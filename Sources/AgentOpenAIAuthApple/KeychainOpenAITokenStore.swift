import AgentOpenAIAuth
import Foundation
import Security

/// Apple Keychain adapter errors that preserve underlying `Security` framework status codes.
public enum KeychainOpenAITokenStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidStoredData
}

/// Injectable wrapper around the `Security` framework functions used by the Keychain token store.
public struct KeychainClient: Sendable {
    public var add: @Sendable ([CFString: Any]) async -> OSStatus
    public var update: @Sendable ([CFString: Any], [CFString: Any]) async -> OSStatus
    public var copyMatching: @Sendable ([CFString: Any], UnsafeMutablePointer<CFTypeRef?>?) async -> OSStatus
    public var delete: @Sendable ([CFString: Any]) async -> OSStatus

    /// Creates a Keychain client from async wrappers around the underlying `Security` calls.
    public init(
        add: @escaping @Sendable ([CFString: Any]) async -> OSStatus,
        update: @escaping @Sendable ([CFString: Any], [CFString: Any]) async -> OSStatus,
        copyMatching: @escaping @Sendable ([CFString: Any], UnsafeMutablePointer<CFTypeRef?>?) async -> OSStatus,
        delete: @escaping @Sendable ([CFString: Any]) async -> OSStatus
    ) {
        self.add = add
        self.update = update
        self.copyMatching = copyMatching
        self.delete = delete
    }

    /// Live Keychain client backed by `SecItemAdd`, `SecItemUpdate`, `SecItemCopyMatching`, and `SecItemDelete`.
    public static let live = Self(
        add: { query in
            SecItemAdd(query as CFDictionary, nil)
        },
        update: { query, attributes in
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        },
        copyMatching: { query, result in
            SecItemCopyMatching(query as CFDictionary, result)
        },
        delete: { query in
            SecItemDelete(query as CFDictionary)
        }
    )

    /// Test helper that creates a configurable in-memory-like Keychain client facade.
    static func mock(
        add: @escaping @Sendable ([CFString: Any]) async -> OSStatus = { _ in errSecSuccess },
        update: @escaping @Sendable ([CFString: Any], [CFString: Any]) async -> OSStatus = { _, _ in errSecSuccess },
        copyMatching: @escaping @Sendable ([CFString: Any], UnsafeMutablePointer<CFTypeRef?>?) async -> OSStatus = { _, _ in errSecItemNotFound },
        delete: @escaping @Sendable ([CFString: Any]) async -> OSStatus = { _ in errSecSuccess }
    ) -> Self {
        Self(
            add: add,
            update: update,
            copyMatching: copyMatching,
            delete: delete
        )
    }
}

/// `OpenAITokenStore` implementation backed by the Apple Keychain.
public struct KeychainOpenAITokenStore: OpenAITokenStore, Sendable {
    /// Configuration for the Keychain item used to persist OpenAI auth tokens.
    public struct Configuration: Equatable, Sendable {
        public var service: String
        public var account: String
        public var accessGroup: String?

        /// Creates Keychain item configuration for the token store.
        public init(
            service: String,
            account: String = "openai-auth-tokens",
            accessGroup: String? = nil
        ) {
            self.service = service
            self.account = account
            self.accessGroup = accessGroup
        }
    }

    public let configuration: Configuration
    let client: KeychainClient

    /// Creates a Keychain-backed token store.
    public init(
        configuration: Configuration,
        client: KeychainClient = .live
    ) {
        self.configuration = configuration
        self.client = client
    }

    /// Loads the current token bundle from the configured Keychain item, if present.
    public func loadTokens() async throws -> OpenAIAuthTokens? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = await client.copyMatching(query, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainOpenAITokenStoreError.invalidStoredData
            }
            return try decodeTokens(from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainOpenAITokenStoreError.unexpectedStatus(status)
        }
    }

    /// Saves the supplied token bundle into the configured Keychain item, updating it when it already exists.
    public func saveTokens(_ tokens: OpenAIAuthTokens) async throws {
        let data = try encodeTokens(tokens)
        var lookupQuery = baseQuery()
        lookupQuery[kSecReturnData] = true
        lookupQuery[kSecMatchLimit] = kSecMatchLimitOne

        let status = await client.copyMatching(lookupQuery, nil)
        switch status {
        case errSecSuccess:
            let updateStatus = await client.update(
                baseQuery(),
                [kSecValueData: data]
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainOpenAITokenStoreError.unexpectedStatus(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = baseQuery()
            addQuery[kSecValueData] = data
            let addStatus = await client.add(addQuery)
            guard addStatus == errSecSuccess else {
                throw KeychainOpenAITokenStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainOpenAITokenStoreError.unexpectedStatus(status)
        }
    }

    /// Clears the configured Keychain item when it exists.
    public func clearTokens() async throws {
        let status = await client.delete(baseQuery())
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainOpenAITokenStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configuration.service,
            kSecAttrAccount: configuration.account,
        ]

        if let accessGroup = configuration.accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup] = accessGroup
        }

        return query
    }
}

private struct StoredOpenAIAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var chatGPTAccountID: String?
    var chatGPTPlanType: String?
    var expiresAt: Date?

    init(tokens: OpenAIAuthTokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        chatGPTAccountID = tokens.chatGPTAccountID
        chatGPTPlanType = tokens.chatGPTPlanType
        expiresAt = tokens.expiresAt
    }

    var tokens: OpenAIAuthTokens {
        OpenAIAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            chatGPTAccountID: chatGPTAccountID,
            chatGPTPlanType: chatGPTPlanType,
            expiresAt: expiresAt
        )
    }
}

private func encodeTokens(_ tokens: OpenAIAuthTokens) throws -> Data {
    try JSONEncoder().encode(StoredOpenAIAuthTokens(tokens: tokens))
}

private func decodeTokens(from data: Data) throws -> OpenAIAuthTokens {
    do {
        return try JSONDecoder()
            .decode(StoredOpenAIAuthTokens.self, from: data)
            .tokens
    } catch {
        throw KeychainOpenAITokenStoreError.invalidStoredData
    }
}
