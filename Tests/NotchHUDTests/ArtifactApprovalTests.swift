import Foundation
import Cocoa
@testable import NotchHUDCore

public enum ArtifactApprovalTests {
    public static func runAllTests() {
        testArtifactMetadataCodable()
        testApproveArtifactUpdatesExistingMetadataAndState()
        testApproveArtifactCreatesMissingMetadata()
        print("✅ [NotchHUDTests] All Artifact Approval unit tests passed successfully!")
    }

    private static func testArtifactMetadataCodable() {
        let meta = ArtifactMetadata(
            summary: "Test Plan",
            requestFeedback: true,
            userFacing: true,
            updatedAt: "2026-10-30T12:00:00Z",
            approved: false,
            userApproved: false,
            status: "pending_review"
        )
        guard let data = try? JSONEncoder().encode(meta),
              let decoded = try? JSONDecoder().decode(ArtifactMetadata.self, from: data) else {
            fatalError("Failed to encode/decode ArtifactMetadata")
        }
        assert(decoded.summary == "Test Plan")
        assert(decoded.requestFeedback == true)
        assert(decoded.userFacing == true)
        assert(decoded.approved == false)
        assert(decoded.status == "pending_review")
    }

    private static func testApproveArtifactUpdatesExistingMetadataAndState() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let artifactFile = tempDir.appendingPathComponent("plan.md")
        try? "# Test Plan Content".write(to: artifactFile, atomically: true, encoding: .utf8)

        let metaFile = tempDir.appendingPathComponent("plan.md.metadata.json")
        let initialMeta: [String: Any] = [
            "summary": "Initial plan summary",
            "requestFeedback": true,
            "userFacing": true,
            "updatedAt": "2026-10-30T10:00:00Z"
        ]
        if let initialData = try? JSONSerialization.data(withJSONObject: initialMeta, options: .prettyPrinted) {
            try? initialData.write(to: metaFile)
        }

        let stateDir = tempDir.appendingPathComponent("state")
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let artifactsFile = stateDir.appendingPathComponent("artifacts.json")
        let initialArtifacts: [[String: Any]] = [
            [
                "id": "plan.md",
                "name": "plan.md",
                "path": artifactFile.path,
                "summary": "Initial plan summary",
                "requestFeedback": true,
                "status": "pending_review",
                "updatedAt": 1000.0
            ]
        ]
        if let artData = try? JSONSerialization.data(withJSONObject: initialArtifacts, options: .prettyPrinted) {
            try? artData.write(to: artifactsFile)
        }

        let success = ArtifactApproval.approveArtifact(
            path: artifactFile.path,
            baseDir: tempDir,
            showToast: false
        )
        assert(success == true, "approveArtifact should succeed")

        // 1. Verify metadata file
        guard let updatedMetaData = try? Data(contentsOf: metaFile),
              let updatedMeta = try? JSONDecoder().decode(ArtifactMetadata.self, from: updatedMetaData) else {
            fatalError("Failed to read updated metadata file")
        }
        assert(updatedMeta.requestFeedback == false, "requestFeedback should be false")
        assert(updatedMeta.approved == true, "approved should be true")
        assert(updatedMeta.userApproved == true, "userApproved should be true")
        assert(updatedMeta.status == "approved", "status should be approved")
        assert(updatedMeta.summary == "Initial plan summary")
        assert(updatedMeta.updatedAt != nil)

        // 2. Verify state/artifacts.json
        guard let updatedArtData = try? Data(contentsOf: artifactsFile),
              let updatedArtList = try? JSONSerialization.jsonObject(with: updatedArtData) as? [[String: Any]],
              let artItem = updatedArtList.first else {
            fatalError("Failed to read updated artifacts.json")
        }
        assert(artItem["status"] as? String == "reviewed", "status should be reviewed")
        assert(artItem["requestFeedback"] as? Bool == false, "requestFeedback should be false")
        assert(artItem["approved"] as? Bool == true, "approved should be true")

        // 3. Verify state/decision.json
        let decisionFile = stateDir.appendingPathComponent("decision.json")
        assert(FileManager.default.fileExists(atPath: decisionFile.path))
        guard let decData = try? Data(contentsOf: decisionFile),
              let decDict = try? JSONSerialization.jsonObject(with: decData) as? [String: Any] else {
            fatalError("Failed to read decision.json")
        }
        assert(decDict["decision"] as? String == "allow")
        assert(decDict["action"] as? String == "proceed")
        assert(decDict["status"] as? String == "approved")

        // 4. Verify state/session.json
        let sessionFile = stateDir.appendingPathComponent("session.json")
        assert(FileManager.default.fileExists(atPath: sessionFile.path))
        guard let sessData = try? Data(contentsOf: sessionFile),
              let sessDict = try? JSONSerialization.jsonObject(with: sessData) as? [String: Any] else {
            fatalError("Failed to read session.json")
        }
        assert(sessDict["status"] as? String == "active")
        assert(sessDict["unblocked"] as? Bool == true)
        assert(sessDict["pendingReview"] as? Bool == false)
        assert(sessDict["lastApprovedArtifact"] as? String == artifactFile.path)

        // 5. Verify pasteboard
        assert(NSPasteboard.general.string(forType: .string) == "proceed")
    }

    private static func testApproveArtifactCreatesMissingMetadata() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let artifactFile = tempDir.appendingPathComponent("new_plan.md")
        try? "# New Plan".write(to: artifactFile, atomically: true, encoding: .utf8)

        let success = ArtifactApproval.approveArtifact(
            path: artifactFile.path,
            baseDir: tempDir,
            showToast: false
        )
        assert(success == true)

        let metaFile = tempDir.appendingPathComponent("new_plan.md.metadata.json")
        assert(FileManager.default.fileExists(atPath: metaFile.path))

        guard let metaData = try? Data(contentsOf: metaFile),
              let meta = try? JSONDecoder().decode(ArtifactMetadata.self, from: metaData) else {
            fatalError("Failed to read created metadata")
        }
        assert(meta.requestFeedback == false)
        assert(meta.approved == true)
        assert(meta.userApproved == true)
        assert(meta.status == "approved")
        assert(meta.summary == "new_plan.md")
    }
}

// Automatically execute all tests when runner initializes
let testsExecuted: Void = ArtifactApprovalTests.runAllTests()
