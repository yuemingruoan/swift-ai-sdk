import Foundation
import AgentCore
import AgentPersistence
import Testing

struct FileAgentStoreTests {
    @Test func saves_sessions_to_disk_and_loads_them_after_reinstantiation() async throws {
        let directoryURL = makeTemporaryDirectory()
        let store = try FileAgentStore(directoryURL: directoryURL)

        try await store.saveSession(.init(id: "session-1"))
        try await store.saveSession(.init(id: "session-2"))

        let reloaded = try FileAgentStore(directoryURL: directoryURL)

        #expect(try await reloaded.listSessions() == [
            AgentSession(id: "session-1"),
            AgentSession(id: "session-2"),
        ])
    }

    @Test func appends_turns_to_disk_and_loads_them_after_reinstantiation() async throws {
        let directoryURL = makeTemporaryDirectory()
        let store = try FileAgentStore(directoryURL: directoryURL)

        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("first")],
                output: [assistantMessage("one")]
            )
        )
        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("second")],
                output: [assistantMessage("two")]
            )
        )

        let reloaded = try FileAgentStore(directoryURL: directoryURL)

        #expect(try await reloaded.turns(forSessionID: "session-1") == [
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("first")],
                output: [assistantMessage("one")],
                sequenceNumber: 0
            ),
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("second")],
                output: [assistantMessage("two")],
                sequenceNumber: 1
            ),
        ])
    }

    @Test func deleting_session_removes_persisted_turns_too() async throws {
        let directoryURL = makeTemporaryDirectory()
        let store = try FileAgentStore(directoryURL: directoryURL)

        try await store.saveSession(.init(id: "session-1"))
        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("hello")],
                output: [assistantMessage("world")]
            )
        )

        try await store.deleteSession(id: "session-1")

        let reloaded = try FileAgentStore(directoryURL: directoryURL)

        #expect(try await reloaded.session(id: "session-1") == nil)
        #expect(try await reloaded.turns(forSessionID: "session-1").isEmpty)
    }
}

private func makeTemporaryDirectory() -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.removeItem(at: directoryURL)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func assistantMessage(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
