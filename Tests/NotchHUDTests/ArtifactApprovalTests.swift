import Foundation
import Cocoa
@testable import NotchHUDCore

public enum NotchHUDCoreTests {
    public static func runAllTests() {
        testAutoApproveConfig()
        testArtifactMetadataCodable()
        print("✅ [NotchHUDTests] All Notch HUD Core unit tests passed successfully!")
    }

    private static func testAutoApproveConfig() {
        var cfg = AutoApproveConfig(enabled: true)
        assert(cfg.enabled == true)

        cfg.enabled = false
        assert(cfg.enabled == false)

        guard let data = try? JSONEncoder().encode(cfg),
              let decoded = try? JSONDecoder().decode(AutoApproveConfig.self, from: data) else {
            fatalError("Failed to encode/decode AutoApproveConfig")
        }
        assert(decoded.enabled == false)
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
}

// Automatically execute all tests when runner initializes
let testsExecuted: Void = NotchHUDCoreTests.runAllTests()
