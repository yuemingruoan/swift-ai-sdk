import Foundation

public enum OpenAIResponseStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case inProgress = "in_progress"
    case queued
    case cancelled
    case incomplete
}

public enum OpenAIResponseItemStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case completed
    case incomplete
}

public enum OpenAIResponseOutputItem: Equatable, Sendable {
    case message(OpenAIResponseMessage)
    case functionCall(OpenAIResponseFunctionCall)
}

extension OpenAIResponseOutputItem: Codable {
    enum CodingKeys: String, CodingKey {
        case type
    }

    enum Kind: String, Codable {
        case message
        case functionCall = "function_call"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .message:
            self = .message(try OpenAIResponseMessage(from: decoder))
        case .functionCall:
            self = .functionCall(try OpenAIResponseFunctionCall(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
        case .functionCall(let functionCall):
            try functionCall.encode(to: encoder)
        }
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

public struct OpenAIResponseMessage: Codable, Equatable, Sendable {
    public var id: String
    public var status: OpenAIResponseItemStatus?
    public var role: OpenAIInputMessageRole
    public var content: [OpenAIResponseMessageContent]

    public init(
        id: String,
        status: OpenAIResponseItemStatus? = nil,
        role: OpenAIInputMessageRole,
        content: [OpenAIResponseMessageContent]
    ) {
        self.id = id
        self.status = status
        self.role = role
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case status
        case role
        case content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.status = try container.decodeIfPresent(OpenAIResponseItemStatus.self, forKey: .status)
        self.role = try container.decode(OpenAIInputMessageRole.self, forKey: .role)
        self.content = try container.decode([OpenAIResponseMessageContent].self, forKey: .content)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(OpenAIResponseOutputItem.Kind.message, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

public enum OpenAIResponseMessageContent: Equatable, Sendable {
    case outputText(String)
    case refusal(String)
}

extension OpenAIResponseMessageContent: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case refusal
    }

    enum Kind: String, Codable {
        case outputText = "output_text"
        case refusal
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .outputText:
            self = .outputText(try container.decode(String.self, forKey: .text))
        case .refusal:
            self = .refusal(try container.decode(String.self, forKey: .refusal))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .outputText(let text):
            try container.encode(Kind.outputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case .refusal(let refusal):
            try container.encode(Kind.refusal, forKey: .type)
            try container.encode(refusal, forKey: .refusal)
        }
    }
}

public struct OpenAIResponseFunctionCall: Codable, Equatable, Sendable {
    public var id: String?
    public var callID: String
    public var name: String
    public var arguments: String
    public var status: OpenAIResponseItemStatus?

    public init(
        id: String? = nil,
        callID: String,
        name: String,
        arguments: String,
        status: OpenAIResponseItemStatus? = nil
    ) {
        self.id = id
        self.callID = callID
        self.name = name
        self.arguments = arguments
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callID = "call_id"
        case name
        case arguments
        case status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.name = try container.decode(String.self, forKey: .name)
        self.arguments = try container.decode(String.self, forKey: .arguments)
        self.status = try container.decodeIfPresent(OpenAIResponseItemStatus.self, forKey: .status)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(OpenAIResponseOutputItem.Kind.functionCall, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(callID, forKey: .callID)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
        try container.encodeIfPresent(status, forKey: .status)
    }
}
