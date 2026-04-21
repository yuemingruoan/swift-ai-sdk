import AgentOpenAIAuth
@testable import AgentOpenAIAuthApple
import Foundation
import Testing

struct KeychainOpenAITokenStoreTests {
    @Test func load_returns_nil_when_item_is_missing() async throws {
        let store = KeychainOpenAITokenStore(
            configuration: .init(service: "dev.test.swift-ai-sdk"),
            client: .mock(copyMatching: { _, _ in errSecItemNotFound })
        )

        let tokens = try await store.loadTokens()

        #expect(tokens == nil)
    }

    @Test func save_then_load_round_trips_tokens() async throws {
        let client = MockKeychainClient()
        let store = KeychainOpenAITokenStore(
            configuration: .init(
                service: "dev.test.swift-ai-sdk",
                account: "chatgpt-auth"
            ),
            client: client.client
        )
        let expected = OpenAIAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            chatGPTAccountID: "acc_123",
            chatGPTPlanType: "plus",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        try await store.saveTokens(expected)
        let loaded = try await store.loadTokens()

        #expect(loaded == expected)
        #expect(client.addCallCount == 1)
        #expect(client.updateCallCount == 0)
    }

    @Test func save_updates_existing_item_when_present() async throws {
        let client = MockKeychainClient(existingData: Data("old".utf8))
        let store = KeychainOpenAITokenStore(
            configuration: .init(service: "dev.test.swift-ai-sdk"),
            client: client.client
        )

        try await store.saveTokens(OpenAIAuthTokens(accessToken: "new-token"))

        #expect(client.addCallCount == 0)
        #expect(client.updateCallCount == 1)
    }

    @Test func clear_deletes_existing_item() async throws {
        let client = MockKeychainClient(existingData: Data("value".utf8))
        let store = KeychainOpenAITokenStore(
            configuration: .init(service: "dev.test.swift-ai-sdk"),
            client: client.client
        )

        try await store.clearTokens()
        let loaded = try await store.loadTokens()

        #expect(loaded == nil)
        #expect(client.deleteCallCount == 1)
    }
}

private final class MockKeychainClient: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data?
    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    init(existingData: Data? = nil) {
        self.storage = existingData
    }

    var client: KeychainClient {
        KeychainClient(
            add: { query in
                self.add(query: query)
            },
            update: { query, attributes in
                self.update(query: query, attributes: attributes)
            },
            copyMatching: { query, result in
                self.copyMatching(query: query, result: result)
            },
            delete: { query in
                self.delete(query: query)
            }
        )
    }

    private func add(query: [CFString: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        addCallCount += 1
        storage = query[kSecValueData] as? Data
        return errSecSuccess
    }

    private func update(query _: [CFString: Any], attributes: [CFString: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        updateCallCount += 1
        storage = attributes[kSecValueData] as? Data
        return errSecSuccess
    }

    private func copyMatching(query _: [CFString: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let storage else {
            return errSecItemNotFound
        }
        result?.pointee = storage as CFData
        return errSecSuccess
    }

    private func delete(query _: [CFString: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        deleteCallCount += 1
        storage = nil
        return errSecSuccess
    }
}
