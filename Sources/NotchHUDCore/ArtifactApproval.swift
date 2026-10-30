import Foundation
import Cocoa

public struct ArtifactMetadata: Codable, Equatable {
    public var summary: String?
    public var requestFeedback: Bool?
    public var userFacing: Bool?
    public var updatedAt: String?
    public var approved: Bool?
    public var userApproved: Bool?
    public var status: String?

    public init(
        summary: String? = nil,
        requestFeedback: Bool? = nil,
        userFacing: Bool? = nil,
        updatedAt: String? = nil,
        approved: Bool? = nil,
        userApproved: Bool? = nil,
        status: String? = nil
    ) {
        self.summary = summary
        self.requestFeedback = requestFeedback
        self.userFacing = userFacing
        self.updatedAt = updatedAt
        self.approved = approved
        self.userApproved = userApproved
        self.status = status
    }
}

public enum ArtifactApproval {
    /// Updates the artifact metadata to reflect user approval, updates state files,
    /// sets clipboard to "proceed", notifies dispatcher.py, and optionally triggers a Notch HUD toast.
    @discardableResult
    public static func approveArtifact(
        path: String,
        baseDir: URL? = nil,
        showToast: Bool = true
    ) -> Bool {
        guard !path.isEmpty else { return false }

        // 1. Copy 'proceed' to general pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("proceed", forType: .string)

        // 2. Update .metadata.json file on disk
        let metaURL = URL(fileURLWithPath: path + ".metadata.json")
        var metaDict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: metaURL.path),
           let data = try? Data(contentsOf: metaURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metaDict = existing
        }
        metaDict["requestFeedback"] = false
        metaDict["approved"] = true
        metaDict["userApproved"] = true
        metaDict["status"] = "approved"
        let isoFormatter = ISO8601DateFormatter()
        metaDict["updatedAt"] = isoFormatter.string(from: Date())
        if metaDict["summary"] == nil {
            metaDict["summary"] = URL(fileURLWithPath: path).lastPathComponent
        }
        if metaDict["userFacing"] == nil {
            metaDict["userFacing"] = true
        }

        if let enc = try? JSONSerialization.data(withJSONObject: metaDict, options: [.prettyPrinted, .sortedKeys]) {
            try? enc.write(to: metaURL, options: .atomic)
        }

        // 3. Resolve base / state directory
        let resolvedBaseDir: URL
        if let baseDir = baseDir {
            resolvedBaseDir = baseDir
        } else {
            let procPath = ProcessInfo.processInfo.arguments.first ?? ""
            if !procPath.isEmpty {
                resolvedBaseDir = URL(fileURLWithPath: procPath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            } else {
                resolvedBaseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            }
        }
        let stateDir = resolvedBaseDir.appendingPathComponent("state")
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        // 4. Update state/artifacts.json
        let artifactsURL = stateDir.appendingPathComponent("artifacts.json")
        if FileManager.default.fileExists(atPath: artifactsURL.path),
           let data = try? Data(contentsOf: artifactsURL),
           var items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for i in 0..<items.count {
                if let p = items[i]["path"] as? String, p == path {
                    items[i]["status"] = "reviewed"
                    items[i]["requestFeedback"] = false
                    items[i]["approved"] = true
                    items[i]["updatedAt"] = Date().timeIntervalSince1970
                }
            }
            if let enc = try? JSONSerialization.data(withJSONObject: items, options: .prettyPrinted) {
                try? enc.write(to: artifactsURL, options: .atomic)
            }
        }

        // 5. Update state/decision.json to unblock dispatcher
        let decisionURL = stateDir.appendingPathComponent("decision.json")
        let decPayload: [String: Any] = [
            "decision": "allow",
            "action": "proceed",
            "status": "approved",
            "path": path,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let decData = try? JSONSerialization.data(withJSONObject: decPayload, options: .prettyPrinted) {
            try? decData.write(to: decisionURL, options: .atomic)
        }

        // 6. Update state/session.json
        let sessionURL = stateDir.appendingPathComponent("session.json")
        let sessionPayload: [String: Any] = [
            "status": "active",
            "pendingReview": false,
            "lastApprovedArtifact": path,
            "unblocked": true,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let sessData = try? JSONSerialization.data(withJSONObject: sessionPayload, options: .prettyPrinted) {
            try? sessData.write(to: sessionURL, options: .atomic)
        }

        // 7. Notify dispatcher.py
        let dispatcherURL = resolvedBaseDir.appendingPathComponent("dispatcher.py")
        if FileManager.default.fileExists(atPath: dispatcherURL.path) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = [dispatcherURL.path, "--approve-artifact", path]
            try? proc.run()
        }

        // 8. Visual feedback in Notch HUD
        if showToast {
            let promptURL = resolvedBaseDir.appendingPathComponent("bin/notch-prompt")
            if FileManager.default.fileExists(atPath: promptURL.path) {
                let proc = Process()
                proc.executableURL = promptURL
                proc.arguments = [
                    "--mode", "toast",
                    "--title", "Artifact Approved",
                    "--message", "✓ Plan approved • Session unblocked",
                    "--sound", "Hero"
                ]
                try? proc.run()
            }
        }

        return true
    }
}
