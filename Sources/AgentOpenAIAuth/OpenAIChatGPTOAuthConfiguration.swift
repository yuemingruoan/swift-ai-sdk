import Foundation

public struct OpenAIChatGPTOAuthConfiguration: Equatable, Sendable {
    public static let codexCLIClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let codexCLIOriginator = "codex_cli_rs"
    public static let defaultScope = "openid profile email offline_access api.connectors.read api.connectors.invoke"

    public var issuer: URL
    public var clientID: String
    public var scope: String
    public var originator: String?
    public var deviceCodeTimeout: TimeInterval
    public var browserRedirectURL: URL?
    public var allowedWorkspaceID: String?

    public init(
        issuer: URL = URL(string: "https://auth.openai.com")!,
        clientID: String = Self.codexCLIClientID,
        scope: String = Self.defaultScope,
        originator: String? = Self.codexCLIOriginator,
        deviceCodeTimeout: TimeInterval = 15 * 60,
        browserRedirectURL: URL? = nil,
        allowedWorkspaceID: String? = nil
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.scope = scope
        self.originator = originator
        self.deviceCodeTimeout = deviceCodeTimeout
        self.browserRedirectURL = browserRedirectURL
        self.allowedWorkspaceID = allowedWorkspaceID
    }

    public var authorizationURL: URL {
        issuer.appendingPathComponent("oauth/authorize")
    }

    public var tokenURL: URL {
        issuer.appendingPathComponent("oauth/token")
    }

    public var deviceCodeUserCodeURL: URL {
        issuer.appendingPathComponent("api/accounts/deviceauth/usercode")
    }

    public var deviceCodeTokenURL: URL {
        issuer.appendingPathComponent("api/accounts/deviceauth/token")
    }

    public var deviceVerificationURL: URL {
        issuer.appendingPathComponent("codex/device")
    }

    public var deviceCodeRedirectURL: URL {
        issuer.appendingPathComponent("deviceauth/callback")
    }
}
