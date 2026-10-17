#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: config.json not found at $CONFIG_FILE"
    exit 1
fi

ACTION="${1:-status}"
DURATION="${2:-15}"

python3 - "$ACTION" "$DURATION" "$CONFIG_FILE" << 'PYEOF'
import sys
import json
import time

action = sys.argv[1].lower() if len(sys.argv) > 1 else "status"
duration_arg = sys.argv[2] if len(sys.argv) > 2 else "15"
config_path = sys.argv[3]

try:
    with open(config_path, "r") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"❌ Failed to load config: {e}")
    sys.exit(1)

aa = cfg.get("auto_approve", {})
enabled = aa.get("enabled", False)
expires_at = aa.get("expires_at", 0.0)
now = time.time()

if enabled and aa.get("duration_minutes", 15.0) > 0 and expires_at > 0 and now >= expires_at:
    enabled = False
    aa["enabled"] = False
    cfg.setdefault("notifications", {})["enable_notch_popup"] = True
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)

if action in ("on", "enable", "start"):
    dur_str = str(duration_arg).strip().lower()
    if dur_str in ("0", "unlimited", "infinity", "inf", "forever", "none", "no-limit"):
        dur_mins = 0.0
        aa["enabled"] = True
        aa["duration_minutes"] = 0.0
        aa["expires_at"] = 0.0
        cfg["auto_approve"] = aa
        cfg.setdefault("notifications", {})["enable_notch_popup"] = False
        with open(config_path, "w") as f:
            json.dump(cfg, f, indent=2)
        print("⚡🟢 Auto-Approve ENABLED with NO TIME LIMIT (∞)!")
        print("🔕 Notch notifications automatically disabled.")
        print("📋 Artifact creation auto-approved • Plans reviewed in UI.")
        print("To disable anytime, run: ./auto-approve.sh off")
    else:
        try:
            dur_mins = float(duration_arg)
        except ValueError:
            dur_mins = 15.0
        if dur_mins == 0:
            aa["enabled"] = True
            aa["duration_minutes"] = 0.0
            aa["expires_at"] = 0.0
            print("⚡🟢 Auto-Approve ENABLED with NO TIME LIMIT (∞)!")
        else:
            aa["enabled"] = True
            aa["duration_minutes"] = dur_mins
            aa["expires_at"] = now + (dur_mins * 60.0)
            print(f"⚡🟢 Auto-Approve ENABLED for {int(dur_mins)} minutes!")
            print(f"⏱️ Will automatically disable at: {time.strftime('%H:%M:%S', time.localtime(aa['expires_at']))}")
        cfg["auto_approve"] = aa
        cfg.setdefault("notifications", {})["enable_notch_popup"] = False
        with open(config_path, "w") as f:
            json.dump(cfg, f, indent=2)
        print("🔕 Notch notifications automatically disabled.")
        print("📋 Artifact creation auto-approved • Plans reviewed in UI.")

elif action in ("off", "disable", "stop"):
    aa["enabled"] = False
    aa["expires_at"] = 0.0
    cfg["auto_approve"] = aa
    cfg.setdefault("notifications", {})["enable_notch_popup"] = True
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)
    print("⚡⚪ Auto-Approve DISABLED. Normal manual approvals restored.")
    print("🔔 Notch notifications automatically restored (ON).")

elif action in ("toggle"):
    is_active = enabled and (aa.get("duration_minutes", 15.0) == 0 or now < expires_at)
    if is_active:
        aa["enabled"] = False
        aa["expires_at"] = 0.0
        cfg.setdefault("notifications", {})["enable_notch_popup"] = True
        print("⚡⚪ Auto-Approve DISABLED.")
        print("🔔 Notch notifications automatically restored (ON).")
    else:
        dur_str = str(duration_arg).strip().lower()
        if dur_str in ("0", "unlimited", "infinity", "inf", "forever", "none", "no-limit"):
            dur_mins = 0.0
            aa["expires_at"] = 0.0
            print("⚡🟢 Auto-Approve ENABLED with NO TIME LIMIT (∞)!")
        else:
            try:
                dur_mins = float(duration_arg)
            except ValueError:
                dur_mins = aa.get("duration_minutes", 15.0)
            if dur_mins == 0:
                aa["expires_at"] = 0.0
                print("⚡🟢 Auto-Approve ENABLED with NO TIME LIMIT (∞)!")
            else:
                aa["expires_at"] = now + (dur_mins * 60.0)
                print(f"⚡🟢 Auto-Approve ENABLED for {int(dur_mins)} minutes!")
        aa["enabled"] = True
        aa["duration_minutes"] = dur_mins
        cfg.setdefault("notifications", {})["enable_notch_popup"] = False
        print("🔕 Notch notifications automatically disabled.")
    cfg["auto_approve"] = aa
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)

elif action in ("status", "check"):
    is_active = enabled and (aa.get("duration_minutes", 15.0) == 0 or now < expires_at)
    if is_active:
        if aa.get("duration_minutes", 15.0) == 0:
            print("⚡🟢 Auto-Approve is ACTIVE (Unlimited / No time limit ∞)")
        else:
            rem_sec = int(expires_at - now)
            rem_min = rem_sec // 60
            rem_s = rem_sec % 60
            print("⚡🟢 Auto-Approve is ACTIVE")
            print(f"⏱️ Remaining: {rem_min}m {rem_s}s (configured: {int(aa.get('duration_minutes', 15))}m)")
        print("📋 Artifact creation: AUTO-APPROVED (plans reviewed in UI)")
    else:
        print("⚡⚪ Auto-Approve is OFF (Normal manual approval mode)")
        cur_dur = aa.get('duration_minutes', 15)
        dur_display = "No limit (∞)" if cur_dur == 0 else f"{int(cur_dur)} minutes"
        print(f"Configured duration: {dur_display}")
        print("To enable: ./auto-approve.sh on [minutes|unlimited]")

else:
    print(f"Usage: {sys.argv[0]} [on|off|toggle|status] [duration_in_minutes|unlimited]")
    sys.exit(1)
PYEOF
