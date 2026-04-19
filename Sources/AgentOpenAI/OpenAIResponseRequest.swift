import AgentCore
import Foundation

public struct OpenAIResponseRequest: Codable, Equatable, Sendable {
    public var model: String
    public var input: [OpenAIResponseInputItem]
    public var previousResponseID: String?

    public init(
        model: String,
        input: [OpenAIResponseInputItem],
        previousResponseID: String? = nil
    ) {
        self.model = model
        self.input = input
        self.previousResponseID = previousResponseID
    }

    public init(
        model: String,
        messages: [AgentMessage],
        previousResponseID: String? = nil
    ) throws {
        self.init(
            model: model,
            input: try messages.map { .message(try .init(agentMessage: $0)) },
            previousResponseID: previousResponseID
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case previousResponseID = "previous_response_id"
    }
}

public enum OpenAIResponseInputItem: Equatable, Sendable {
    case message(OpenAIInputMessage)
    case functionCallOutput(OpenAIFunctionCallOutput)
}

extension OpenAIResponseInputItem: Codable {
    enum CodingKeys: String, CodingKey {
        case type
    }

    enum Kind: String, Codable {
        case message
        case functionCallOutput = "function_call_output"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .message:
            self = .message(try OpenAIInputMessage(from: decoder))
        case .functionCallOutput:
            self = .functionCallOutput(try OpenAIFunctionCallOutput(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
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
}

extension OpenAIInputMessageContent: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    enum Kind: String, Codable {
        case inputText = "input_text"
        case inputImage = "input_image"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .inputText:
            self = .inputText(try container.decode(String.self, forKey: .text))
        case .inputImage:
            self = .inputImage(try container.decode(URL.self, forKey: .imageURL))
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
