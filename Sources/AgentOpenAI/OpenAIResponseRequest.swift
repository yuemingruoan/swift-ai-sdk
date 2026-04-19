import AgentCore
import Foundation

public struct OpenAIResponseRequest: Codable, Equatable, Sendable {
    public var model: String
    public var input: [OpenAIInputMessage]
    public var previousResponseID: String?

    public init(
        model: String,
        input: [OpenAIInputMessage],
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
            input: try messages.map(OpenAIInputMessage.init(agentMessage:)),
            previousResponseID: previousResponseID
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case previousResponseID = "previous_response_id"
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
