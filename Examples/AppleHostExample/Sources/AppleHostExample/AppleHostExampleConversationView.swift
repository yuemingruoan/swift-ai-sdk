import AppleHostExampleSupport
import AgentCore
import SwiftUI

struct AppleHostExampleConversationView: View {
    @Bindable var model: AppleHostExampleModel
    let strings: AppleHostExampleStrings
    let onSendPrompt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.conversation)
                        .font(.title2.weight(.semibold))
                    Text(sessionSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu(strings.demoPrompts) {
                    Button(strings.weatherPromptTitle) {
                        model.loadDemoPrompt(strings.weatherPromptText)
                    }
                    Button(strings.memoryPromptTitle) {
                        model.loadDemoPrompt(strings.memoryPromptText)
                    }
                    Button(strings.architecturePromptTitle) {
                        model.loadDemoPrompt(strings.architecturePromptText)
                    }
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let activeToolName = model.activeToolName {
                        toolStatusBadge(name: activeToolName)
                    }
                    if model.displayedMessages.isEmpty {
                        Text(strings.emptyConversation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 32)
                    } else {
                        ForEach(Array(model.displayedMessages.enumerated()), id: \.offset) { _, message in
                            messageBubble(message)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                TextField(strings.composerPlaceholder, text: $model.draftPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 6)

                HStack {
                    Text(footerText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.isSending ? strings.running : strings.sendPrompt) {
                        onSendPrompt()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isSending || !isSignedIn)
                }
            }
            .padding(20)
            .background(Color.secondary.opacity(0.06))
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var isSignedIn: Bool {
        switch model.transportMode {
        case .responses:
            if case .signedIn = model.authState {
                return true
            }
            return false
        case .webSocket:
            return model.hasRealtimeCredentials
        }
    }

    private var sessionSummary: String {
        let sessionID = model.selectedSessionID ?? model.conversationState.sessionID
        return "\(strings.sessionID): \(sessionID)"
    }

    private var footerText: String {
        if isSignedIn {
            return sessionSummary
        }
        switch model.transportMode {
        case .responses:
            return strings.signInFirst
        case .webSocket:
            return model.webSocketUsesChatGPTAuth ? strings.signInFirst : strings.enterAPIKeyFirst
        }
    }

    private func messageBubble(_ message: AgentMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .user ? strings.userRole : strings.assistantRole)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(render(message))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09))
                )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func toolStatusBadge(name: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(strings.callingTool(name))
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func render(_ message: AgentMessage) -> String {
        message.parts.map { part in
            switch part {
            case .text(let text):
                return text
            case .image(let url):
                return "[image: \(url.absoluteString)]"
            }
        }
        .joined(separator: " ")
    }
}
