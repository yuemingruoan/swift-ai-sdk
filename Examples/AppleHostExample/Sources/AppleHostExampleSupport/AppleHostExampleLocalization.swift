import Foundation

public enum AppleHostExampleLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    public var id: String { rawValue }

    var resolvedLanguage: AppleHostExampleResolvedLanguage? {
        switch self {
        case .system:
            return nil
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        }
    }
}

public enum AppleHostExampleResolvedLanguage: Sendable {
    case english
    case simplifiedChinese

    var localizationIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-hans"
        }
    }

    var locale: Locale {
        Locale(identifier: localizationIdentifier)
    }
}

public struct AppleHostExampleStrings: Sendable {
    private let resolvedLanguage: AppleHostExampleResolvedLanguage

    public init(
        language: AppleHostExampleLanguage,
        locale: Locale = .autoupdatingCurrent
    ) {
        if let explicit = language.resolvedLanguage {
            self.resolvedLanguage = explicit
        } else {
            let identifier = locale.identifier.lowercased()
            let languageCode = locale.language.languageCode?.identifier.lowercased()
            if identifier.contains("zh-hans") || identifier.contains("zh_cn") || languageCode == "zh" {
                self.resolvedLanguage = .simplifiedChinese
            } else {
                self.resolvedLanguage = .english
            }
        }
    }

    public var windowTitle: String { localized("window_title", default: "Apple Host Example") }
    public var sidebarTitle: String { localized("sidebar_title", default: "Sessions") }
    public var newChat: String { localized("new_chat", default: "New Chat") }
    public var signIn: String { localized("sign_in", default: "Sign In with ChatGPT") }
    public var signOut: String { localized("sign_out", default: "Sign Out") }
    public var signingIn: String { localized("signing_in", default: "Waiting for browser sign-in…") }
    public var model: String { localized("model", default: "Model") }
    public var mode: String { localized("mode", default: "Mode") }
    public var responsesMode: String { localized("responses_mode", default: "Responses") }
    public var webSocketMode: String { localized("websocket_mode", default: "WebSocket") }
    public var baseURL: String { localized("base_url", default: "Base URL") }
    public var apiKey: String { localized("api_key", default: "API Key") }
    public var realtimeAPIKeyPlaceholder: String { localized("realtime_api_key_placeholder", default: "OpenAI API key") }
    public var callback: String { localized("callback", default: "Callback") }

    public var callbackValue: String {
        AppleHostExampleDefaults.redirectURLString
    }

    public var language: String { localized("language", default: "Language") }
    public var systemLanguage: String { localized("system_language", default: "System") }
    public var english: String { localized("english", default: "English") }
    public var simplifiedChinese: String { localized("simplified_chinese", default: "Simplified Chinese") }
    public var conversation: String { localized("conversation", default: "Conversation") }
    public var emptyConversation: String {
        localized(
            "empty_conversation",
            default: "Sign in, then try a prompt like weather in Paris to see browser OAuth, tool calling, streaming, and persistence work together."
        )
    }
    public var composerPlaceholder: String {
        localized(
            "composer_placeholder",
            default: "Ask anything. Weather prompts are good for showing the tool loop."
        )
    }
    public var sendPrompt: String { localized("send_prompt", default: "Send") }
    public var running: String { localized("running", default: "Running…") }
    public var signInFirst: String { localized("sign_in_first", default: "Sign in first to send prompts.") }
    public var enterAPIKeyFirst: String { localized("enter_api_key_first", default: "Enter an API key to use WebSocket mode.") }
    public var sessionID: String { localized("session_id", default: "Session ID") }
    public var demoPrompts: String { localized("demo_prompts", default: "Demo Prompts") }
    public var errorTitle: String { localized("error_title", default: "Apple Host Example Error") }
    public var ok: String { localized("ok", default: "OK") }
    public var weatherPromptTitle: String { localized("weather_prompt_title", default: "Weather with tool use") }
    public var memoryPromptTitle: String { localized("memory_prompt_title", default: "Multi-turn memory") }
    public var architecturePromptTitle: String { localized("architecture_prompt_title", default: "Architecture explanation") }
    public var weatherPromptText: String {
        localized(
            "weather_prompt_text",
            default: "What is the weather in Paris? Use the tool and keep the answer short."
        )
    }
    public var memoryPromptText: String {
        localized(
            "memory_prompt_text",
            default: "Remember that my favorite city is Tokyo, then summarize it in one sentence."
        )
    }
    public var architecturePromptText: String {
        localized(
            "architecture_prompt_text",
            default: "Explain why a SwiftData adapter should stay outside a cross-platform core SDK."
        )
    }
    public var noSessions: String { localized("no_sessions", default: "No saved sessions yet.") }
    public var noMessagesYet: String { localized("no_messages_yet", default: "No messages yet") }
    public var userRole: String { localized("user_role", default: "User") }
    public var assistantRole: String { localized("assistant_role", default: "Assistant") }

