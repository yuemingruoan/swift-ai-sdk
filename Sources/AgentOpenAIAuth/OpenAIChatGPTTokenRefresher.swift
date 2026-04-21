import AgentOpenAI
import Foundation

public struct OpenAIChatGPTTokenRefresher: OpenAITokenRefresher, Sendable {
    public let configuration: OpenAIChatGPTOAuthConfiguration
    public let session: any OpenAIHTTPSession
    public let clock: @Sendable () -> Date

    public init(
        configuration: OpenAIChatGPTOAuthConfiguration = .init(),
        session: any OpenAIHTTPSession = URLSession.shared,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.session = session
        self.clock = clock
    }

    public func refreshTokens(
        current: OpenAIAuthTokens,
        reason _: OpenAITokenRefreshReason
    ) async throws -> OpenAIAuthTokens {
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            throw OpenAIChatGPTOAuthError.missingRefreshToken
        }

        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedData([
            ("grant_type", "refresh_token"),
            ("client_id", configuration.clientID),
            ("refresh_token", refreshToken),
        ])

        let (data, response) = try await session.data(for: request)
        let payload = try decodeResponse(
            OpenAIChatGPTTokenEndpointResponse.self,
            data: data,
            response: response
        )
        return mapTokenResponse(payload, current: current, clock: clock)
    }
}

struct OpenAIChatGPTTokenEndpointResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

func mapTokenResponse(
    _ payload: OpenAIChatGPTTokenEndpointResponse,
    current: OpenAIAuthTokens?,
    clock: @Sendable () -> Date
) -> OpenAIAuthTokens {
    let idTokenClaims = payload.idToken.flatMap(parseOpenAIJWTClaims)
    let accessTokenClaims = parseOpenAIJWTClaims(payload.accessToken)

    return OpenAIAuthTokens(
        accessToken: payload.accessToken,
        refreshToken: payload.refreshToken ?? current?.refreshToken,
        chatGPTAccountID: idTokenClaims?.chatGPTAccountID ?? current?.chatGPTAccountID,
        chatGPTPlanType: idTokenClaims?.chatGPTPlanType ?? current?.chatGPTPlanType,
        expiresAt: accessTokenClaims?.expiresAt
            ?? payload.expiresIn.map { clock().addingTimeInterval($0) }
            ?? current?.expiresAt
    )
}

func formURLEncodedData(_ items: [(String, String)]) -> Data {
    let body = items
        .map { key, value in
            "\(formURLEncode(key))=\(formURLEncode(value))"
        }
        .joined(separator: "&")
    return Data(body.utf8)
}

private func formURLEncode(_ string: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
}
