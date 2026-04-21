import AppKit
import AuthenticationServices
import Foundation
import Testing
@testable import AppleHostExampleSupport

struct AppleHostExampleAuthenticationSessionPresenterTests {
    @Test @MainActor func authenticate_starts_ephemeral_session_and_clears_it_after_background_completion() async throws {
        let authorizationURL = URL(string: "https://auth.example.com/authorize")!
        let callbackURL = URL(string: "http://127.0.0.1:1455/auth/callback?code=test-code")!

        let session = TestAuthenticationSession()
        let presenter = AppleHostExampleAuthenticationSessionPresenter(
            makeSession: { url, completion in
                #expect(url == authorizationURL)
                session.completion = completion
                return session
            },
            presentationAnchorProvider: { ASPresentationAnchor() }
        )

        let authenticationTask = Task {
            try await presenter.authenticate(at: authorizationURL)
        }

        while session.startCallCount == 0 {
            await Task.yield()
        }

        #expect(session.prefersEphemeralWebBrowserSession)

        await session.completeOnBackgroundQueue(callbackURL: callbackURL, error: nil)

        let resolvedCallbackURL = try await authenticationTask.value
        #expect(resolvedCallbackURL == callbackURL)

        presenter.cancel()
        #expect(session.cancelCallCount == 0)
    }

    @Test @MainActor func authenticate_throws_when_session_cannot_start() async {
        let authorizationURL = URL(string: "https://auth.example.com/authorize")!
        let session = TestAuthenticationSession(startResult: false)
        let presenter = AppleHostExampleAuthenticationSessionPresenter(
            makeSession: { _, completion in
                session.completion = completion
                return session
            },
            presentationAnchorProvider: { ASPresentationAnchor() }
        )

        await #expect(throws: AppleHostExampleAuthenticationSessionError.unableToStart) {
            try await presenter.authenticate(at: authorizationURL)
        }

        presenter.cancel()
        #expect(session.cancelCallCount == 0)
    }
}

private final class TestAuthenticationSession: AppleHostExampleAuthenticationSessionProtocol, @unchecked Sendable {
    var prefersEphemeralWebBrowserSession = false
    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding?
    var startCallCount = 0
    var cancelCallCount = 0
    var startResult: Bool
    var completion: ((URL?, Error?) -> Void)?

    init(startResult: Bool = true) {
        self.startResult = startResult
    }

    func start() -> Bool {
        startCallCount += 1
        return startResult
    }

    func cancel() {
        cancelCallCount += 1
    }

    func complete(callbackURL: URL?, error: Error?) {
        completion?(callbackURL, error)
    }

    func completeOnBackgroundQueue(callbackURL: URL?, error: Error?) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.complete(callbackURL: callbackURL, error: error)
                continuation.resume()
            }
        }
    }
}
