import Cocoa
import SwiftUI

// MARK: - JSON Config Model
struct ConfigJSON: Codable, Equatable {
    struct Notifications: Codable, Equatable {
        var approval_timeout_seconds: Double = 60
        var toast_duration_seconds: Double = 3.0
        var enable_notch_popup: Bool = true
    }
    struct Audio: Codable, Equatable {
        var sound_enabled: Bool = true
        var prompt_sound: String = "Glass"
        var toast_sound: String = "Hero"
    }
    struct Appearance: Codable, Equatable {
        var font_size_scale: Double = 1.0
        var notch_prompt_width: Double = 480
        var notch_prompt_height: Double = 158
        var notch_toast_width: Double = 380
        var notch_toast_height: Double = 46
    }

    var notifications: Notifications = Notifications()
    var audio: Audio = Audio()
    var appearance: Appearance = Appearance()
}

// MARK: - Data Models
struct PendingRequest: Codable, Identifiable, Equatable {
    var id: String
    var tool: String
    var description: String
    var action: String
    var timestamp: Double

    static func == (lhs: PendingRequest, rhs: PendingRequest) -> Bool {
        return lhs.id == rhs.id
    }
}

struct HistoryItem: Codable, Identifiable {
    var id: String
    var tool: String
    var description: String
    var action: String
    var decision: String // "allow" or "deny"
    var timestamp: Double

    var relativeTime: String {
        let diff = Date().timeIntervalSince1970 - timestamp
        if diff < 60 { return "Just now" }
        let mins = Int(diff / 60)
        if mins < 60 { return "\(mins)m ago" }
        let hours = Int(mins / 60)
        return "\(hours)h ago"
    }
}

// MARK: - App State Manager
class AppStateManager: ObservableObject {
    @Published var pendingRequest: PendingRequest? = nil
    @Published var history: [HistoryItem] = []
    @Published var config: ConfigJSON = ConfigJSON()

    let baseDir: URL
    let configPath: URL
    let stateDir: URL
    let pendingFile: URL
    let decisionFile: URL
    let historyFile: URL

    private var timer: Timer?

    init() {
        let currentDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
        self.baseDir = currentDir
        self.configPath = currentDir.appendingPathComponent("config.json")
        self.stateDir = currentDir.appendingPathComponent("state")
        self.pendingFile = stateDir.appendingPathComponent("pending.json")
        self.decisionFile = stateDir.appendingPathComponent("decision.json")
        self.historyFile = stateDir.appendingPathComponent("history.json")

        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        loadConfig()
        reload()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func loadConfig() {
        if FileManager.default.fileExists(atPath: configPath.path),
           let data = try? Data(contentsOf: configPath),
           let cfg = try? JSONDecoder().decode(ConfigJSON.self, from: data) {
            self.config = cfg
        }
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]) {
                try? prettyData.write(to: configPath)
            }
        }
    }

    func toggleNotchPopup() {
        config.notifications.enable_notch_popup.toggle()
        saveConfig()
    }

    func toggleSound() {
        config.audio.sound_enabled.toggle()
        saveConfig()
    }

    func setFontSizeScale(_ scale: Double) {
        config.appearance.font_size_scale = scale
        saveConfig()
    }

    func setTimeout(_ timeout: Double) {
        config.notifications.approval_timeout_seconds = timeout
        saveConfig()
    }

    func reload() {
        // Load pending request
        if FileManager.default.fileExists(atPath: pendingFile.path),
           let data = try? Data(contentsOf: pendingFile),
           let req = try? JSONDecoder().decode(PendingRequest.self, from: data) {
            if self.pendingRequest != req {
                self.pendingRequest = req
            }
        } else {
            if self.pendingRequest != nil {
                self.pendingRequest = nil
            }
        }

        // Load history
        if FileManager.default.fileExists(atPath: historyFile.path),
           let data = try? Data(contentsOf: historyFile),
           let hist = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = hist.reversed()
        }
    }

    func approve(request: PendingRequest) {
        let decisionData = ["id": request.id, "decision": "allow"]
        if let data = try? JSONSerialization.data(withJSONObject: decisionData, options: .prettyPrinted) {
            try? data.write(to: decisionFile)
        }
        self.pendingRequest = nil
    }

    func deny(request: PendingRequest) {
        let decisionData = ["id": request.id, "decision": "deny"]
        if let data = try? JSONSerialization.data(withJSONObject: decisionData, options: .prettyPrinted) {
            try? data.write(to: decisionFile)
        }
        self.pendingRequest = nil
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: historyFile)
        self.history = []
    }
}

