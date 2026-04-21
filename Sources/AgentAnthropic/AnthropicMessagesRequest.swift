import AgentCore
import Foundation

public enum AnthropicConversionError: Error, Equatable, Sendable {
    case unsupportedMessageRole(String)
    case unsupportedMessagePart(String)
    case unsupportedResponseMessageRole(String)
    case unsupportedResponseContentBlock(String)
}

public struct AnthropicMessagesRequest: Codable, Equatable, Sendable {
    public var model: String
    public var maxTokens: Int
    public var system: String?
    public var messages: [AnthropicMessage]
    public var tools: [AnthropicTool]?

    public init(
        model: String,
        maxTokens: Int,
        system: String? = nil,
        messages: [AnthropicMessage],
        tools: [ToolDescriptor] = []
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools.isEmpty ? nil : tools.map(AnthropicTool.init(descriptor:))
    }

    public init(
        model: String,
        maxTokens: Int,
        messages: [AgentMessage],
        tools: [ToolDescriptor] = []
    ) throws {
        var systemSegments: [String] = []
        var anthropicMessages: [AnthropicMessage] = []

        for message in messages {
            switch message.role {
            case .system, .developer:
                systemSegments += try message.parts.map(systemText(from:))

            case .user, .assistant:
                guard let role = AnthropicMessageRole(agentRole: message.role) else {
                    throw AnthropicConversionError.unsupportedMessageRole(message.role.rawValue)
                }
                anthropicMessages.append(
                    AnthropicMessage(
                        role: role,
                        content: try message.parts.map(contentBlock(from:))
                    )
                )

            case .tool:
                throw AnthropicConversionError.unsupportedMessageRole(message.role.rawValue)
            }
        }

        self.init(
            model: model,
            maxTokens: maxTokens,
            system: systemSegments.isEmpty ? nil : systemSegments.joined(separator: "\n\n"),
            messages: anthropicMessages,
            tools: tools
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
    }
}

public enum AnthropicMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant

    init?(agentRole: AgentMessageRole) {
        switch agentRole {
        case .user:
            self = .user
        case .assistant:
            self = .assistant
        case .system, .developer, .tool:
            return nil
        }
    }
}

public struct AnthropicMessage: Codable, Equatable, Sendable {
    public var role: AnthropicMessageRole
    public var content: [AnthropicContentBlock]

    public init(role: AnthropicMessageRole, content: [AnthropicContentBlock]) {
        self.role = role
        self.content = content
    }

    public static func userText(_ text: String) -> Self {
        .init(role: .user, content: [.text(text)])
    }

    public static func assistantText(_ text: String) -> Self {
        .init(role: .assistant, content: [.text(text)])
    }
}

public enum AnthropicContentBlock: Equatable, Sendable {
    case text(String)
    case toolUse(AnthropicToolUse)
    case toolResult(AnthropicToolResult)
}

extension AnthropicContentBlock: Codable {
    enum CodingKeys: String, CodingKey {
        case type
    }

    enum Kind: String, Codable {
        case text
        case toolUse = "tool_use"
        case toolResult = "tool_result"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try AnthropicTextBlock(from: decoder).text)
        case .toolUse:
            self = .toolUse(try AnthropicToolUse(from: decoder))
        case .toolResult:
            self = .toolResult(try AnthropicToolResult(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let text):
            try AnthropicTextBlock(text: text).encode(to: encoder)
        case .toolUse(let toolUse):
            try toolUse.encode(to: encoder)
        case .toolResult(let toolResult):
            try toolResult.encode(to: encoder)
        }
    }
}

private struct AnthropicTextBlock: Codable, Equatable, Sendable {
    var type = "text"
    var text: String
}

public struct AnthropicToolUse: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var input: [String: ToolValue]

    public init(id: String, name: String, input: [String: ToolValue]) {
        self.id = id
        self.name = name
        self.input = input
    }

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case input
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        input = try container.decode([String: ToolValue].self, forKey: .input)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("tool_use", forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(input, forKey: .input)
    }
}

public struct AnthropicToolResult: Codable, Equatable, Sendable {
    public var toolUseID: String
    public var content: String
    public var isError: Bool?

    public init(toolUseID: String, content: String, isError: Bool? = nil) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
    }

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolUseID = try container.decode(String.self, forKey: .toolUseID)
        content = try container.decode(String.self, forKey: .content)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("tool_result", forKey: .type)
        try container.encode(toolUseID, forKey: .toolUseID)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(isError, forKey: .isError)
    }
}

public struct AnthropicTool: Codable, Equatable, Sendable {
    public var name: String
    public var description: String?
    public var inputSchema: AnthropicToolSchema

    public init(
        name: String,
        description: String? = nil,
        inputSchema: AnthropicToolSchema
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public init(descriptor: ToolDescriptor) {
        self.init(
            name: descriptor.name,
            description: descriptor.description,
            inputSchema: AnthropicToolSchema(
                toolInputSchema: descriptor.inputSchema ?? .object()
            )
        )
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

public indirect enum AnthropicToolSchema: Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case array(items: AnthropicToolSchema)
    case object(
        properties: [String: AnthropicToolSchema] = [:],
        required: [String] = []
    )

    public init(toolInputSchema: ToolInputSchema) {
        switch toolInputSchema {
        case .string:
            self = .string
        case .integer:
            self = .integer
        case .number:
            self = .number
        case .boolean:
            self = .boolean
        case .array(let items):
            self = .array(items: AnthropicToolSchema(toolInputSchema: items))
        case .object(let properties, let required):
            self = .object(
                properties: properties.mapValues(AnthropicToolSchema.init(toolInputSchema:)),
                required: required
            )
        }
    }
}

extension AnthropicToolSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case items
        case properties
        case required
    }

    enum Kind: String, Codable {
        case string
        case integer
        case number
        case boolean
        case array
        case object
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .string:
            self = .string
        case .integer:
            self = .integer
        case .number:
            self = .number
        case .boolean:
            self = .boolean
        case .array:
            self = .array(items: try container.decode(AnthropicToolSchema.self, forKey: .items))
        case .object:
            self = .object(
                properties: try container.decodeIfPresent([String: AnthropicToolSchema].self, forKey: .properties) ?? [:],
                required: try container.decodeIfPresent([String].self, forKey: .required) ?? []
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string:
            try container.encode(Kind.string, forKey: .type)
        case .integer:
            try container.encode(Kind.integer, forKey: .type)
        case .number:
            try container.encode(Kind.number, forKey: .type)
        case .boolean:
            try container.encode(Kind.boolean, forKey: .type)
        case .array(let items):
            try container.encode(Kind.array, forKey: .type)
            try container.encode(items, forKey: .items)
        case .object(let properties, let required):
            try container.encode(Kind.object, forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
        }
    }
}

private func systemText(from part: MessagePart) throws -> String {
    switch part {
    case .text(let text):
        return text
    case .image:
        throw AnthropicConversionError.unsupportedMessagePart("image")
    }
}

private func contentBlock(from part: MessagePart) throws -> AnthropicContentBlock {
    switch part {
    case .text(let text):
        return .text(text)
    case .image:
        throw AnthropicConversionError.unsupportedMessagePart("image")
    }
}
