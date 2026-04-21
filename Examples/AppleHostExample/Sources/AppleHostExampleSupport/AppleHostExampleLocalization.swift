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

    public var windowTitle: String {
        value(en: "Apple Host Example", zh: "Apple 平台示例")
    }

    public var sidebarTitle: String {
        value(en: "Sessions", zh: "会话")
    }

    public var newChat: String {
        value(en: "New Chat", zh: "新会话")
    }

    public var signIn: String {
        value(en: "Sign In with ChatGPT", zh: "使用 ChatGPT 登录")
    }

    public var signOut: String {
        value(en: "Sign Out", zh: "退出登录")
    }

    public var signingIn: String {
        value(en: "Waiting for browser sign-in…", zh: "等待浏览器完成登录…")
    }

    public var model: String {
        value(en: "Model", zh: "模型")
    }

    public var mode: String {
        value(en: "Mode", zh: "模式")
    }

    public var responsesMode: String {
        value(en: "Responses", zh: "Responses")
    }

    public var webSocketMode: String {
        value(en: "WebSocket", zh: "WebSocket")
    }

    public var baseURL: String {
        value(en: "Base URL", zh: "Base URL")
    }

    public var apiKey: String {
        value(en: "API Key", zh: "API Key")
    }

    public var realtimeAPIKeyPlaceholder: String {
        value(en: "Realtime API key", zh: "Realtime API key")
    }

    public var callback: String {
        value(en: "Callback", zh: "回调地址")
    }

    public var callbackValue: String {
        AppleHostExampleDefaults.redirectURLString
    }

    public var language: String {
        value(en: "Language", zh: "语言")
    }

    public var systemLanguage: String {
        value(en: "System", zh: "跟随系统")
    }

    public var english: String {
        value(en: "English", zh: "英文")
    }

    public var simplifiedChinese: String {
        value(en: "Simplified Chinese", zh: "简体中文")
    }

    public var conversation: String {
        value(en: "Conversation", zh: "对话")
    }

    public var emptyConversation: String {
        value(
            en: "Sign in, then try a prompt like weather in Paris to see browser OAuth, tool calling, streaming, and persistence work together.",
            zh: "先完成登录，再试试“Paris 的天气怎么样”之类的提示词，就能看到浏览器 OAuth、工具调用、流式输出和持久化一起工作。"
        )
    }

    public var composerPlaceholder: String {
        value(
            en: "Ask anything. Weather prompts are good for showing the tool loop.",
            zh: "输入任意问题。天气类提示词很适合演示工具调用。"
        )
    }

    public var sendPrompt: String {
        value(en: "Send", zh: "发送")
    }

    public var running: String {
        value(en: "Running…", zh: "运行中…")
    }

    public var signInFirst: String {
        value(en: "Sign in first to send prompts.", zh: "请先登录，再发送提示词。")
    }

    public var enterAPIKeyFirst: String {
        value(en: "Enter an API key to use WebSocket mode.", zh: "请输入 API key 后再使用 WebSocket 模式。")
    }

    public var sessionID: String {
        value(en: "Session ID", zh: "会话 ID")
    }

    public var demoPrompts: String {
        value(en: "Demo Prompts", zh: "示例提示词")
    }

    public var errorTitle: String {
        value(en: "Apple Host Example Error", zh: "Apple 示例错误")
    }

    public var ok: String {
        value(en: "OK", zh: "确定")
    }

    public var weatherPromptTitle: String {
        value(en: "Weather with tool use", zh: "天气查询与工具调用")
    }

    public var memoryPromptTitle: String {
        value(en: "Multi-turn memory", zh: "多轮记忆")
    }

    public var architecturePromptTitle: String {
        value(en: "Architecture explanation", zh: "架构说明")
    }

    public var weatherPromptText: String {
        value(
            en: "What is the weather in Paris? Use the tool and keep the answer short.",
            zh: "Paris 的天气怎么样？请调用工具，并保持回答简短。"
        )
    }

    public var memoryPromptText: String {
        value(
            en: "Remember that my favorite city is Tokyo, then summarize it in one sentence.",
            zh: "记住我最喜欢的城市是东京，然后用一句话总结。"
        )
    }

    public var architecturePromptText: String {
        value(
            en: "Explain why a SwiftData adapter should stay outside a cross-platform core SDK.",
            zh: "解释为什么 SwiftData 适配层应该放在跨平台核心 SDK 之外。"
        )
    }

    public var noSessions: String {
        value(en: "No saved sessions yet.", zh: "还没有保存过会话。")
    }

    public var noMessagesYet: String {
        value(en: "No messages yet", zh: "还没有消息")
    }

    public var userRole: String {
        value(en: "User", zh: "用户")
    }

    public var assistantRole: String {
        value(en: "Assistant", zh: "助手")
    }

    public func callingTool(_ toolName: String) -> String {
        switch resolvedLanguage {
        case .english:
            return "Calling tool: \(toolName)"
        case .simplifiedChinese:
            return "正在调用工具：\(toolName)"
        }
    }

    public func turnsLabel(_ count: Int) -> String {
        switch resolvedLanguage {
        case .english:
            return "\(count) turns"
        case .simplifiedChinese:
            return "\(count) 轮"
        }
    }

    public func webSocketDescription(
        authState: AppleHostExampleAuthState,
        hasAPIKey: Bool,
        usesChatGPTAuth: Bool
    ) -> String {
        switch resolvedLanguage {
        case .english:
            if usesChatGPTAuth {
                switch authState {
                case .signedIn:
                    return "WebSocket mode is ready. The demo will use the Codex responses websocket with stored ChatGPT OAuth credentials."
                case .waitingForBrowserCallback:
                    return "Browser login is in progress. Once it finishes, WebSocket mode will use the saved ChatGPT OAuth credentials."
                case .signedOut:
                    return "WebSocket mode for chatgpt.com uses ChatGPT OAuth. Sign in first, then the demo will connect through the Codex responses websocket."
                }
            }
            if hasAPIKey {
                return "WebSocket mode is ready. The demo will use the provided API key through the Responses websocket transport."
            }
            return "WebSocket mode requires an OpenAI API key for this backend."
        case .simplifiedChinese:
            if usesChatGPTAuth {
                switch authState {
                case .signedIn:
                    return "WebSocket 模式已就绪。示例会使用已保存的 ChatGPT OAuth 凭证接入 Codex responses websocket。"
                case .waitingForBrowserCallback:
                    return "浏览器登录进行中。完成后，WebSocket 模式会使用保存下来的 ChatGPT OAuth 凭证。"
                case .signedOut:
                    return "当前这个 chatgpt.com 后端的 WebSocket 模式依赖 ChatGPT OAuth。请先登录，示例随后会通过 Codex responses websocket 建连。"
                }
            }
            if hasAPIKey {
                return "WebSocket 模式已就绪。示例会使用你提供的 API key 通过 Responses websocket 传输。"
            }
            return "当前这个后端的 WebSocket 模式需要 OpenAI API key。"
        }
    }

    public func authDescription(for state: AppleHostExampleAuthState) -> String {
        switch state {
        case .signedOut:
            return value(
                en: "No stored ChatGPT OAuth token. The app will open your default browser and complete the localhost callback automatically.",
                zh: "当前没有保存的 ChatGPT OAuth token。点击登录后，应用会拉起默认浏览器，并通过本机回调自动完成授权。"
            )
        case .waitingForBrowserCallback:
            return value(
                en: "Browser login is in progress. Finish sign-in in the browser window that just opened.",
                zh: "浏览器登录进行中。请在刚刚打开的浏览器窗口里完成登录。"
            )
        case .signedIn(let accountID, let planType):
            let accountPart = accountID ?? value(en: "unknown account", zh: "未知账户")
            let planPart = planType ?? value(en: "unknown plan", zh: "未知套餐")
            return value(
                en: "Signed in as \(accountPart) on \(planPart). Tokens are stored in Keychain.",
                zh: "当前账户 \(accountPart)，套餐 \(planPart)。Token 已保存到 Keychain。"
            )
        }
    }

    private func value(en: String, zh: String) -> String {
        switch resolvedLanguage {
        case .english:
            return en
        case .simplifiedChinese:
            return zh
        }
    }
}
