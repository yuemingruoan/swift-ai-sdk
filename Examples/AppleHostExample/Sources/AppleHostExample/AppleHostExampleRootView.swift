import AppleHostExampleSupport
import SwiftUI

struct AppleHostExampleRootView: View {
    @Bindable var model: AppleHostExampleModel
    @AppStorage("dev.swift-ai-sdk.apple-host-example.language")
    private var languageRawValue = AppleHostExampleLanguage.system.rawValue
    @State private var callbackListener: AppleHostExampleLoopbackCallbackListener?

    private var language: AppleHostExampleLanguage {
        get { AppleHostExampleLanguage(rawValue: languageRawValue) ?? .system }
        nonmutating set { languageRawValue = newValue.rawValue }
    }

    private var strings: AppleHostExampleStrings {
        AppleHostExampleStrings(language: language)
    }

    var body: some View {
        NavigationSplitView {
            AppleHostExampleSidebarView(
                model: model,
                strings: strings,
                onSelectSession: selectSession
            )
        } detail: {
            VStack(spacing: 18) {
                AppleHostExampleStatusCard(
                    model: model,
                    strings: strings,
                    language: Binding(
                        get: { language },
                        set: { language = $0 }
                    ),
                    onStartLogin: startLogin,
                    onSignOut: signOut
                )

                AppleHostExampleConversationView(
                    model: model,
                    strings: strings,
                    onSendPrompt: sendPrompt
                )
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color.orange.opacity(0.06),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .task {
            await model.bootstrap()
        }
        .alert(
            strings.errorTitle,
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(strings.ok) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func startLogin() {
        Task {
            guard let authorizationURL = await model.startBrowserLogin() else {
                return
            }
            let listener = AppleHostExampleLoopbackCallbackListener(
                callbackURL: AppleHostExampleDefaults.redirectURL
            )
            do {
                try await listener.start()

                let didOpenBrowser = await MainActor.run {
                    AppleHostExampleLoopbackCallbackListener.openBrowser(at: authorizationURL)
                }
                guard didOpenBrowser else {
                    await listener.cancel()
                    throw AppleHostExampleLoopbackCallbackListenerError.failedToOpenBrowser
                }

                await MainActor.run {
                    callbackListener = listener
                }

                let callbackURL = try await listener.waitForCallback()
                await model.completeBrowserLogin(with: callbackURL)
                await MainActor.run {
                    callbackListener = nil
                }
            } catch {
                await listener.cancel()
                await MainActor.run {
                    callbackListener = nil
                    model.browserLoginDidFail(error)
                }
            }
        }
    }

    private func signOut() {
        Task {
            await callbackListener?.cancel()
            await MainActor.run {
                callbackListener = nil
            }
            await model.signOut()
        }
    }

    private func sendPrompt() {
        Task {
            await model.sendPrompt()
        }
    }

    private func selectSession(_ sessionID: String) {
        Task {
            try await model.selectSession(id: sessionID)
        }
    }
}
