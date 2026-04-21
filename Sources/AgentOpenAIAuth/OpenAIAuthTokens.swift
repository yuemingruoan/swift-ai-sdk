import Foundation

public struct OpenAIAuthTokens: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var chatGPTAccountID: String?
    public var chatGPTPlanType: String?
    public var expiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        chatGPTAccountID: String? = nil,
        chatGPTPlanType: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.chatGPTAccountID = chatGPTAccountID
        self.chatGPTPlanType = chatGPTPlanType
        self.expiresAt = expiresAt
    }
}
