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

SAFE_COMMAND_PREFIXES = [
    "git status", "git diff", "git log", "git branch", "git fetch",
    "git show", "git rev-parse", "git remote", "git tag", "git ls-files",
    "git check-ignore", "git pull",
    "node -e", "python3 -c", "jq", "grep", "cat", "head", "tail", "wc",
    "ls", "pwd", "diff", "stat", "awk", "which", "sw_vers", "swiftc", "swift",
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
        }
    }

def is_safe_command(cmd: str) -> bool:
    cmd_clean = cmd.strip()
    if any(s in cmd_clean for s in ("start.sh", "stop.sh", "build.sh", "notch-hud", "antigravity-bar", "pkill")):
        return True
    for prefix in SAFE_COMMAND_PREFIXES:
        if cmd_clean.startswith(prefix):
            return True
    return False

def is_safe_action(tool_name: str, args: dict) -> bool:
    if tool_name in SAFE_TOOLS:
        return True

    if tool_name == "run_command":
        cmd = args.get("CommandLine", "")
        if is_safe_command(cmd):
            return True

    if tool_name in ("write_to_file", "replace_file_content"):
        target = args.get("TargetFile", "")
        if "PLAN_LOG.md" in target or "state/" in target or "config.json" in target or ".gemini/antigravity-cli/brain" in target or target.endswith(".md") or "tools/notch-hud" in target:
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

    if os.path.exists(bin_path):
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

    # Check if tool is safe / read-only -> Auto allow silently
    if is_safe_action(tool_name, tool_args):
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    description, action_code = extract_action_details(tool_name, tool_args)
    req_id = f"req-{int(time.time() * 1000)}"

    # 1. Clean previous decision file
    if os.path.exists(decision_file):
        try:
            os.remove(decision_file)
        except Exception:
            pass

    # 2. Write pending request to state for Menu Bar App
    pending_payload = {
        "id": req_id,
        "tool": tool_name,
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
    # Global hook wait timeout (e.g. 10 minutes)
    max_wait_seconds = 600.0

    while time.time() - start_time < max_wait_seconds:
        # Check if decision was written via Menu Bar app
        if os.path.exists(decision_file):
            try:
                with open(decision_file, "r") as f:
                    dec_data = json.load(f)
                if dec_data.get("id") == req_id or dec_data.get("decision"):
                    decision = dec_data.get("decision", "allow")
                    break
            except Exception:
                pass

        # Check if Notch HUD process responded
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
                # Notch HUD dismissed after timeout -> Keep waiting in Menu Bar!
                proc = None

        time.sleep(0.15)

    if decision is None:
        decision = "deny"

    # Clean up
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

    # Save to history
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
