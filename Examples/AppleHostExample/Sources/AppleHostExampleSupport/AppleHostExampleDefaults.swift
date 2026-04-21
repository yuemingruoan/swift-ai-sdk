import Foundation

public enum AppleHostExampleDefaults {
    public static let modelName = "gpt-5.4"
    public static let baseURLString = "https://chatgpt.com/backend-api/codex"
    public static let callbackHost = "localhost"
    public static let callbackPort: UInt16 = 1455
    public static let callbackPath = "/auth/callback"
    public static let redirectURLString = "http://localhost:1455/auth/callback"

    public static var redirectURL: URL {
        guard let url = URL(string: redirectURLString) else {
            preconditionFailure("Invalid redirect URL: \(redirectURLString)")
        }
        return url
    }
}
