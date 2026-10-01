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

if enabled and now >= expires_at:
    enabled = False
    aa["enabled"] = False
    cfg.setdefault("notifications", {})["enable_notch_popup"] = True
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)

if action in ("on", "enable", "start"):
    try:
        dur_mins = float(duration_arg)
    except ValueError:
        dur_mins = 15.0
    aa["enabled"] = True
    aa["duration_minutes"] = dur_mins
    aa["expires_at"] = now + (dur_mins * 60.0)
    cfg["auto_approve"] = aa
    cfg.setdefault("notifications", {})["enable_notch_popup"] = False
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)
    print(f"⚡🟢 Auto-Approve ENABLED for {int(dur_mins)} minutes!")
    print(f"🔕 Notch notifications automatically disabled.")
    print(f"🛡️ Artifacts and plans still require manual review.")
    print(f"⏱️ Will automatically disable at: {time.strftime('%H:%M:%S', time.localtime(aa['expires_at']))}")

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
    if enabled and now < expires_at:
        aa["enabled"] = False
        aa["expires_at"] = 0.0
        cfg.setdefault("notifications", {})["enable_notch_popup"] = True
        print("⚡⚪ Auto-Approve DISABLED.")
        print("🔔 Notch notifications automatically restored (ON).")
    else:
        try:
            dur_mins = float(duration_arg)
        except ValueError:
            dur_mins = aa.get("duration_minutes", 15.0)
        aa["enabled"] = True
        aa["duration_minutes"] = dur_mins
        aa["expires_at"] = now + (dur_mins * 60.0)
        cfg.setdefault("notifications", {})["enable_notch_popup"] = False
        print(f"⚡🟢 Auto-Approve ENABLED for {int(dur_mins)} minutes!")
        print(f"🔕 Notch notifications automatically disabled.")
    cfg["auto_approve"] = aa
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)

elif action in ("status", "check"):
    if enabled and now < expires_at:
        rem_sec = int(expires_at - now)
        rem_min = rem_sec // 60
        rem_s = rem_sec % 60
        print(f"⚡🟢 Auto-Approve is ACTIVE")
        print(f"⏱️ Remaining: {rem_min}m {rem_s}s (configured: {int(aa.get('duration_minutes', 15))}m)")
        print(f"🛡️ Artifact review gate: ENFORCED (plans require review)")
    else:
        print("⚡⚪ Auto-Approve is OFF (Normal manual approval mode)")
        print(f"Default duration: {int(aa.get('duration_minutes', 15))} minutes")
        print("To enable: ./auto-approve.sh on [minutes]")

else:
    print(f"Usage: {sys.argv[0]} [on|off|toggle|status] [duration_in_minutes]")
    sys.exit(1)
PYEOF
