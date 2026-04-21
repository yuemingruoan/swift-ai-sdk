import Foundation

public enum OpenAIOAuthMethod: Equatable, Sendable {
    case browser
    case deviceCode
}

public struct OpenAIOAuthSession: Equatable, Sendable {
    public var sessionID: String
    public var method: OpenAIOAuthMethod
    public var authorizationURL: URL?
    public var verificationURL: URL?
    public var userCode: String?

    public init(
        sessionID: String,
        method: OpenAIOAuthMethod,
        authorizationURL: URL? = nil,
        verificationURL: URL? = nil,
        userCode: String? = nil
    ) {
        self.sessionID = sessionID
        self.method = method
        self.authorizationURL = authorizationURL
        self.verificationURL = verificationURL
        self.userCode = userCode
    }
}

public protocol OpenAIOAuthFlow: Sendable {
    func startAuthorization(method: OpenAIOAuthMethod) async throws -> OpenAIOAuthSession
    func completeAuthorization(sessionID: String) async throws -> OpenAIAuthTokens
}
