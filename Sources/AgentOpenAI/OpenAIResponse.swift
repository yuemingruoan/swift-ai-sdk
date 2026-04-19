import Foundation

public enum OpenAIResponseStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case inProgress = "in_progress"
    case queued
    case cancelled
    case incomplete
}

public struct OpenAIResponseOutputItem: Codable, Equatable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public struct OpenAIResponse: Codable, Equatable, Sendable {
    public var id: String
    public var status: OpenAIResponseStatus
    public var output: [OpenAIResponseOutputItem]

    public init(
        id: String,
        status: OpenAIResponseStatus,
        output: [OpenAIResponseOutputItem]
    ) {
        self.id = id
        self.status = status
        self.output = output
    }
}
