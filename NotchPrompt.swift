import Cocoa
import SwiftUI

// MARK: - JSON File Configuration Schema
struct FileConfig: Codable {
    struct Notifications: Codable {
        var approval_timeout_seconds: Double?
        var toast_duration_seconds: Double?
        var enable_notch_popup: Bool?
    }
    struct Audio: Codable {
        var sound_enabled: Bool?
        var prompt_sound: String?
        var toast_sound: String?
    }
    struct Appearance: Codable {
        var font_size_scale: Double?
        var notch_prompt_width: Double?
        var notch_prompt_height: Double?
        var notch_toast_width: Double?
        var notch_toast_height: Double?
    }

    var notifications: Notifications?
    var audio: Audio?
    var appearance: Appearance?

    static func load() -> FileConfig? {
        let exeURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let possiblePaths = [
            exeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("config.json").path,
            exeURL.deletingLastPathComponent().appendingPathComponent("config.json").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("config.json").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tools/notch-hud/config.json").path
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let cfg = try? JSONDecoder().decode(FileConfig.self, from: data) {
                return cfg
            }
        }
        return nil
    }
}

// MARK: - CLI Arguments & Merged Configuration
struct Config {
    var mode: String = "prompt" // "prompt" or "toast"
    var tool: String = "run_command"
    var description: String = "Execute operation"
    var action: String = "git commit -m 'update'"
    var reason: String = "Guarded action requires authorization"
    var timeout: TimeInterval = 60.0
    var toastDuration: TimeInterval = 3.0
    var title: String = "Antigravity CLI"
    var message: String = "Task completed, waiting for input"
    var sound: String = "Glass"
    var soundEnabled: Bool = true
    var fontScale: CGFloat = 1.0
    var promptWidth: CGFloat = 480.0
    var promptHeight: CGFloat = 158.0
    var toastWidth: CGFloat = 380.0
    var toastHeight: CGFloat = 46.0

