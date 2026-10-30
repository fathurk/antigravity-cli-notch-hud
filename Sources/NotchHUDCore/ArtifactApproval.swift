import Foundation

public struct AutoApproveConfig: Codable, Equatable {
    public var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

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
