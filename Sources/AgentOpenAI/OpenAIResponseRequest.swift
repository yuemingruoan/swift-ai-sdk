import AgentCore
import Foundation

public struct OpenAIResponseRequest: Codable, Equatable, Sendable {
    public var model: String
    public var input: [OpenAIResponseInputItem]
    public var instructions: String?
    public var previousResponseID: String?
    public var store: Bool?
    public var promptCacheKey: String?
    public var stream: Bool?
    public var tools: [OpenAIResponseTool]?
    public var toolChoice: OpenAIResponseToolChoice?

    public init(
        model: String,
        input: [OpenAIResponseInputItem],
        instructions: String? = nil,
        previousResponseID: String? = nil,
        store: Bool? = nil,
        promptCacheKey: String? = nil,
        stream: Bool? = nil,
        tools: [OpenAIResponseTool]? = nil,
        toolChoice: OpenAIResponseToolChoice? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.previousResponseID = previousResponseID
        self.store = store
        self.promptCacheKey = promptCacheKey
        self.stream = stream
        self.tools = tools
        self.toolChoice = toolChoice
    }

    public init(
        model: String,
        messages: [AgentMessage],
        previousResponseID: String? = nil,
        stream: Bool? = nil,
        tools: [ToolDescriptor] = [],
        toolChoice: OpenAIResponseToolChoice? = nil
    ) throws {
        self.init(
            model: model,
            input: try messages.map { .message(try .init(agentMessage: $0)) },
            instructions: nil,
            previousResponseID: previousResponseID,
            store: nil,
            promptCacheKey: nil,
            stream: stream,
            tools: tools.map(OpenAIResponseTool.init(descriptor:)),
            toolChoice: toolChoice
        )
    }

    public init(
        model: String,
        previousResponseID: String? = nil,
        stream: Bool? = nil,
        tools: [ToolDescriptor] = [],
        toolChoice: OpenAIResponseToolChoice? = nil,
        configureInput: (inout OpenAIResponseInputBuilder) -> Void
    ) {
        var builder = OpenAIResponseInputBuilder()
        configureInput(&builder)
        self.init(
            model: model,
            input: builder.build(),
            instructions: nil,
            previousResponseID: previousResponseID,
            store: nil,
            promptCacheKey: nil,
            stream: stream,
            tools: tools.map(OpenAIResponseTool.init(descriptor:)),
            toolChoice: toolChoice
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case previousResponseID = "previous_response_id"
        case store
        case promptCacheKey = "prompt_cache_key"
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

public enum OpenAIResponseToolChoice: String, Codable, Equatable, Sendable {
    case none
    case auto
    case required
}

public struct OpenAIResponseTool: Codable, Equatable, Sendable {
    public var type: String
    public var name: String
    public var description: String?
    public var parameters: OpenAIResponseToolSchema

    public init(
        name: String,
        description: String? = nil,
        parameters: OpenAIResponseToolSchema
    ) {
        self.type = "function"
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public init(descriptor: ToolDescriptor) {
        self.init(
            name: descriptor.name,
            parameters: OpenAIResponseToolSchema(
                toolInputSchema: descriptor.inputSchema ?? .object()
            )
        )
    }
}

public indirect enum OpenAIResponseToolSchema: Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case array(items: OpenAIResponseToolSchema)
    case object(
        properties: [String: OpenAIResponseToolSchema] = [:],
        required: [String] = [],
        additionalProperties: Bool = false
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
            self = .array(items: OpenAIResponseToolSchema(toolInputSchema: items))
        case .object(let properties, let required):
            self = .object(
                properties: properties.mapValues(OpenAIResponseToolSchema.init(toolInputSchema:)),
                required: required
            )
        }
    }
}

extension OpenAIResponseToolSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case items
        case properties
        case required
        case additionalProperties
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
            self = .array(items: try container.decode(OpenAIResponseToolSchema.self, forKey: .items))
        case .object:
            self = .object(
                properties: try container.decodeIfPresent([String: OpenAIResponseToolSchema].self, forKey: .properties) ?? [:],
                required: try container.decodeIfPresent([String].self, forKey: .required) ?? [],
                additionalProperties: try container.decodeIfPresent(Bool.self, forKey: .additionalProperties) ?? false
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
        case .object(let properties, let required, let additionalProperties):
            try container.encode(Kind.object, forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(additionalProperties, forKey: .additionalProperties)
        }
    }
}

public struct OpenAIResponseInputBuilder: Equatable, Sendable {
    private var items: [OpenAIResponseInputItem] = []

    public init() {}

    public mutating func append(_ item: OpenAIResponseInputItem) {
        items.append(item)
    }

    public mutating func appendSystemText(_ text: String) {
        append(.message(.systemText(text)))
    }

    public mutating func appendDeveloperText(_ text: String) {
        append(.message(.developerText(text)))
    }

    public mutating func appendUserText(_ text: String) {
        append(.message(.userText(text)))
    }

    public mutating func appendAssistantText(_ text: String) {
        append(.message(.assistantText(text)))
    }

    public mutating func appendUserImage(_ url: URL) {
        guard case .message(let message)? = items.last, message.role == .user else {
            append(.message(.init(role: .user, content: [.inputImage(url)])))
            return
        }

        items.removeLast()
        items.append(.message(.init(role: .user, content: message.content + [.inputImage(url)])))
    }

