#!/usr/bin/env python3
import sys
import json
import os
import time
import subprocess
import re

SAFE_TOOLS = {
    "view_file", "read_file", "grep_search", "list_dir", "find_by_name", 
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
    duration_mins = aa.get("duration_minutes", 15.0)
    expires_at = aa.get("expires_at", 0.0)
    # Unlimited / no time limit when duration_minutes == 0 or expires_at <= 0
    if duration_mins == 0 or expires_at <= 0.0:
        return True
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

def update_artifacts_state(script_dir: str, artifact_dir: str = None, target_file: str = None, metadata: dict = None):
    state_dir = os.path.join(script_dir, "state")
    os.makedirs(state_dir, exist_ok=True)
    artifacts_path = os.path.join(state_dir, "artifacts.json")

    existing_items = []
    if os.path.exists(artifacts_path):
        try:
            with open(artifacts_path, "r") as f:
                existing_items = json.load(f)
        except Exception:
            existing_items = []

    items_by_path = {item["path"]: item for item in existing_items if isinstance(item, dict) and "path" in item}

    if target_file and target_file.endswith(".md"):
        fname = os.path.basename(target_file)
        req_feedback = False
        summary = ""
        is_approved = False
        if metadata:
            req_feedback = metadata.get("RequestFeedback", metadata.get("requestFeedback", False))
            summary = metadata.get("Summary", metadata.get("summary", ""))
            is_approved = metadata.get("Approved", metadata.get("approved", False)) or metadata.get("userApproved", False) or metadata.get("status") in ("approved", "reviewed")
        elif "plan" in fname.lower():
            meta_path = target_file + ".metadata.json"
            if os.path.exists(meta_path):
                try:
                    with open(meta_path, "r") as mf:
                        mdata = json.load(mf)
                        req_feedback = mdata.get("requestFeedback", False)
                        summary = mdata.get("summary", "")
                        is_approved = mdata.get("approved", False) or mdata.get("userApproved", False) or mdata.get("status") in ("approved", "reviewed")
                except Exception:
                    pass
            else:
                req_feedback = True
                summary = "Plan artifact ready for review"

        prev_item = items_by_path.get(target_file, {})
        prev_status = prev_item.get("status")
        prev_approved = prev_item.get("approved", False)

        if is_approved or prev_approved or (prev_status == "reviewed" and not req_feedback):
            status = "reviewed"
            req_feedback = False
            is_approved = True
        else:
            status = "pending_review" if req_feedback else "completed"

        items_by_path[target_file] = {
            "id": fname,
            "name": fname,
            "path": target_file,
            "summary": summary,
            "requestFeedback": req_feedback,
            "approved": is_approved,
            "updatedAt": time.time(),
            "status": status
        }

    if artifact_dir and os.path.exists(artifact_dir):
        for fname in os.listdir(artifact_dir):
            if fname.endswith(".md") and not fname.startswith("."):
                fpath = os.path.join(artifact_dir, fname)
                meta_path = fpath + ".metadata.json"
                req_feedback = ("plan" in fname.lower())
                summary = ""
                is_approved = False
                if os.path.exists(meta_path):
                    try:
                        with open(meta_path, "r") as mf:
                            mdata = json.load(mf)
                            req_feedback = mdata.get("requestFeedback", req_feedback)
                            summary = mdata.get("summary", summary)
                            is_approved = mdata.get("approved", False) or mdata.get("userApproved", False) or mdata.get("status") in ("approved", "reviewed")
                    except Exception:
                        pass
                try:
                    mtime = os.path.getmtime(fpath)
                except Exception:
                    mtime = time.time()

                prev_item = items_by_path.get(fpath, {})
                prev_status = prev_item.get("status")
                prev_approved = prev_item.get("approved", False)

                if is_approved or prev_approved or (prev_status == "reviewed" and not req_feedback):
                    new_status = "reviewed"
                    req_feedback = False
                    is_approved = True
                else:
                    new_status = "pending_review" if req_feedback else "completed"

                items_by_path[fpath] = {
                    "id": fname,
                    "name": fname,
                    "path": fpath,
                    "summary": summary,
                    "requestFeedback": req_feedback,
                    "approved": is_approved,
                    "updatedAt": mtime,
                    "status": new_status
                }

    sorted_items = sorted(items_by_path.values(), key=lambda x: x.get("updatedAt", 0), reverse=True)
    try:
        tmp_artifacts = artifacts_path + ".tmp"
        with open(tmp_artifacts, "w") as f:
            json.dump(sorted_items, f, indent=2)
        os.replace(tmp_artifacts, artifacts_path)
    except Exception:
        pass

    # Update session status
    pending_items = [it for it in sorted_items if it.get("requestFeedback") or it.get("status") == "pending_review"]
    pending_count = len(pending_items)
    session_status = "waiting_review" if pending_count > 0 else "active"
    session_path = os.path.join(state_dir, "session.json")
    try:
        session_data = {
            "status": session_status,
            "pendingReview": pending_count > 0,
            "pendingCount": pending_count,
            "unblocked": pending_count == 0,
            "lastUpdated": time.time()
        }
        with open(session_path + ".tmp", "w") as f:
            json.dump(session_data, f, indent=2)
        os.replace(session_path + ".tmp", session_path)
    except Exception:
        pass

    return sorted_items

def approve_artifact(script_dir: str, artifact_path: str):
    state_dir = os.path.join(script_dir, "state")
    os.makedirs(state_dir, exist_ok=True)

    # 1. Update artifact metadata file
    meta_path = artifact_path + ".metadata.json"
    meta_dict = {}
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r") as f:
                meta_dict = json.load(f)
        except Exception:
            meta_dict = {}
    meta_dict["requestFeedback"] = False
    meta_dict["approved"] = True
    meta_dict["userApproved"] = True
    meta_dict["status"] = "approved"
    meta_dict["updatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if "summary" not in meta_dict:
        meta_dict["summary"] = os.path.basename(artifact_path)
    if "userFacing" not in meta_dict:
        meta_dict["userFacing"] = True
    try:
        with open(meta_path + ".tmp", "w") as f:
            json.dump(meta_dict, f, indent=2)
        os.replace(meta_path + ".tmp", meta_path)
    except Exception:
        pass

    # 2. Update artifacts state
    art_dir = os.path.dirname(artifact_path)
    update_artifacts_state(script_dir, artifact_dir=art_dir, target_file=artifact_path, metadata=meta_dict)

    # 3. Unblock waiting agent session by writing allow decision
    decision_path = os.path.join(state_dir, "decision.json")
    try:
        with open(decision_path + ".tmp", "w") as f:
            json.dump({
                "decision": "allow",
                "action": "proceed",
                "status": "approved",
                "path": artifact_path,
                "timestamp": time.time()
            }, f, indent=2)
        os.replace(decision_path + ".tmp", decision_path)
    except Exception:
        pass

    # 4. Remove pending.json if any
    pending_path = os.path.join(state_dir, "pending.json")
    if os.path.exists(pending_path):
        try:
            os.remove(pending_path)
        except Exception:
            pass

    # 5. Ensure session.json is updated to active & unblocked
    session_path = os.path.join(state_dir, "session.json")
    try:
        with open(session_path + ".tmp", "w") as f:
            json.dump({
                "status": "active",
                "pendingReview": False,
                "pendingCount": 0,
                "unblocked": True,
                "lastApprovedArtifact": artifact_path,
                "lastUpdated": time.time()
            }, f, indent=2)
        os.replace(session_path + ".tmp", session_path)
    except Exception:
        pass

def is_safe_action(tool_name: str, args: dict, input_data: dict = None) -> bool:
    if tool_name in SAFE_TOOLS:
        return True

    if tool_name == "run_command":
        cmd = args.get("CommandLine", "")
        if is_safe_command(cmd):
            return True

    if tool_name in ("write_to_file", "replace_file_content", "write_file", "edit_file"):
        # Artifact creation with ArtifactMetadata
        if args.get("ArtifactMetadata"):
            return True

        target = args.get("TargetFile", "") or args.get("Path", "")
        basename = os.path.basename(target).lower()

        # Plan logs, progress logs, task logs
        if "plan_log" in basename or "plan-log" in basename or "plan.md" in basename or basename == "plan_log.md":
            return True

        # Internal state, config, scratch, tools/notch-hud
        if "state/" in target or "config.json" in target or "scratch/" in target or "tools/notch-hud" in target:
            return True

        # Brain / artifact directories
        if ".gemini/antigravity-cli/brain" in target or ".gemini/antigravity/artifacts" in target:
            return True
        if input_data:
            artifact_dir = input_data.get("artifactDirectoryPath", "")
            if artifact_dir and target.startswith(artifact_dir):
                return True

        # All markdown documentation and notes files
        if target.endswith(".md"):
            return True

    return False

def extract_action_details(tool_name: str, args: dict):
    summary = args.get("toolSummary", "") or args.get("toolAction", "")
    instruction = args.get("Instruction", "") or args.get("Description", "")
    
    if tool_name == "run_command":
        cmd = args.get("CommandLine", "Terminal Command")
        desc = summary or instruction or "Execute terminal command"
        return desc, cmd

    elif tool_name in ("write_to_file", "replace_file_content", "write_file", "edit_file"):
        target = args.get("TargetFile", "") or args.get("Path", "")
        basename = os.path.basename(target)
        action_type = "Create" if tool_name in ("write_to_file", "write_file") else "Edit"
        
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
    recent_plan = None
    plan_path = ""

    if raw_input.strip():
        try:
            data = json.loads(raw_input)
            artifact_dir = data.get("artifactDirectoryPath", "")
            if artifact_dir and os.path.exists(artifact_dir):
                artifacts = update_artifacts_state(script_dir, artifact_dir)
                for item in artifacts:
                    if item.get("requestFeedback") or (time.time() - item.get("updatedAt", 0) < 120 and "plan" in item.get("name", "").lower()):
                        recent_plan = item["name"]
                        plan_path = item["path"]
                        title = "Antigravity Plan Ready"
                        message = "📋 Plan ready • Click Review in Toast/Menu Bar"
                        break
                if not recent_plan and artifacts:
                    latest = artifacts[0]
                    if time.time() - latest.get("updatedAt", 0) < 60:
                        recent_plan = latest["name"]
                        plan_path = latest["path"]
                        if "walkthrough" in latest["name"].lower():
                            title = "Walkthrough Ready"
                            message = "📋 Walkthrough ready • Click Review"
                        else:
                            title = "Artifact Ready"
                            message = f"📋 {latest['name']} ready • Click Review"
        except Exception:
            pass

    toast_sound = config.get("audio", {}).get("toast_sound", "Hero")
    if not config.get("audio", {}).get("sound_enabled", True):
        toast_sound = "none"

    enable_notch = config.get("notifications", {}).get("enable_notch_popup", True)
    sound_enabled = config.get("audio", {}).get("sound_enabled", True)

    if os.path.exists(bin_path):
        if enable_notch or recent_plan:
            toast_args = [
                bin_path,
                "--mode", "toast",
                "--title", title,
                "--message", message,
                "--sound", toast_sound
            ]
            if plan_path:
                toast_args.extend(["--action", plan_path])
            subprocess.Popen(
                toast_args,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                close_fds=True
            )
        elif sound_enabled and toast_sound != "none":
            subprocess.Popen(
                ["afplay", f"/System/Library/Sounds/{toast_sound}.aiff"],
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

    # If called with --approve-artifact <path>
    if len(sys.argv) > 1 and sys.argv[1] == "--approve-artifact":
        target = sys.argv[2] if len(sys.argv) > 2 else ""
        if target:
            approve_artifact(script_dir, target)
        print(json.dumps({"status": "approved", "path": target, "decision": "allow"}))
        sys.exit(0)

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

    auto_approve_active = is_auto_approve_active(config, script_dir)

    # Check if tool is safe / read-only / artifact creation -> Auto allow silently
    if is_safe_action(tool_name, tool_args, data):
        if tool_name in ("write_to_file", "replace_file_content", "write_file", "edit_file"):
            target = tool_args.get("TargetFile", "") or tool_args.get("Path", "")
            if target.endswith(".md"):
                meta = tool_args.get("ArtifactMetadata")
                art_dir = data.get("artifactDirectoryPath") if data else None
                try:
                    update_artifacts_state(script_dir, art_dir, target, meta)
                except Exception:
                    pass
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    description, action_code = extract_action_details(tool_name, tool_args)
    req_id = f"req-{int(time.time() * 1000)}"

    # If Auto-Approve is ON -> Auto allow immediately!
    if auto_approve_active:
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