    static func parse() -> Config {
        var config = Config()
        let fileCfg = FileConfig.load()

        // Apply JSON file config defaults
        if let notif = fileCfg?.notifications {
            if let t = notif.approval_timeout_seconds { config.timeout = t }
            if let d = notif.toast_duration_seconds { config.toastDuration = d }
        }
        if let aud = fileCfg?.audio {
            if let se = aud.sound_enabled { config.soundEnabled = se }
            if let ps = aud.prompt_sound { config.sound = ps }
        }
        if let app = fileCfg?.appearance {
            if let fs = app.font_size_scale { config.fontScale = CGFloat(fs) }
            if let pw = app.notch_prompt_width { config.promptWidth = CGFloat(pw) }
            if let ph = app.notch_prompt_height { config.promptHeight = CGFloat(ph) }
            if let tw = app.notch_toast_width { config.toastWidth = CGFloat(tw) }
            if let th = app.notch_toast_height { config.toastHeight = CGFloat(th) }
        }

        // Apply CLI overrides if passed
        let args = ProcessInfo.processInfo.arguments
        var i = 1
        while i < args.count {
            let arg = args[i]
            if arg == "--mode" && i + 1 < args.count {
                config.mode = args[i + 1]
                if config.mode == "toast", let ts = fileCfg?.audio?.toast_sound {
                    config.sound = ts
                }
                i += 2
            } else if arg == "--tool" && i + 1 < args.count {
                config.tool = args[i + 1]
                i += 2
            } else if arg == "--description" && i + 1 < args.count {
                config.description = args[i + 1]
                i += 2
            } else if arg == "--action" && i + 1 < args.count {
                config.action = args[i + 1]
                i += 2
            } else if arg == "--timeout" && i + 1 < args.count {
                config.timeout = Double(args[i + 1]) ?? config.timeout
                i += 2
            } else if arg == "--title" && i + 1 < args.count {
                config.title = args[i + 1]
                i += 2
            } else if arg == "--message" && i + 1 < args.count {
                config.message = args[i + 1]
                i += 2
            } else if arg == "--sound" && i + 1 < args.count {
                config.sound = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return config
    }
}

// MARK: - Sound Helper
func playNotificationSound(_ name: String, enabled: Bool) {
    guard enabled && name != "none" else { return }
    if let sound = NSSound(named: NSSound.Name(name)) {
        sound.play()
    }
}

// MARK: - SwiftUI Notch Prompt View
struct NotchPromptView: View {
    let config: Config
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onDismiss: () -> Void

    @State private var timeRemaining: Int
    @State private var timer: Timer? = nil
    @State private var isHoveringApprove = false
    @State private var isHoveringDeny = false

    init(config: Config, onApprove: @escaping () -> Void, onDeny: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.config = config
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onDismiss = onDismiss
        _timeRemaining = State(initialValue: Int(config.timeout))
    }

    var body: some View {
        VStack(spacing: 8) {
            // Top Header Row
            HStack(alignment: .center, spacing: 8) {
                // Glowing Pulse Indicator
                Circle()
                    .fill(Color(red: 0.98, green: 0.7, blue: 0.15))
                    .frame(width: 8 * config.fontScale, height: 8 * config.fontScale)
                    .shadow(color: Color.orange.opacity(0.8), radius: 5)

                Text("Antigravity Approval")
                    .font(.system(size: 12 * config.fontScale, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Tool Badge
                Text(config.tool)
                    .font(.system(size: 10 * config.fontScale, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.35))
                    .foregroundColor(Color(red: 0.85, green: 0.75, blue: 1.0))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.purple.opacity(0.6), lineWidth: 0.5)
                    )

                Spacer()

                // Countdown Timer
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9 * config.fontScale))
                    Text("\(timeRemaining)s")
                        .font(.system(size: 10 * config.fontScale, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Color.gray.opacity(0.9))
            }

            // Description / Intent Row (Human-Readable)
            if !config.description.isEmpty && config.description != config.action {
                HStack(alignment: .top, spacing: 6) {
                    Text("💬")
                        .font(.system(size: 11 * config.fontScale))
                    Text(config.description)
                        .font(.system(size: 11 * config.fontScale, weight: .semibold))
                        .foregroundColor(Color(red: 0.95, green: 0.95, blue: 1.0))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, 2)
            }

            // Action / Command / File Box
            HStack(spacing: 6) {
                Text(config.tool == "run_command" ? "$" : (config.tool.contains("file") ? "📄" : "⚡"))
                    .font(.system(size: 11 * config.fontScale, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.cyan.opacity(0.8))
                
                Text(config.action)
                    .font(.system(size: 11 * config.fontScale, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.85, green: 0.88, blue: 0.95))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(red: 0.07, green: 0.08, blue: 0.11))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )

            // Buttons Row
            HStack(spacing: 12) {
                // Deny Button
                Button(action: onDeny) {
                    HStack(spacing: 5) {
                        Text("✗")
                            .font(.system(size: 11 * config.fontScale, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 11 * config.fontScale, weight: .semibold))
                        Text("Esc")
                            .font(.system(size: 9 * config.fontScale, weight: .regular, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isHoveringDeny ? Color.red.opacity(0.3) : Color(red: 0.16, green: 0.18, blue: 0.22))
                    .foregroundColor(isHoveringDeny ? .red : .white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHoveringDeny ? Color.red.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveringDeny = $0 }

                // Approve Button
                Button(action: onApprove) {
                    HStack(spacing: 5) {
                        Text("✓")
                            .font(.system(size: 11 * config.fontScale, weight: .bold))
                        Text("Approve")
                            .font(.system(size: 11 * config.fontScale, weight: .bold))
                        Text("↵")
                            .font(.system(size: 10 * config.fontScale, weight: .bold))
                            .foregroundColor(Color.green.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isHoveringApprove ? Color(red: 0.1, green: 0.65, blue: 0.35) : Color(red: 0.08, green: 0.52, blue: 0.28))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .shadow(color: Color.green.opacity(0.4), radius: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green.opacity(0.8), lineWidth: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveringApprove = $0 }
            }
        }
        .padding(12)
        .frame(width: config.promptWidth)
        .background(
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.06).opacity(0.96)
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.7),
                                Color.purple.opacity(0.5),
                                Color.white.opacity(0.12)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.8), radius: 18, x: 0, y: 8)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if timeRemaining > 1 {
                    timeRemaining -= 1
                } else {
                    timer?.invalidate()
                    onDismiss()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - SwiftUI Notch Toast View
struct NotchToastView: View {
    let config: Config
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.1, green: 0.7, blue: 0.4))
                    .frame(width: 18 * config.fontScale, height: 18 * config.fontScale)
                Image(systemName: "sparkles")
                    .font(.system(size: 10 * config.fontScale, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(.system(size: 11 * config.fontScale, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(config.message)
                    .font(.system(size: 10 * config.fontScale, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: config.toastWidth, height: config.toastHeight)
        .background(
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.06).opacity(0.96)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.green.opacity(0.7),
                                Color.cyan.opacity(0.4),
                                Color.white.opacity(0.12)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.6), radius: 12, x: 0, y: 6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.toastDuration) {
                onDismiss()
            }
        }
    }
}

// MARK: - App Delegate & Window Manager
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel!
    var config: Config!
    var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Config.parse()
        playNotificationSound(config.sound, enabled: config.soundEnabled)

        guard let screen = NSScreen.main else {
            print("{\"decision\":\"ask\",\"reason\":\"No main screen found\"}")
            exit(0)
        }

        let screenFrame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let hasNotch = safeTop > 20

        let width: CGFloat = config.mode == "toast" ? config.toastWidth : config.promptWidth
        let height: CGFloat = config.mode == "toast" ? config.toastHeight : config.promptHeight

        // Calculate position at the top notch of the screen with clear margin
        let xPos = screenFrame.origin.x + (screenFrame.width - width) / 2
        let yPos = hasNotch ? (screenFrame.origin.y + screenFrame.height - safeTop - height - 8) : (screenFrame.origin.y + screenFrame.height - height - 12)

        let frame = NSRect(x: xPos, y: yPos, width: width, height: height)

        window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false

        if config.mode == "toast" {
            let toastView = NotchToastView(config: config) { [weak self] in
                self?.finish(exitCode: 0, decision: "toast_done")
            }
            window.contentView = NSHostingView(rootView: toastView)
        } else {
            let promptView = NotchPromptView(
                config: config,
                onApprove: { [weak self] in
                    self?.finish(exitCode: 0, decision: "allow")
                },
                onDeny: { [weak self] in
                    self?.finish(exitCode: 1, decision: "deny")
                },
                onDismiss: { [weak self] in
                    self?.finish(exitCode: 2, decision: "dismiss")
                }
            )
            window.contentView = NSHostingView(rootView: promptView)

            // Setup keyboard monitoring for Return / Space (Approve) and Esc (Deny)
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 { // Return, Enter, Space
                    self?.finish(exitCode: 0, decision: "allow")
                    return nil
                } else if event.keyCode == 53 { // Escape
                    self?.finish(exitCode: 1, decision: "deny")
                    return nil
                }
                return event
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish(exitCode: Int32, decision: String) {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        window?.orderOut(nil)

        if config.mode == "toast" {
            exit(0)
        }

        if decision == "allow" {
            print("{\"decision\":\"allow\"}")
            exit(0)
        } else if decision == "dismiss" {
            print("{\"decision\":\"dismiss\"}")
            exit(2)
        } else {
            print("{\"decision\":\"deny\",\"reason\":\"Action denied by user on Mac Notch HUD\"}")
            exit(1)
        }
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
