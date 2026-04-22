import OpenAIAgentRuntime
@testable import AppleHostExampleSupport
import Foundation
import Testing

@MainActor
struct AppleHostExampleLiveSmokeTests {
    @Test func live_model_can_send_prompt_when_enabled() async throws {
        guard smokeEnabled("APPLE_HOST_EXAMPLE_LIVE_SMOKE") else {
            return
        }

        let model = try AppleHostExampleModel.live()
        if let overrideBaseURL = ProcessInfo.processInfo.environment["APPLE_HOST_EXAMPLE_BASE_URL"],
           !overrideBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.baseURLString = overrideBaseURL
        }
        if let overrideModel = ProcessInfo.processInfo.environment["OPENAI_MODEL"],
           !overrideModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.modelName = overrideModel
        }
        model.transportMode = .responses

        await model.bootstrap()

        guard case .signedIn = model.authState else {
            Issue.record("expected AppleHostExample to load stored ChatGPT OAuth tokens from Keychain")
            return
        }

        model.createSession()
        model.draftPrompt = "Respond with exactly: APPLE_HOST_SMOKE_OK"

        await model.sendPrompt()

        #expect(model.errorMessage == nil)
        #expect(model.isSending == false)
        #expect(model.displayedMessages.contains(where: containsSmokeText))
    }
}

private func smokeEnabled(_ key: String) -> Bool {
    let value = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return value == "1" || value == "true" || value == "yes"
}

private func containsSmokeText(_ message: AgentMessage) -> Bool {
    message.parts.contains { part in
        guard case .text(let text) = part else {
            return false
        }
        return text.contains("APPLE_HOST_SMOKE_OK")
    }
}
