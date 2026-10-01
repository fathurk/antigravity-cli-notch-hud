#!/usr/bin/env python3
import sys
import json
import os
import time
import subprocess
import re

SAFE_TOOLS = {
    "view_file", "grep_search", "list_dir", "find_by_name", 
    "read_url_content", "schedule", "manage_task", "send_message",
    "invoke_subagent", "manage_subagents"
}

SAFE_GIT_SUBCOMMANDS = {
    "status", "diff", "log", "branch", "fetch", "show", "rev-parse",
    "remote", "tag", "ls-files", "check-ignore", "pull", "describe",
    "cat-file", "shortlog", "version", "help"
}

SAFE_COMMAND_PREFIXES = [
    "node -e", "python3 -c", "python -c", "jq", "grep", "rg", "cat", "head", "tail", "wc",
    "ls", "pwd", "diff", "stat", "awk", "which", "sw_vers", "swiftc", "swift",
    "echo", "printf", "date", "uptime", "uname", "find", "fd",
    "notch-hud", "notch-prompt", "antigravity-bar"
]

def load_config(script_dir: str) -> dict:
    config_path = os.path.join(script_dir, "config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "notifications": {
            "approval_timeout_seconds": 60,
            "toast_duration_seconds": 3.0,
            "enable_notch_popup": True
        },
        "audio": {
            "sound_enabled": True,
            "prompt_sound": "Glass",
            "toast_sound": "Hero"
        },
        "appearance": {
            "font_size_scale": 1.0,
            "notch_prompt_width": 480,
            "notch_prompt_height": 158
        },
        "auto_approve": {
            "enabled": False,
            "duration_minutes": 15.0,
            "expires_at": 0.0
        }
    }

def is_safe_git_command(cmd: str) -> bool:
    tokens = cmd.split()
    if not tokens or tokens[0] != "git":
        return False
    i = 1
    while i < len(tokens):
        tok = tokens[i]
        if tok in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        return tok in SAFE_GIT_SUBCOMMANDS
    return False

def is_safe_command(cmd: str) -> bool:
    cmd_clean = cmd.strip()
    if not cmd_clean:
        return True
    if any(s in cmd_clean for s in ("start.sh", "stop.sh", "build.sh", "notch-hud", "antigravity-bar", "pkill")):
        return True
    parts = re.split(r'\||&&|;', cmd_clean)
    all_parts_safe = True
    for p in parts:
        p_clean = p.strip()
        if not p_clean:
            continue
        if is_safe_git_command(p_clean):
            continue
        if any(p_clean.startswith(prefix) for prefix in SAFE_COMMAND_PREFIXES):
            continue
        all_parts_safe = False
        break
    if all_parts_safe and len(parts) > 0:
        return True
    return False

def is_auto_approve_active(config: dict, script_dir: str) -> bool:
    aa = config.get("auto_approve", {})
    if not aa.get("enabled", False):
        return False
    expires_at = aa.get("expires_at", 0.0)
    now = time.time()
    if now >= expires_at:
        # Expired! Auto-disable in config.json and restore notifications
        aa["enabled"] = False
        config.setdefault("notifications", {})["enable_notch_popup"] = True
        try:
            cfg_path = os.path.join(script_dir, "config.json")
            with open(cfg_path, "w") as f:
                json.dump(config, f, indent=2)
        except Exception:
            pass
        return False
    return True

def is_artifact_requiring_review(tool_name: str, args: dict, input_data: dict = None) -> bool:
    """
    Check if a tool call creates or modifies an artifact or plan requiring user review.
    Even when Auto-Approve mode is ON, these operations must still require manual user review.
    """
    # 1. write_to_file with ArtifactMetadata requesting feedback or user review
    if tool_name == "write_to_file":
        artifact_meta = args.get("ArtifactMetadata")
        if artifact_meta and isinstance(artifact_meta, dict):
            if artifact_meta.get("RequestFeedback", False) or artifact_meta.get("UserFacing", False):
                return True

    # 2. Files written or modified in brain / artifact directories or plan files
    if tool_name in ("write_to_file", "replace_file_content"):
        target = args.get("TargetFile", "")
        basename = os.path.basename(target).lower()
        if "plan" in basename:
            return True
        if ".gemini/antigravity-cli/brain" in target or ".gemini/antigravity/artifacts" in target:
            if target.endswith(".md"):
                return True
        if input_data:
            artifact_dir = input_data.get("artifactDirectoryPath", "")
            if artifact_dir and target.startswith(artifact_dir) and target.endswith(".md"):
                return True

    return False

