import Foundation

public enum AgentHTTPBackoffStrategy: Equatable, Sendable {
    case none
    case constant(milliseconds: Int)

    public func delayDuration() -> Duration? {
        switch self {
        case .none:
            return nil
        case .constant(let milliseconds):
            return .milliseconds(milliseconds)
        }
    }
}

public struct AgentHTTPRetryPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var backoff: AgentHTTPBackoffStrategy
    public var retryableStatusCodes: Set<Int>

    public init(
        maxAttempts: Int = 1,
        backoff: AgentHTTPBackoffStrategy = .none,
        retryableStatusCodes: [Int] = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoff = backoff
        self.retryableStatusCodes = Set(retryableStatusCodes)
    }

    public func shouldRetry(afterAttempt attempt: Int, statusCode: Int) -> Bool {
        attempt < maxAttempts && retryableStatusCodes.contains(statusCode)
    }

    public func shouldRetry(afterAttempt attempt: Int) -> Bool {
        attempt < maxAttempts
    }
}

public struct AgentHTTPTransportConfiguration: Equatable, Sendable {
    public var timeoutInterval: TimeInterval?
    public var retryPolicy: AgentHTTPRetryPolicy
    public var additionalHeaders: [String: String]
    public var userAgent: String?
    public var requestID: String?

    public init(
        timeoutInterval: TimeInterval? = nil,
        retryPolicy: AgentHTTPRetryPolicy = .init(),
        additionalHeaders: [String: String] = [:],
        userAgent: String? = nil,
        requestID: String? = nil
    ) {
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.additionalHeaders = additionalHeaders
        self.userAgent = userAgent
        self.requestID = requestID
    }
}