// MARK: - SwiftUI Menu Bar Dropdown View
struct MenuBarView: View {
    @ObservedObject var state: AppStateManager
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.pendingRequest != nil ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: (state.pendingRequest != nil ? Color.orange : Color.green).opacity(0.6), radius: 3)

                    Text("Antigravity CLI")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                if state.pendingRequest != nil {
                    Text("1 Pending")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.25))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                } else {
                    Text("Idle")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 2)

            Divider().background(Color.white.opacity(0.15))

            // Pending Approvals Section
            if let req = state.pendingRequest {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("⚠️ PENDING APPROVAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)

                        Spacer()

                        Text(req.tool)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.3))
                            .foregroundColor(Color(red: 0.85, green: 0.75, blue: 1.0))
                            .cornerRadius(4)
                    }

                    // Description
                    if !req.description.isEmpty {
                        Text(req.description)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }

                    // Code / Command snippet
                    HStack(spacing: 5) {
                        Text(req.tool == "run_command" ? "$" : "📄")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text(req.action)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(red: 0.85, green: 0.9, blue: 0.95))
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(6)
                    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 0.5))

                    // Buttons
                    HStack(spacing: 8) {
                        Button(action: { state.deny(request: req) }) {
                            Text("✗ Deny")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color(red: 0.2, green: 0.15, blue: 0.18))
                                .foregroundColor(.red)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { state.approve(request: req) }) {
                            Text("✓ Approve")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color(red: 0.08, green: 0.55, blue: 0.28))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No pending approvals")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            Divider().background(Color.white.opacity(0.15))

            // Preferences & Toggles Section
            VStack(alignment: .leading, spacing: 8) {
                Text("⚙️ PREFERENCES & TOGGLES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                // 1. Notch HUD Popup Toggle
                HStack {
                    Text("🔔 Notch HUD Popup")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { state.toggleNotchPopup() }) {
                        Text(state.config.notifications.enable_notch_popup ? "ON" : "OFF")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(state.config.notifications.enable_notch_popup ? Color.green.opacity(0.25) : Color.gray.opacity(0.2))
                            .foregroundColor(state.config.notifications.enable_notch_popup ? .green : .gray)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.config.notifications.enable_notch_popup ? Color.green.opacity(0.6) : Color.gray.opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // 2. Sound Alerts Toggle
                HStack {
                    Text("🔊 Audio Chimes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { state.toggleSound() }) {
                        Text(state.config.audio.sound_enabled ? "ON" : "OFF")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(state.config.audio.sound_enabled ? Color.blue.opacity(0.25) : Color.gray.opacity(0.2))
                            .foregroundColor(state.config.audio.sound_enabled ? Color.blue : .gray)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.config.audio.sound_enabled ? Color.blue.opacity(0.6) : Color.gray.opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // 3. Font Scale
                HStack {
                    Text("🔤 Font Scaling")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([0.9, 1.0, 1.2], id: \.self) { scale in
                            Button(action: { state.setFontSizeScale(scale) }) {
                                Text(scale == 0.9 ? "S" : (scale == 1.0 ? "M" : "L"))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(state.config.appearance.font_size_scale == scale ? Color.purple.opacity(0.4) : Color.gray.opacity(0.15))
                                    .foregroundColor(state.config.appearance.font_size_scale == scale ? Color(red: 0.85, green: 0.75, blue: 1.0) : .gray)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // 4. Timeout
                HStack {
                    Text("⏱️ Timeout")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([5.0, 15.0, 30.0], id: \.self) { timeout in
                            Button(action: { state.setTimeout(timeout) }) {
                                Text("\(Int(timeout))s")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(state.config.notifications.approval_timeout_seconds == timeout ? Color.orange.opacity(0.3) : Color.gray.opacity(0.15))
                                    .foregroundColor(state.config.notifications.approval_timeout_seconds == timeout ? .orange : .gray)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.03))
            .cornerRadius(6)

            // Recent Activity Section
            if !state.history.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("RECENT ACTIVITY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Button(action: { state.clearHistory() }) {
                            Text("Clear")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    ForEach(state.history.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Text(item.decision == "allow" ? "✓" : "✗")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(item.decision == "allow" ? .green : .red)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.description.isEmpty ? item.action : item.description)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(item.tool) • \(item.relativeTime)")
                                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.15))

            // Footer
            HStack {
                Text("tools/notch-hud/config.json")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.gray.opacity(0.8))

                Spacer()

                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 330)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.98))
    }
}

// MARK: - Menu Bar App Delegate
class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var stateManager: AppStateManager!
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stateManager = AppStateManager()

        // Create Status Item in Menu Bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚡ AGY"
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create Popover with calibrated dimensions
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 370)
        popover.behavior = .transient
        popover.animates = true
        let contentView = MenuBarView(state: stateManager, onQuit: {
            NSApp.terminate(nil)
        })
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Periodic Status Item Title Update
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if stateManager.pendingRequest != nil {
            button.title = "⚡ (1)"
        } else {
            button.title = "⚡ AGY"
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            stateManager.loadConfig()
            stateManager.reload()
            // Dynamically adjust popover height based on pending approvals and history
            let targetHeight: CGFloat
            if stateManager.pendingRequest != nil {
                targetHeight = 465
            } else if stateManager.history.isEmpty {
                targetHeight = 315
            } else {
                targetHeight = 370
            }
            popover.contentSize = NSSize(width: 330, height: targetHeight)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MenuBarAppDelegate()
app.delegate = delegate
app.run()