    public mutating func appendFunctionCallOutput(
        callID: String,
        output: OpenAIFunctionCallOutputValue
    ) {
        append(.functionCallOutput(.init(callID: callID, output: output)))
    }

    public func build() -> [OpenAIResponseInputItem] {
        items
    }
}

public enum OpenAIResponseInputItem: Equatable, Sendable {
    case message(OpenAIInputMessage)
    case functionCall(OpenAIResponseFunctionCall)
    case functionCallOutput(OpenAIFunctionCallOutput)
}

extension OpenAIResponseInputItem: Codable {
    enum CodingKeys: String, CodingKey {
        case type
    }

    enum Kind: String, Codable {
        case message
        case functionCall = "function_call"
        case functionCallOutput = "function_call_output"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .message:
            self = .message(try OpenAIInputMessage(from: decoder))
        case .functionCall:
            self = .functionCall(try OpenAIResponseFunctionCall(from: decoder))
        case .functionCallOutput:
            self = .functionCallOutput(try OpenAIFunctionCallOutput(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
        case .functionCall(let functionCall):
            try functionCall.encode(to: encoder)
        case .functionCallOutput(let output):
            try output.encode(to: encoder)
        }
    }
}

public enum OpenAIInputMessageRole: String, Codable, Equatable, Sendable {
    case system
    case developer
    case user
    case assistant
}

public struct OpenAIInputMessage: Codable, Equatable, Sendable {
    public var role: OpenAIInputMessageRole
    public var content: [OpenAIInputMessageContent]

    public init(role: OpenAIInputMessageRole, content: [OpenAIInputMessageContent]) {
        self.role = role
        self.content = content
    }

    public static func systemText(_ text: String) -> Self {
        .init(role: .system, content: [.inputText(text)])
    }

    public static func developerText(_ text: String) -> Self {
        .init(role: .developer, content: [.inputText(text)])
    }

    public static func userText(_ text: String) -> Self {
        .init(role: .user, content: [.inputText(text)])
    }

    public static func assistantText(_ text: String) -> Self {
        .init(role: .assistant, content: [.inputText(text)])
    }

    init(agentMessage: AgentMessage) throws {
        guard let role = OpenAIInputMessageRole(agentRole: agentMessage.role) else {
            throw OpenAIConversionError.unsupportedMessageRole(String(describing: agentMessage.role.rawValue))
        }

        self.init(
            role: role,
            content: agentMessage.parts.map(OpenAIInputMessageContent.init(messagePart:))
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decode(OpenAIInputMessageRole.self, forKey: .role)
        self.content = try container.decode([OpenAIInputMessageContent].self, forKey: .content)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(OpenAIResponseInputItem.Kind.message, forKey: .type)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

public enum OpenAIInputMessageContent: Equatable, Sendable {
    case inputText(String)
    case inputImage(URL)
    case outputText(String)
    case refusal(String)
}

extension OpenAIInputMessageContent: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case refusal
    }

    enum Kind: String, Codable {
        case inputText = "input_text"
        case inputImage = "input_image"
        case outputText = "output_text"
        case refusal
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .inputText:
            self = .inputText(try container.decode(String.self, forKey: .text))
        case .inputImage:
            self = .inputImage(try container.decode(URL.self, forKey: .imageURL))
        case .outputText:
            self = .outputText(try container.decode(String.self, forKey: .text))
        case .refusal:
            self = .refusal(try container.decode(String.self, forKey: .refusal))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inputText(let text):
            try container.encode(Kind.inputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let url):
            try container.encode(Kind.inputImage, forKey: .type)
            try container.encode(url, forKey: .imageURL)
        case .outputText(let text):
            try container.encode(Kind.outputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case .refusal(let refusal):
            try container.encode(Kind.refusal, forKey: .type)
            try container.encode(refusal, forKey: .refusal)
        }
    }
}

public struct OpenAIFunctionCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var output: OpenAIFunctionCallOutputValue

    public init(callID: String, output: OpenAIFunctionCallOutputValue) {
        self.callID = callID
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case output
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.output = try container.decode(OpenAIFunctionCallOutputValue.self, forKey: .output)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(OpenAIResponseInputItem.Kind.functionCallOutput, forKey: .type)
        try container.encode(callID, forKey: .callID)
        try container.encode(output, forKey: .output)
    }
}

public enum OpenAIFunctionCallOutputValue: Equatable, Sendable {
    case text(String)
    case content([OpenAIInputMessageContent])
}

extension OpenAIFunctionCallOutputValue: Codable {
    public init(from decoder: any Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let text = try? singleValueContainer.decode(String.self) {
            self = .text(text)
            return
        }

        self = .content(try singleValueContainer.decode([OpenAIInputMessageContent].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try singleValueContainer.encode(text)
        case .content(let content):
            try singleValueContainer.encode(content)
        }
    }
}

private extension OpenAIInputMessageRole {
    init?(agentRole: AgentMessageRole) {
        switch agentRole {
        case .system:
            self = .system
        case .developer:
            self = .developer
        case .user:
            self = .user
        case .assistant:
            self = .assistant
        case .tool:
            return nil
        }
    }
}

private extension OpenAIInputMessageContent {
    init(messagePart: MessagePart) {
        switch messagePart {
        case .text(let text):
            self = .inputText(text)
        case .image(let url):
            self = .inputImage(url)
        }
    }
}
