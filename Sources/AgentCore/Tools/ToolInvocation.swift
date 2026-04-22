import Foundation

public indirect enum ToolValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([ToolValue])
    case object([String: ToolValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ToolValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: ToolValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                ToolValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported ToolValue payload")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let string):
            try container.encode(string)
        case .integer(let integer):
            try container.encode(integer)
        case .number(let number):
            try container.encode(number)
        case .boolean(let boolean):
            try container.encode(boolean)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        case .null:
            try container.encodeNil()
        }
    }
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
