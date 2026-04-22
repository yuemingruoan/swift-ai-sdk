import Foundation
import OpenAIAgentRuntime

public enum AppleHostExampleTransportMode: String, CaseIterable, Identifiable, Sendable {
    case responses
    case webSocket

    public var id: String { rawValue }
}

public enum AppleHostExampleRuntimeError: Error, Equatable, LocalizedError {
    case missingRealtimeCredentials
    case invalidRealtimeBaseURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingRealtimeCredentials:
            return "Missing realtime credentials."
        case .invalidRealtimeBaseURL(let value):
            return "Invalid realtime base URL: \(value)"
        }
    }
}

public struct AppleHostExampleRealtimeCredentials: Equatable, Sendable {
    public var authorizationValue: String
    public var accountID: String?
    public var additionalHeaders: [String: String]

    public init(
        authorizationValue: String,
        accountID: String? = nil,
        additionalHeaders: [String: String] = [:]
    ) {
        self.authorizationValue = authorizationValue
        self.accountID = accountID
        self.additionalHeaders = additionalHeaders
    }
}

public struct AppleHostExampleSessionRunner: Sendable {
    private let runTurnImpl: @Sendable (AgentConversationState, [AgentMessage]) throws -> AsyncThrowingStream<AgentSessionStreamEvent, Error>

    public init<Base: AgentTurnRunner>(base: AgentSessionRunner<Base>) {
        self.runTurnImpl = { state, input in
            try base.runTurn(state: state, input: input)
        }
    }

    public func runTurn(
        state: AgentConversationState,
        input: [AgentMessage]
    ) throws -> AsyncThrowingStream<AgentSessionStreamEvent, Error> {
        try runTurnImpl(state, input)
    }
}
