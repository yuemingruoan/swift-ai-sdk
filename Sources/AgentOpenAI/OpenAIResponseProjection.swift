import AgentCore
import Foundation

public struct OpenAIResponseToolCall: Equatable, Sendable {
    public var callID: String
    public var invocation: ToolInvocation

    public init(callID: String, invocation: ToolInvocation) {
        self.callID = callID
        self.invocation = invocation
    }
}

public struct OpenAIResponseProjection: Equatable, Sendable {
    public var messages: [AgentMessage]
    public var toolCalls: [OpenAIResponseToolCall]

    public init(messages: [AgentMessage], toolCalls: [OpenAIResponseToolCall]) {
        self.messages = messages
        self.toolCalls = toolCalls
    }
}

public extension OpenAIResponse {
    func projectedOutput() throws -> OpenAIResponseProjection {
        var messages: [AgentMessage] = []
        var toolCalls: [OpenAIResponseToolCall] = []

        for item in output {
            switch item {
            case .message(let message):
                let parts = message.content.map { content in
                    switch content {
                    case .outputText(let text):
                        MessagePart.text(text)
                    case .refusal(let refusal):
                        MessagePart.text(refusal)
                    }
                }

                messages.append(AgentMessage(role: .assistant, parts: parts))

            case .functionCall(let functionCall):
                toolCalls.append(
                    OpenAIResponseToolCall(
                        callID: functionCall.callID,
                        invocation: ToolInvocation(
                            toolName: functionCall.name,
                            input: try parseToolValue(from: functionCall.arguments, callID: functionCall.callID)
                        )
                    )
                )
            }
        }

        return OpenAIResponseProjection(messages: messages, toolCalls: toolCalls)
    }
}

private func parseToolValue(from json: String, callID: String) throws -> ToolValue {
    guard let data = json.data(using: .utf8) else {
        throw OpenAIConversionError.invalidFunctionCallArguments(callID)
    }

    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw OpenAIConversionError.invalidFunctionCallArguments(callID)
    }

    return try convertToolValue(object, callID: callID)
}

private func convertToolValue(_ value: Any, callID: String) throws -> ToolValue {
    switch value {
    case let string as String:
        return .string(string)
    case let bool as Bool:
        return .boolean(bool)
    case let int as Int:
        return .integer(int)
    case let number as NSNumber:
        return CFNumberIsFloatType(number) ? .number(number.doubleValue) : .integer(number.intValue)
    case let array as [Any]:
        return .array(try array.map { try convertToolValue($0, callID: callID) })
    case let dictionary as [String: Any]:
        return .object(
            try dictionary.mapValues { try convertToolValue($0, callID: callID) }
        )
    case _ as NSNull:
        return .null
    default:
        throw OpenAIConversionError.invalidFunctionCallArguments(callID)
    }
}