def is_safe_action(tool_name: str, args: dict, input_data: dict = None) -> bool:
    # Artifacts requiring review are never safe actions
    if is_artifact_requiring_review(tool_name, args, input_data):
        return False

    if tool_name in SAFE_TOOLS:
        return True

    if tool_name == "run_command":
        cmd = args.get("CommandLine", "")
        if is_safe_command(cmd):
            return True

    if tool_name in ("write_to_file", "replace_file_content"):
        target = args.get("TargetFile", "")
        if "PLAN_LOG.md" in target or "state/" in target or "config.json" in target or "scratch/" in target or "tools/notch-hud" in target:
            return True

    return False

def extract_action_details(tool_name: str, args: dict):
    summary = args.get("toolSummary", "") or args.get("toolAction", "")
    instruction = args.get("Instruction", "") or args.get("Description", "")
    
    if tool_name == "run_command":
        cmd = args.get("CommandLine", "Terminal Command")
        desc = summary or instruction or "Execute terminal command"
        return desc, cmd

    elif tool_name in ("write_to_file", "replace_file_content"):
        target = args.get("TargetFile", "")
        basename = os.path.basename(target)
        action_type = "Create" if tool_name == "write_to_file" else "Edit"
        
        if instruction:
            desc = f"{action_type} {basename}: {instruction}"
        elif summary:
            desc = f"{summary} ({basename})"
        else:
            desc = f"{action_type} file {basename}"
            
        return desc, target

    else:
        desc = summary or instruction or f"Execute {tool_name}"
        action = json.dumps(args, separators=(',', ':'))[:90]
        return desc, action

def append_to_history(state_dir: str, item: dict):
    history_file = os.path.join(state_dir, "history.json")
    history = []
    if os.path.exists(history_file):
        try:
            with open(history_file, "r") as f:
                history = json.load(f)
        except Exception:
            history = []
    history.append(item)
    history = history[-20:]
    try:
        with open(history_file, "w") as f:
            json.dump(history, f, indent=2)
    except Exception:
        pass

