# Antigravity CLI Dynamic Notch HUD & Menu Bar Hub 🪐⚡

A native macOS companion for [Google Antigravity CLI (`agy`)](https://antigravity.google) that brings interactive approval prompts, turn-completion notifications, and a persistent menu bar hub directly to your MacBook camera notch and macOS status bar.

Never miss a permission approval prompt again while multitasking across other macOS applications!

---

## ✨ Features

- 📱 **Dynamic Notch Overlay**: Automatically detects your MacBook camera notch geometry (via AppKit `safeAreaInsets`) and expands smoothly under the notch (or floats as a Dynamic Island capsule on external displays).
- ⚡ **Persistent Top Menu Bar App (`⚡ AGY`)**: Lives in your macOS menu bar with real-time pending badges (`⚡ (1)`), dropdown approval cards, and recent activity history.
- 💬 **Rich Descriptions & Context**: Clear, human-readable explanations of why the agent needs permission and exact command/file previews.
- ⌨️ **Keyboard-First & 1-Click Approvals**:
  - <kbd>Return</kbd> / <kbd>Space</kbd> or click **[✓ Approve]** ➔ Agent continues execution immediately.
  - <kbd>Esc</kbd> or click **[✗ Deny]** ➔ Agent halts tool execution.
- ⚙️ **Interactive GUI Toggles**: Toggle Notch popup ON/OFF, mute/unmute audio chimes, adjust font scaling (S/M/L), and choose auto-dismiss timeouts (`5s` / `15s` / `30s`) directly in the Menu Bar dropdown.
- 📄 **Single JSON Configuration (`config.json`)**: All preferences stored in a clean, human-editable JSON configuration file with live auto-reloading.
- 🚀 **Zero Third-Party Dependencies**: Pure native Swift 6 + AppKit/SwiftUI compiled directly with Apple's built-in `swiftc`.

---

## 🛠️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ 🪐 AGY (1)                                                  │ ◀── Top Menu Bar Icon
├─────────────────────────────────────────────────────────────┤
│ ⚡ Antigravity CLI                      🟢 Agent Active     │
│ ─────────────────────────────────────────────────────────── │
│ 🟡 PENDING APPROVAL (1)                                     │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ [run_command] ⏱ 14s remaining                           │ │
│ │ 💬 Staging and committing changes to feat/sorting       │ │
│ │ $ git commit -m "feat: add sorting rules"               │ │
│ │                                                         │ │
│ │      [ ✗ Deny (Esc) ]          [ ✓ Approve (↵) ]        │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ⚙️ PREFERENCES & TOGGLES                                     │
│ 🔔 Notch HUD Popup: [ON]             🔊 Audio: [ON]         │
│ 🔤 Font Scale: [S | M | L]           ⏱️ Timeout: [5s|15s|30s]│
│ ─────────────────────────────────────────────────────────── │
│ 📋 RECENT ACTIVITY                                          │
│ • [replace_file_content] Update services/auth.ts (2m ago)   │
│ ─────────────────────────────────────────────────────────── │
│ config.json                          ❌ Quit AntigravityBar │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Getting Started

### 1. Prerequisites
- macOS 13 (Ventura) or later (Apple Silicon or Intel).
- Built-in `swiftc` compiler (installed automatically with Xcode Command Line Tools: `xcode-select --install`).
- Python 3.

### 2. Clone and Build
```bash
git clone https://github.com/fathurk/antigravity-cli-notch-hud.git
cd antigravity-cli-notch-hud
bash build.sh
```

### 3. Start the Menu Bar App
```bash
bash start.sh
```
To stop the Menu Bar app at any time:
```bash
bash stop.sh
```

---

## 🔌 Hooking into Antigravity CLI

Add the following lifecycle hooks to your project's `.agents/hooks.json` (or globally in `~/.gemini/config/hooks.json`):

```json
{
  "mac-notch-hud": {
    "enabled": true,
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/antigravity-cli-notch-hud/dispatcher.py",
            "timeout": 90
          }
        ]
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "python3 /path/to/antigravity-cli-notch-hud/dispatcher.py --stop-hook",
        "timeout": 10
      }
    ]
  }
}
```

---

## ⚙️ Configuration (`config.json`)

```json
{
  "notifications": {
    "approval_timeout_seconds": 15,
    "toast_duration_seconds": 3.0,
    "enable_notch_popup": true
  },
  "audio": {
    "sound_enabled": true,
    "prompt_sound": "Glass",
    "toast_sound": "Hero"
  },
  "appearance": {
    "font_size_scale": 1.0,
    "notch_prompt_width": 480,
    "notch_prompt_height": 158,
    "notch_toast_width": 380,
    "notch_toast_height": 46
  }
}
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
