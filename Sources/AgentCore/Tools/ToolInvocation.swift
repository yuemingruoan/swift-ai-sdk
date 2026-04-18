import Foundation

public indirect enum ToolValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([ToolValue])
    case object([String: ToolValue])
    case null
}

public struct ToolInvocation: Codable, Equatable, Sendable {
    public let toolName: String
    public let arguments: [String: ToolValue]

    public init(
        toolName: String,
        arguments: [String: ToolValue] = [:]
    ) {
        self.toolName = toolName
        self.arguments = arguments
    }
}