def handle_stop_hook(script_dir: str, bin_path: str, config: dict):
    raw_input = ""
    try:
        raw_input = sys.stdin.read()
    except Exception:
        pass

    title = "Antigravity CLI"
    message = "✨ Task completed • Waiting for your input"

    if raw_input.strip():
        try:
            data = json.loads(raw_input)
            artifact_dir = data.get("artifactDirectoryPath", "")
            if artifact_dir and os.path.exists(artifact_dir):
                plan_file = os.path.join(artifact_dir, "plan.md")
                if os.path.exists(plan_file):
                    mtime = os.path.getmtime(plan_file)
                    if (time.time() - mtime) < 45:
                        title = "Antigravity Plan Ready"
                        message = "📋 Plan is ready • Click Proceed in UI or type /build"
        except Exception:
            pass

    toast_sound = config.get("audio", {}).get("toast_sound", "Hero")
    if not config.get("audio", {}).get("sound_enabled", True):
        toast_sound = "none"

    enable_notch = config.get("notifications", {}).get("enable_notch_popup", True)
    if enable_notch and os.path.exists(bin_path):
        subprocess.Popen(
            [
                bin_path,
                "--mode", "toast",
                "--title", title,
                "--message", message,
                "--sound", toast_sound
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            close_fds=True
        )

    print(json.dumps({}))
    sys.stdout.flush()
    sys.exit(0)

def main():
    try:
        _main_internal()
    except Exception:
        # Fail-safe: Always allow tool execution if any unexpected error occurs
        print(json.dumps({"decision": "allow"}))
        sys.stdout.flush()
        sys.exit(0)

def _main_internal():
    script_dir = os.path.dirname(os.path.realpath(__file__))
    bin_path = os.path.join(script_dir, "bin", "notch-prompt")
    state_dir = os.path.join(script_dir, "state")
    os.makedirs(state_dir, exist_ok=True)

    config = load_config(script_dir)
    pending_file = os.path.join(state_dir, "pending.json")
    decision_file = os.path.join(state_dir, "decision.json")

    # If called with --stop-hook (Stop event)
    if len(sys.argv) > 1 and sys.argv[1] == "--stop-hook":
        handle_stop_hook(script_dir, bin_path, config)

    # Read stdin for PreToolUse
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            print(json.dumps({"decision": "allow"}))
            sys.exit(0)
        data = json.loads(raw_input)
    except Exception:
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    tool_call = data.get("toolCall", {})
    tool_name = tool_call.get("name", "")
    tool_args = tool_call.get("args", {})

    # Dedicated handler for ask_question: Show question toast and allow seamlessly
    if tool_name == "ask_question":
        q_list = tool_args.get("questions", [])
        q_title = "❓ Question from Agent"
        q_msg = "Please select your option in the chat window"
        if q_list and isinstance(q_list, list):
            first_q = q_list[0]
            if isinstance(first_q, dict):
                q_prompt = first_q.get("question", "")
                if q_prompt:
                    q_msg = f"{q_prompt[:60]}... • Reply in chat" if len(q_prompt) > 60 else f"{q_prompt} • Reply in chat"
        
        prompt_sound = config.get("audio", {}).get("prompt_sound", "Glass")
        if not config.get("audio", {}).get("sound_enabled", True):
            prompt_sound = "none"

        if os.path.exists(bin_path):
            subprocess.Popen(
                [
                    bin_path,
                    "--mode", "toast",
                    "--title", q_title,
                    "--message", q_msg,
                    "--sound", prompt_sound
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                close_fds=True
            )
        print(json.dumps({"decision": "allow"}))
        sys.stdout.flush()
        sys.exit(0)

    is_artifact = is_artifact_requiring_review(tool_name, tool_args, data)
    auto_approve_active = is_auto_approve_active(config, script_dir)

    # Check if tool is safe / read-only -> Auto allow silently
    if not is_artifact and is_safe_action(tool_name, tool_args, data):
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    description, action_code = extract_action_details(tool_name, tool_args)
    if is_artifact:
        description = f"📋 Artifact Review: {description}"
    req_id = f"req-{int(time.time() * 1000)}"

    # If Auto-Approve is ON and NOT an artifact requiring review -> Auto allow immediately!
    if auto_approve_active and not is_artifact:
        append_to_history(state_dir, {
            "id": req_id,
            "tool": tool_name,
            "description": description,
            "action": action_code,
            "decision": "allow",
            "auto_approved": True,
            "timestamp": time.time()
        })
        print(json.dumps({"decision": "allow"}))
        sys.stdout.flush()
        sys.exit(0)

    # 1. Clean previous decision file
    if os.path.exists(decision_file):
        try:
            os.remove(decision_file)
        except Exception:
            pass

    # 2. Write pending request to state for Menu Bar App
    pending_payload = {
        "id": req_id,
        "tool": f"{tool_name} (Artifact Review)" if is_artifact else tool_name,
        "description": description,
        "action": action_code,
        "timestamp": time.time()
    }
    with open(pending_file, "w") as f:
        json.dump(pending_payload, f, indent=2)

    # 3. Launch Notch HUD overlay if enabled
    proc = None
    enable_notch = config.get("notifications", {}).get("enable_notch_popup", True)
    timeout_sec = config.get("notifications", {}).get("approval_timeout_seconds", 60)
    prompt_sound = config.get("audio", {}).get("prompt_sound", "Glass")
    if not config.get("audio", {}).get("sound_enabled", True):
        prompt_sound = "none"

    if enable_notch and os.path.exists(bin_path):
        proc = subprocess.Popen([
            bin_path,
            "--mode", "prompt",
            "--tool", tool_name,
            "--description", description,
            "--action", action_code,
            "--timeout", str(timeout_sec),
            "--sound", prompt_sound
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    # 4. Wait for decision from either Menu Bar or Notch HUD
    decision = None
    start_time = time.time()
    max_wait_seconds = 600.0

    while time.time() - start_time < max_wait_seconds:
        if os.path.exists(decision_file):
            try:
                with open(decision_file, "r") as f:
                    dec_data = json.load(f)
                if dec_data.get("id") == req_id or dec_data.get("decision"):
                    decision = dec_data.get("decision", "allow")
                    break
            except Exception:
                pass

        if proc and proc.poll() is not None:
            stdout, _ = proc.communicate()
            match = re.search(r'\{.*\}', stdout)
            notch_decision = None
            if match:
                try:
                    res_json = json.loads(match.group(0))
                    notch_decision = res_json.get("decision")
                except Exception:
                    pass

            if notch_decision == "allow" or proc.returncode == 0:
                decision = "allow"
                break
            elif notch_decision == "deny" or (proc.returncode == 1 and notch_decision != "dismiss"):
                decision = "deny"
                break
            elif notch_decision == "dismiss" or proc.returncode == 2:
                proc = None

        time.sleep(0.15)

    if decision is None:
        decision = "deny"

    if proc and proc.poll() is None:
        try:
            proc.terminate()
        except Exception:
            pass

    if os.path.exists(pending_file):
        try:
            os.remove(pending_file)
        except Exception:
            pass

    if os.path.exists(decision_file):
        try:
            os.remove(decision_file)
        except Exception:
            pass

    append_to_history(state_dir, {
        "id": req_id,
        "tool": tool_name,
        "description": description,
        "action": action_code,
        "decision": decision,
        "timestamp": time.time()
    })

    if decision == "allow":
        print(json.dumps({"decision": "allow"}))
    else:
        print(json.dumps({"decision": "deny", "reason": "Denied by user via Notch/Menu Bar"}))

if __name__ == "__main__":
    main()