    public func callingTool(_ toolName: String) -> String {
        formatted("calling_tool", default: "Calling tool: %@", toolName)
    }

    public func turnsLabel(_ count: Int) -> String {
        formatted("turns_label", default: "%lld turns", count)
    }

    public func sessionSummary(_ sessionID: String) -> String {
        formatted("session_summary", default: "Session ID: %@", sessionID)
    }

    public func webSocketDescription(
        authState: AppleHostExampleAuthState,
        hasAPIKey: Bool,
        usesChatGPTAuth: Bool
    ) -> String {
        if usesChatGPTAuth {
            switch authState {
            case .signedIn:
                return localized(
                    "ws_ready_chatgpt",
                    default: "WebSocket mode is ready. The demo will use the Codex responses websocket with stored ChatGPT OAuth credentials."
                )
            case .waitingForBrowserCallback:
                return localized(
                    "ws_waiting_chatgpt",
                    default: "Browser login is in progress. Once it finishes, WebSocket mode will use the saved ChatGPT OAuth credentials."
                )
            case .signedOut:
                return localized(
                    "ws_signed_out_chatgpt",
                    default: "WebSocket mode for chatgpt.com uses ChatGPT OAuth. Sign in first, then the demo will connect through the Codex responses websocket."
                )
            }
        }

        if hasAPIKey {
            return localized(
                "ws_ready_api_key",
                default: "WebSocket mode is ready. The demo will use the provided API key through the Responses websocket transport."
            )
        }

        return localized(
            "ws_requires_api_key",
            default: "WebSocket mode requires an OpenAI API key for this backend."
        )
    }

    public func authDescription(for state: AppleHostExampleAuthState) -> String {
        switch state {
        case .signedOut:
            return localized(
                "auth_signed_out",
                default: "No stored ChatGPT OAuth token. The app will open your default browser and complete the localhost callback automatically."
            )
        case .waitingForBrowserCallback:
            return localized(
                "auth_waiting",
                default: "Browser login is in progress. Finish sign-in in the browser window that just opened."
            )
        case .signedIn(let accountID, let planType):
            return formatted(
                "auth_signed_in",
                default: "Signed in as %@ on %@. Tokens are stored in Keychain.",
                accountID ?? localized("unknown_account", default: "unknown account"),
                planType ?? localized("unknown_plan", default: "unknown plan")
            )
        }
    }

    private var bundle: Bundle {
        guard let path = Bundle.module.path(
            forResource: resolvedLanguage.localizationIdentifier,
            ofType: "lproj"
        ),
        let localizedBundle = Bundle(path: path) else {
            return .module
        }
        return localizedBundle
    }

    private func localized(_ key: String, default defaultValue: String) -> String {
        bundle.localizedString(forKey: key, value: defaultValue, table: "Localizable")
    }

    private func formatted(
        _ key: String,
        default defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: localized(key, default: defaultValue),
            locale: resolvedLanguage.locale,
            arguments: arguments
        )
    }
}
