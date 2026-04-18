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
    public let input: ToolValue

    public init(
        toolName: String,
        input: ToolValue = .object([:])
    ) {
        self.toolName = toolName
        self.input = input
    }

    public init(
        toolName: String,
        arguments: [String: ToolValue]
    ) {
        self.init(toolName: toolName, input: .object(arguments))
    }

    public var arguments: [String: ToolValue]? {
        guard case let .object(arguments) = input else {
            return nil
        }

        return arguments
    }
}
