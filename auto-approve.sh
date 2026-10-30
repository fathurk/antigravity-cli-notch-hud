#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: config.json not found at $CONFIG_FILE"
    exit 1
fi

ACTION="${1:-status}"

python3 - "$ACTION" "$CONFIG_FILE" << 'PYEOF'
import sys
import json

action = sys.argv[1].lower() if len(sys.argv) > 1 else "status"
config_path = sys.argv[2]

try:
    with open(config_path, "r") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"❌ Failed to load config: {e}")
    sys.exit(1)

aa = cfg.get("auto_approve", {})
enabled = aa.get("enabled", False)

if action in ("on", "enable", "start"):
    aa["enabled"] = True
    cfg["auto_approve"] = aa
    cfg.setdefault("notifications", {})["enable_notch_popup"] = False
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)
    print("⚡🟢 Auto-Approve ENABLED!")
    print("🔕 Notch notifications automatically disabled.")
    print("📋 Artifact creation auto-approved • Plans reviewed in UI.")
    print("To disable anytime, run: ./auto-approve.sh off")

elif action in ("off", "disable", "stop"):
    aa["enabled"] = False
    cfg["auto_approve"] = aa
    cfg.setdefault("notifications", {})["enable_notch_popup"] = True
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)
    print("⚡⚪ Auto-Approve DISABLED. Normal manual approvals restored.")
    print("🔔 Notch notifications automatically restored (ON).")

elif action in ("toggle"):
    if enabled:
        aa["enabled"] = False
        cfg.setdefault("notifications", {})["enable_notch_popup"] = True
        print("⚡⚪ Auto-Approve DISABLED.")
        print("🔔 Notch notifications automatically restored (ON).")
    else:
        aa["enabled"] = True
        cfg.setdefault("notifications", {})["enable_notch_popup"] = False
        print("⚡🟢 Auto-Approve ENABLED!")
        print("🔕 Notch notifications automatically disabled.")
    cfg["auto_approve"] = aa
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)

elif action in ("status", "check"):
    if enabled:
        print("⚡🟢 Auto-Approve is ACTIVE (Persistent ON)")
        print("📋 Artifact creation: AUTO-APPROVED (plans reviewed in UI)")
    else:
        print("⚡⚪ Auto-Approve is OFF (Normal manual approval mode)")
        print("To enable: ./auto-approve.sh on")

else:
    print(f"Usage: {sys.argv[0]} [on|off|toggle|status]")
    sys.exit(1)
PYEOF
