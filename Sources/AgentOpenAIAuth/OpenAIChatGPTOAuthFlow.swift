import AgentCore
import OpenAIResponsesAPI
import Foundation

/// Device-code OAuth flow for ChatGPT/Codex-compatible authentication.
public final class OpenAIChatGPTDeviceCodeFlow: OpenAIOAuthFlow, @unchecked Sendable {
    private let configuration: OpenAIChatGPTOAuthConfiguration
    private let session: any OpenAIHTTPSession
    private let sleeper: @Sendable (TimeInterval) async -> Void
    private let clock: @Sendable () -> Date
    private let store = OpenAIChatGPTDeviceCodeSessionStore()

    /// Creates a device-code OAuth flow implementation.
    public init(
        configuration: OpenAIChatGPTOAuthConfiguration = .init(),
        session: any OpenAIHTTPSession = URLSession.shared,
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            guard seconds > 0 else {
                return
            }
            let duration = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
        },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.session = session
        self.sleeper = sleeper
        self.clock = clock
    }

    /// Starts a device-code authorization session and returns the verification URL plus user code.
    public func startAuthorization(method: OpenAIOAuthMethod) async throws -> OpenAIOAuthSession {
        guard method == .deviceCode else {
            throw AgentAuthError.unsupportedAuthorizationMethod(String(describing: method))
        }

        var request = URLRequest(url: configuration.deviceCodeUserCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeviceCodeUserCodeRequest(clientID: configuration.clientID)
        )

        let (data, response) = try await session.data(for: request)
        let payload = try decodeResponse(
            DeviceCodeUserCodeResponse.self,
            data: data,
            response: response
        )
        let deviceSession = DeviceCodeSession(
            deviceAuthID: payload.deviceAuthID,
            userCode: payload.userCode,
            interval: payload.interval
        )
        await store.save(deviceSession)

        return OpenAIOAuthSession(
            sessionID: payload.deviceAuthID,
            method: .deviceCode,
            authorizationURL: nil,
            verificationURL: configuration.deviceVerificationURL,
            userCode: payload.userCode
        )
    }

    /// Polls until the device-code session is approved and exchanges the authorization code for tokens.
    public func completeAuthorization(sessionID: String) async throws -> OpenAIAuthTokens {
        guard let deviceSession = await store.load(sessionID: sessionID) else {
            throw AgentAuthError.unknownAuthorizationSession
        }

        do {
            let codeResponse = try await pollForAuthorizationCode(session: deviceSession)
            let tokens = try await exchangeAuthorizationCode(codeResponse.authorizationCode, codeVerifier: codeResponse.codeVerifier)
            await store.remove(sessionID: sessionID)
            return tokens
        } catch {
            await store.remove(sessionID: sessionID)
            throw error
        }
    }

    private func pollForAuthorizationCode(
        session deviceSession: DeviceCodeSession
    ) async throws -> DeviceCodeTokenPollingSuccessResponse {
        let deadline = clock().addingTimeInterval(configuration.deviceCodeTimeout)

        while clock() < deadline {
            var request = URLRequest(url: configuration.deviceCodeTokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                DeviceCodeTokenPollingRequest(
                    deviceAuthID: deviceSession.deviceAuthID,
                    userCode: deviceSession.userCode
                )
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AgentTransportError.invalidResponse(provider: .openAI)
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    return try JSONDecoder().decode(
                        DeviceCodeTokenPollingSuccessResponse.self,
                        from: data
                    )
                } catch {
                    throw AgentDecodingError.responseBody(
                        provider: .openAI,
                        description: String(describing: error)
                    )
                }
            case 403, 404:
                await sleeper(deviceSession.interval)
            default:
                throw AgentProviderError.unsuccessfulResponse(
                    provider: .openAI,
                    statusCode: httpResponse.statusCode
                )
            }
        }

        throw AgentAuthError.deviceCodeTimedOut
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String
    ) async throws -> OpenAIAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", configuration.deviceCodeRedirectURL.absoluteString),
            ("client_id", configuration.clientID),
            ("code_verifier", codeVerifier),
        ])

        let (data, response) = try await session.data(for: request)
        let payload = try decodeResponse(
            OpenAIChatGPTTokenEndpointResponse.self,
            data: data,
            response: response
        )
        return mapTokenResponse(payload, current: nil, clock: clock)
    }
}

private struct DeviceCodeUserCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct DeviceCodeUserCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        userCode = try container.decode(String.self, forKey: .userCode)

        if let stringValue = try? container.decode(String.self, forKey: .interval),
           let parsed = TimeInterval(stringValue)
        {
            interval = parsed
        } else if let numericValue = try? container.decode(Double.self, forKey: .interval) {
            interval = numericValue
        } else {
            interval = 5
        }
    }
}

private struct DeviceCodeTokenPollingRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

private struct DeviceCodeTokenPollingSuccessResponse: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct DeviceCodeSession: Sendable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval
}

private actor OpenAIChatGPTDeviceCodeSessionStore {
    private var sessions: [String: DeviceCodeSession] = [:]

    func save(_ session: DeviceCodeSession) {
        sessions[session.deviceAuthID] = session
    }

    func load(sessionID: String) -> DeviceCodeSession? {
        sessions[sessionID]
    }

    func remove(sessionID: String) {
        sessions.removeValue(forKey: sessionID)
    }
}

func decodeResponse<T: Decodable>(
    _ type: T.Type,
    data: Data,
    response: URLResponse
) throws -> T {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AgentTransportError.invalidResponse(provider: .openAI)
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
        throw AgentProviderError.unsuccessfulResponse(
            provider: .openAI,
            statusCode: httpResponse.statusCode
        )
    }
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw AgentDecodingError.responseBody(
            provider: .openAI,
            description: String(describing: error)
        )
    }
}
