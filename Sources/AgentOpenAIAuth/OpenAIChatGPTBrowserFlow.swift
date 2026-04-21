import AgentOpenAI
import CryptoKit
import Foundation

public struct OpenAIChatGPTBrowserAuthorizationSessionData: Equatable, Sendable {
    public var sessionID: String
    public var state: String
    public var codeVerifier: String
    public var codeChallenge: String

    public init(
        sessionID: String,
        state: String,
        codeVerifier: String,
        codeChallenge: String
    ) {
        self.sessionID = sessionID
        self.state = state
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
    }

    public static func generate() -> Self {
        let verifierBytes = randomBytes(count: 64)
        let codeVerifier = base64URLEncode(verifierBytes)
        let codeChallenge = base64URLEncode(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
        return Self(
            sessionID: UUID().uuidString.lowercased(),
            state: base64URLEncode(randomBytes(count: 32)),
            codeVerifier: codeVerifier,
            codeChallenge: codeChallenge
        )
    }
}

public final class OpenAIChatGPTBrowserFlow: OpenAIOAuthFlow, @unchecked Sendable {
    private let configuration: OpenAIChatGPTOAuthConfiguration
    private let session: any OpenAIHTTPSession
    private let sessionFactory: @Sendable () -> OpenAIChatGPTBrowserAuthorizationSessionData
    private let clock: @Sendable () -> Date
    private let store = OpenAIChatGPTBrowserSessionStore()

    public init(
        configuration: OpenAIChatGPTOAuthConfiguration = .init(),
        session: any OpenAIHTTPSession = URLSession.shared,
        sessionFactory: @escaping @Sendable () -> OpenAIChatGPTBrowserAuthorizationSessionData = {
            .generate()
        },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.session = session
        self.sessionFactory = sessionFactory
        self.clock = clock
    }

    public func startAuthorization(method: OpenAIOAuthMethod) async throws -> OpenAIOAuthSession {
        guard method == .browser else {
            throw OpenAIChatGPTOAuthError.unsupportedAuthorizationMethod(method)
        }
        guard let redirectURL = configuration.browserRedirectURL else {
            throw OpenAIChatGPTOAuthError.missingBrowserRedirectURL
        }

        let sessionData = sessionFactory()
        await store.save(sessionData)

        var components = URLComponents(url: configuration.authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "redirect_uri", value: redirectURL.absoluteString),
            .init(name: "scope", value: configuration.scope),
            .init(name: "code_challenge", value: sessionData.codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "id_token_add_organizations", value: "true"),
            .init(name: "codex_cli_simplified_flow", value: "true"),
            .init(name: "state", value: sessionData.state),
        ]

        if let originator = configuration.originator, !originator.isEmpty {
            components?.queryItems?.append(.init(name: "originator", value: originator))
        }
        if let allowedWorkspaceID = configuration.allowedWorkspaceID, !allowedWorkspaceID.isEmpty {
            components?.queryItems?.append(.init(name: "allowed_workspace_id", value: allowedWorkspaceID))
        }

        guard let authorizationURL = components?.url else {
            throw OpenAIChatGPTOAuthError.invalidResponse
        }

        return OpenAIOAuthSession(
            sessionID: sessionData.sessionID,
            method: .browser,
            authorizationURL: authorizationURL,
            verificationURL: nil,
            userCode: nil
        )
    }

    public func completeAuthorization(sessionID _: String) async throws -> OpenAIAuthTokens {
        throw OpenAIChatGPTOAuthError.callbackURLRequired
    }

    public func completeAuthorization(
        sessionID: String,
        callbackURL: URL
    ) async throws -> OpenAIAuthTokens {
        guard let redirectURL = configuration.browserRedirectURL else {
            throw OpenAIChatGPTOAuthError.missingBrowserRedirectURL
        }
        guard let sessionData = await store.load(sessionID: sessionID) else {
            throw OpenAIChatGPTOAuthError.unknownAuthorizationSession
        }

        do {
            let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

            if let errorCode = values["error"], !errorCode.isEmpty {
                throw OpenAIChatGPTOAuthError.callbackError(
                    code: errorCode,
                    description: values["error_description"]
                )
            }

            guard values["state"] == sessionData.state else {
                throw OpenAIChatGPTOAuthError.stateMismatch
            }
            guard let code = values["code"], !code.isEmpty else {
                throw OpenAIChatGPTOAuthError.missingAuthorizationCode
            }

            var request = URLRequest(url: configuration.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formURLEncodedData([
                ("grant_type", "authorization_code"),
                ("code", code),
                ("redirect_uri", redirectURL.absoluteString),
                ("client_id", configuration.clientID),
                ("code_verifier", sessionData.codeVerifier),
            ])

            let (data, response) = try await session.data(for: request)
            let payload = try decodeResponse(
                OpenAIChatGPTTokenEndpointResponse.self,
                data: data,
                response: response
            )
            await store.remove(sessionID: sessionID)
            return mapTokenResponse(payload, current: nil, clock: clock)
        } catch {
            await store.remove(sessionID: sessionID)
            throw error
        }
    }
}

private actor OpenAIChatGPTBrowserSessionStore {
    private var sessions: [String: OpenAIChatGPTBrowserAuthorizationSessionData] = [:]

    func save(_ session: OpenAIChatGPTBrowserAuthorizationSessionData) {
        sessions[session.sessionID] = session
    }

    func load(sessionID: String) -> OpenAIChatGPTBrowserAuthorizationSessionData? {
        sessions[sessionID]
    }

    func remove(sessionID: String) {
        sessions.removeValue(forKey: sessionID)
    }
}

private func randomBytes(count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    return Data(bytes)
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
