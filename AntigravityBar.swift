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
    struct AutoApprove: Codable, Equatable {
        var enabled: Bool = false
        var duration_minutes: Double = 15.0
        var expires_at: Double = 0.0
    }

    var notifications: Notifications = Notifications()
    var audio: Audio = Audio()
    var appearance: Appearance = Appearance()
    var auto_approve: AutoApprove = AutoApprove()
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
    var auto_approved: Bool? = nil

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

    var isAutoApproveActive: Bool {
        return config.auto_approve.enabled && (Date().timeIntervalSince1970 < config.auto_approve.expires_at)
    }

    var autoApproveRemainingSeconds: Double {
        return max(0, config.auto_approve.expires_at - Date().timeIntervalSince1970)
    }

    var formattedRemainingTime: String {
        let secs = Int(autoApproveRemainingSeconds)
        let mins = secs / 60
        let remSecs = secs % 60
        if mins > 0 {
            return "\(mins)m \(remSecs)s"
        } else {
            return "\(remSecs)s"
        }
    }

    func toggleAutoApprove() {
        if isAutoApproveActive {
            config.auto_approve.enabled = false
            config.auto_approve.expires_at = 0.0
            config.notifications.enable_notch_popup = true
        } else {
            config.auto_approve.enabled = true
            let durationSecs = (config.auto_approve.duration_minutes > 0 ? config.auto_approve.duration_minutes : 15.0) * 60.0
            config.auto_approve.expires_at = Date().timeIntervalSince1970 + durationSecs
            config.notifications.enable_notch_popup = false
        }
        saveConfig()
    }

    func setAutoApproveDuration(_ minutes: Double) {
        config.auto_approve.duration_minutes = minutes
        if isAutoApproveActive {
            config.auto_approve.expires_at = Date().timeIntervalSince1970 + (minutes * 60.0)
        }
        saveConfig()
    }

    func reload() {
        // Auto-expire auto approve if duration elapsed
        if config.auto_approve.enabled && Date().timeIntervalSince1970 >= config.auto_approve.expires_at {
            config.auto_approve.enabled = false
            config.notifications.enable_notch_popup = true
            saveConfig()
        }

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
            headerSection
            Divider().background(Color.white.opacity(0.15))

            if state.pendingRequest != nil {
                pendingSection
                Divider().background(Color.white.opacity(0.15))
            }

            autoApproveSection
            Divider().background(Color.white.opacity(0.15))

            preferencesSection

            if !state.history.isEmpty {
                Divider().background(Color.white.opacity(0.15))
                activitySection
            }

            Divider().background(Color.white.opacity(0.15))
            footerSection
        }
        .padding(14)
        .frame(width: 330)
        .background(
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.98)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.7), radius: 16, x: 0, y: 8)
    }

    // MARK: - Subviews
    private var headerSection: some View {
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
    }

    @ViewBuilder
    private var pendingSection: some View {
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

                if !req.description.isEmpty {
                    Text(req.description)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    Text(req.tool.contains("run_command") ? "$" : "📄")
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
        }
    }

    private var autoApproveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 11))
                        .foregroundColor(state.isAutoApproveActive ? .green : .gray)
                    Text("AUTO-APPROVE MODE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(state.isAutoApproveActive ? .green : .gray)
                }

                Spacer()

                Button(action: { state.toggleAutoApprove() }) {
                    Text(state.isAutoApproveActive ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(state.isAutoApproveActive ? Color.green.opacity(0.25) : Color.gray.opacity(0.2))
                        .foregroundColor(state.isAutoApproveActive ? .green : .gray)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.isAutoApproveActive ? Color.green.opacity(0.6) : Color.gray.opacity(0.4), lineWidth: 0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if state.isAutoApproveActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active: \(state.formattedRemainingTime) remaining")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 4) {
                        Text("🔕")
                            .font(.system(size: 9))
                        Text("Notch notifications automatically silenced")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(red: 0.75, green: 0.85, blue: 1.0))
                    }

                    HStack(spacing: 4) {
                        Text("🛡️")
                            .font(.system(size: 9))
                        Text("Artifacts & plans still require review")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.orange.opacity(0.9))
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(5)
            } else {
                HStack(spacing: 4) {
                    Text("Auto-approve commands & edits • 🔔 Notifs ON")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.gray)
                }
            }

            HStack {
                Text("⏱ Active Duration")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 4) {
                    ForEach([5.0, 15.0, 30.0, 60.0], id: \.self) { duration in
                        Button(action: { state.setAutoApproveDuration(duration) }) {
                            Text("\(Int(duration))m")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(state.config.auto_approve.duration_minutes == duration ? Color.cyan.opacity(0.35) : Color.gray.opacity(0.15))
                                .foregroundColor(state.config.auto_approve.duration_minutes == duration ? .cyan : .gray)
                                .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(8)
        .background(state.isAutoApproveActive ? Color.green.opacity(0.05) : Color.white.opacity(0.03))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(state.isAutoApproveActive ? Color.green.opacity(0.25) : Color.clear, lineWidth: 1))
    }

    private var preferencesSection: some View {
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
    }

    private var activitySection: some View {
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
                    Text(item.decision == "allow" ? (item.auto_approved == true ? "⚡" : "✓") : "✗")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(item.decision == "allow" ? (item.auto_approved == true ? .cyan : .green) : .red)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.description.isEmpty ? item.action : item.description)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if item.auto_approved == true {
                                Text("Auto-Approved •")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                            Text("\(item.tool) • \(item.relativeTime)")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var footerSection: some View {
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
}

// MARK: - Menu Bar App Delegate
class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var stateManager: AppStateManager!
    private var updateTimer: Timer?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stateManager = AppStateManager()

        // Create Status Item in Menu Bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚡ AGY"
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create Custom Screen-Anchored Floating Panel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 505),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let contentView = MenuBarView(state: stateManager, onQuit: {
            NSApp.terminate(nil)
        })
        panel.contentView = NSHostingView(rootView: contentView)

        // Periodic Status Item Title Update
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if stateManager.pendingRequest != nil {
            button.title = "⚡ (1)"
        } else if stateManager.isAutoApproveActive {
            let mins = max(1, Int(ceil(stateManager.autoApproveRemainingSeconds / 60.0)))
            button.title = "⚡🟢 (\(mins)m)"
        } else {
            button.title = "⚡ AGY"
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        
        if panel.isVisible {
            closePanel()
        } else {
            stateManager.loadConfig()
            stateManager.reload()

            let width: CGFloat = 330
            let targetHeight: CGFloat = (stateManager.pendingRequest != nil) ? 585 : (stateManager.history.isEmpty ? 435 : 505)

            // Calculate exact screen position directly below the status bar icon
            let buttonScreenRect = buttonWindow.convertToScreen(button.bounds)
            guard let screen = buttonWindow.screen ?? NSScreen.main else { return }

            var xPos = buttonScreenRect.midX - (width / 2)
            // Clamp X so it doesn't overflow screen right or left edges
            if xPos + width > screen.visibleFrame.maxX - 8 {
                xPos = screen.visibleFrame.maxX - width - 8
            }
            if xPos < screen.visibleFrame.minX + 8 {
                xPos = screen.visibleFrame.minX + 8
            }

            // Position EXACTLY 6px below the status bar button
            let yPos = buttonScreenRect.minY - targetHeight - 6

            panel.setFrame(NSRect(x: xPos, y: yPos, width: width, height: targetHeight), display: true)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Auto-close on click outside
            if globalClickMonitor != nil {
                NSEvent.removeMonitor(globalClickMonitor!)
            }
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePanel()
            }
        }
    }

    func closePanel() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        panel.orderOut(nil)
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MenuBarAppDelegate()
app.delegate = delegate
app.run()
