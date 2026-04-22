import AgentCore
import Foundation
import OpenAIResponsesAPI

public extension OpenAIResponseStreamEvent {
    /// Projects a raw Responses streaming event into provider-neutral runtime events.
    func projectedAgentStreamEvents() throws -> [AgentStreamEvent] {
        switch self {
        case .responseCreated:
            return []
        case .outputTextDelta(let delta):
            return [.textDelta(delta.delta)]
        case .outputItemDone:
            return []
        case .responseFailed(let response), .responseIncomplete(let response):
            throw AgentStreamError.responseFailed(provider: .openAI, status: response.status.rawValue)
        case .error(let error):
            throw AgentStreamError.serverError(
                provider: .openAI,
                type: error.type,
                code: error.code,
                message: error.message
            )
        case .responseCompleted(let response):
            return try response.projectedOutput().agentStreamEvents()
        }
    }
}

public extension OpenAIRealtimeEvent {
    /// Projects a raw Realtime event into provider-neutral runtime events.
    func projectedAgentStreamEvents() throws -> [AgentStreamEvent] {
        switch type {
        case "response.output_text.delta":
            guard case let .string(delta)? = payload["delta"] else {
                return []
            }
            return [.textDelta(delta)]

        case "response.completed", "response.done":
            guard let responseValue = payload["response"] else {
                return []
            }
            let data = try JSONEncoder().encode(responseValue)
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return try response.projectedOutput().agentStreamEvents()

        default:
            return []
        }
    }
}

public extension OpenAIRealtimeWebSocketClient {
    /// Receives one raw Realtime event and projects it into provider-neutral runtime events.
    func receiveProjectedEvents() async throws -> [AgentStreamEvent] {
        try await receive().projectedAgentStreamEvents()
    }

    /// Receives realtime events until the current turn completes, optionally resolving tool calls.
    func receiveUntilTurnFinished(
        using executor: ToolExecutor? = nil,
        maxIterations: Int = 8
    ) async throws -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []
        var remainingIterations = maxIterations

        while true {
            guard remainingIterations > 0 else {
                throw AgentRuntimeError.toolCallLimitExceeded(provider: .openAI, maxIterations: maxIterations)
            }

            let realtimeEvent = try await receive()
            switch realtimeEvent.type {
            case "response.output_text.delta":
                let projected = try realtimeEvent.projectedAgentStreamEvents()
                events.append(contentsOf: projected)

            case "response.completed", "response.done":
                let projection = try runtimeDecodeCompletedResponse(from: realtimeEvent).projectedOutput()
                let projected = projection.agentStreamEvents()
                events.append(contentsOf: projected)

                if projection.toolCalls.isEmpty {
                    return events
                }

                guard let executor else {
                    return events
                }

                for toolCall in projection.toolCalls {
                    let result = try await executor.invoke(toolCall.invocation)
                    try await sendFunctionCallOutput(
                        callID: toolCall.callID,
                        output: try runtimeEncodeToolResult(result)
                    )
                }
                try await createResponse()
                remainingIterations -= 1

            default:
                continue
            }
        }
    }
}

private func runtimeDecodeCompletedResponse(from event: OpenAIRealtimeEvent) throws -> OpenAIResponse {
    guard let responseValue = event.payload["response"] else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "missing response payload")
        )
    }
    let data = try JSONEncoder().encode(responseValue)
    return try JSONDecoder().decode(OpenAIResponse.self, from: data)
}

private func runtimeEncodeToolResult(_ result: ToolResult) throws -> String {
    switch result.payload {
    case .string(let text):
        return text
    default:
        let data = try JSONEncoder().encode(
            OpenAIRuntimeToolJSONValue(toolValue: result.payload)
        )
        return String(decoding: data, as: UTF8.self)
    }
}

private indirect enum OpenAIRuntimeToolJSONValue {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([OpenAIRuntimeToolJSONValue])
    case object([String: OpenAIRuntimeToolJSONValue])
    case null

    init(toolValue: ToolValue) {
        switch toolValue {
        case .string(let string):
            self = .string(string)
        case .integer(let integer):
            self = .integer(integer)
        case .number(let number):
            self = .number(number)
        case .boolean(let boolean):
            self = .boolean(boolean)
        case .array(let array):
            self = .array(array.map(OpenAIRuntimeToolJSONValue.init(toolValue:)))
        case .object(let object):
            self = .object(object.mapValues(OpenAIRuntimeToolJSONValue.init(toolValue:)))
        case .null:
            self = .null
        }
    }
}

extension OpenAIRuntimeToolJSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
            return
        }
        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let array = try? container.decode([OpenAIRuntimeToolJSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: OpenAIRuntimeToolJSONValue].self) {
            self = .object(object)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "unsupported tool JSON value"
        )
    }

    func encode(to encoder: any Encoder) throws {
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
