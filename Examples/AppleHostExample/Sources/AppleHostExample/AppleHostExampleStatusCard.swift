import AppleHostExampleSupport
import SwiftUI

struct AppleHostExampleStatusCard: View {
    @Bindable var model: AppleHostExampleModel
    let strings: AppleHostExampleStrings
    @Binding var language: AppleHostExampleLanguage
    let onStartLogin: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.windowTitle)
                        .font(.title.weight(.semibold))
                    Text(statusDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let latestEventText = model.latestEventText {
                        Text(latestEventText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Picker(strings.language, selection: $language) {
                        Text(strings.systemLanguage).tag(AppleHostExampleLanguage.system)
                        Text(strings.english).tag(AppleHostExampleLanguage.english)
                        Text(strings.simplifiedChinese).tag(AppleHostExampleLanguage.simplifiedChinese)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    Button(actionButtonTitle) {
                        switch model.authState {
                        case .signedOut:
                            onStartLogin()
                        case .waitingForBrowserCallback:
                            break
                        case .signedIn:
                            onSignOut()
                        }
                    }
                    .disabled(model.authState == .waitingForBrowserCallback)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    label(strings.mode)
                    Picker(strings.mode, selection: $model.transportMode) {
                        Text(strings.responsesMode).tag(AppleHostExampleTransportMode.responses)
                        Text(strings.webSocketMode).tag(AppleHostExampleTransportMode.webSocket)
                    }
                    .pickerStyle(.segmented)
                }
                GridRow {
                    label(strings.model)
                    TextField(strings.model, text: $model.modelName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label(strings.baseURL)
                    TextField(strings.baseURL, text: $model.baseURLString)
                        .textFieldStyle(.roundedBorder)
                }
                if model.transportMode == .webSocket && !model.webSocketUsesChatGPTAuth {
                    GridRow {
                        label(strings.apiKey)
                        SecureField(strings.realtimeAPIKeyPlaceholder, text: $model.realtimeAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                GridRow {
                    label(strings.callback)
                    Text(strings.callbackValue)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusDescription: String {
        switch model.transportMode {
        case .responses:
            return strings.authDescription(for: model.authState)
        case .webSocket:
            return strings.webSocketDescription(
                authState: model.authState,
                hasAPIKey: model.hasRealtimeAPIKey,
                usesChatGPTAuth: model.webSocketUsesChatGPTAuth
            )
        }
    }

    private var actionButtonTitle: String {
        switch model.authState {
        case .signedOut:
            return strings.signIn
        case .waitingForBrowserCallback:
            return strings.signingIn
        case .signedIn:
            return strings.signOut
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
    }
}
