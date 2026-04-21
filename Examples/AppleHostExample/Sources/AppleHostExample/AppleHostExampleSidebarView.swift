import AppleHostExampleSupport
import SwiftUI

struct AppleHostExampleSidebarView: View {
    @Bindable var model: AppleHostExampleModel
    let strings: AppleHostExampleStrings
    let onSelectSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(strings.sidebarTitle)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(strings.newChat) {
                    model.createSession()
                }
            }

            if model.sessions.isEmpty {
                Text(strings.noSessions)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.sessions) { session in
                            Button {
                                onSelectSession(session.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(session.detail.isEmpty ? strings.noMessagesYet : session.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(strings.turnsLabel(session.turnCount))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(
                                            model.selectedSessionID == session.id
                                                ? Color.accentColor.opacity(0.18)
                                                : Color.secondary.opacity(0.08)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle(strings.windowTitle)
    }
}
