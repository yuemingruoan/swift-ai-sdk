import Foundation

public struct AppleHostExampleEmbeddedAuthURLMatcher: Sendable {
    private let callbackScheme: String?
    private let callbackHost: String?
    private let callbackPort: Int?
    private let callbackPath: String

    public init(callbackURL: URL) {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        callbackScheme = components?.scheme?.lowercased()
        callbackHost = components?.host?.lowercased()
        callbackPort = components?.port
        callbackPath = components?.path ?? callbackURL.path
    }

    public func matches(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        return components.scheme?.lowercased() == callbackScheme
            && components.host?.lowercased() == callbackHost
            && components.port == callbackPort
            && components.path == callbackPath
    }
}
