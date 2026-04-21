import AppKit
import AuthenticationServices
import Foundation

public enum AppleHostExampleAuthenticationSessionError: Error, Equatable {
    case unableToStart
    case missingCallbackURL
}

protocol AppleHostExampleAuthenticationSessionProtocol: AnyObject {
    var prefersEphemeralWebBrowserSession: Bool { get set }
    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding? { get set }

    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: AppleHostExampleAuthenticationSessionProtocol {}

public final class AppleHostExampleAuthenticationSessionPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let makeSession: (URL, @escaping (URL?, Error?) -> Void) -> any AppleHostExampleAuthenticationSessionProtocol
    private let presentationAnchorProvider: @MainActor () -> ASPresentationAnchor
    private let stateLock = NSLock()

    private var session: (any AppleHostExampleAuthenticationSessionProtocol)?
    private var presentationAnchor = ASPresentationAnchor()

    public override convenience init() {
        self.init(
            makeSession: { authorizationURL, completion in
                ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: "http",
                    completionHandler: completion
                )
            },
            presentationAnchorProvider: {
                NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
            }
        )
    }

    init(
        makeSession: @escaping (URL, @escaping (URL?, Error?) -> Void) -> any AppleHostExampleAuthenticationSessionProtocol,
        presentationAnchorProvider: @escaping @MainActor () -> ASPresentationAnchor
    ) {
        self.makeSession = makeSession
        self.presentationAnchorProvider = presentationAnchorProvider
        super.init()
    }

    @MainActor
    public func authenticate(at authorizationURL: URL) async throws -> URL {
        setPresentationAnchor(presentationAnchorProvider())

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = makeSession(authorizationURL) { [weak self] callbackURL, error in
                self?.clearSession()

                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AppleHostExampleAuthenticationSessionError.missingCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            storeSession(session)

            guard session.start() else {
                clearSession()
                continuation.resume(throwing: AppleHostExampleAuthenticationSessionError.unableToStart)
                return
            }
        }
    }

    public func cancel() {
        let session = takeSession()
        session?.cancel()
    }

    public func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        stateLock.lock()
        defer { stateLock.unlock() }
        return presentationAnchor
    }
}

private extension AppleHostExampleAuthenticationSessionPresenter {
    func storeSession(_ session: any AppleHostExampleAuthenticationSessionProtocol) {
        stateLock.lock()
        self.session = session
        stateLock.unlock()
    }

    func clearSession() {
        stateLock.lock()
        session = nil
        stateLock.unlock()
    }

    func takeSession() -> (any AppleHostExampleAuthenticationSessionProtocol)? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let session = session
        self.session = nil
        return session
    }

    func setPresentationAnchor(_ anchor: ASPresentationAnchor) {
        stateLock.lock()
        presentationAnchor = anchor
        stateLock.unlock()
    }
}
