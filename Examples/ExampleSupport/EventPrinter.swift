import Foundation
import OpenAIAgentRuntime

public enum ExampleEventPrinter {
    public static func printEvent(_ event: AgentStreamEvent) {
        switch event {
        case .textDelta(let delta):
            print(delta, terminator: "")
            fflush(stdout)

        case .toolCall(let toolCall):
            print("\n[tool call] \(toolCall.invocation.toolName) \(describe(toolCall.invocation.input))")

        case .messagesCompleted(let messages):
            if !messages.isEmpty {
                print()
                print("[messages completed]")
                printMessages(messages)
            }

        case .turnCompleted(let turn):
            print("[turn completed] session=\(turn.sessionID) sequence=\(turn.sequenceNumber ?? -1)")
        }
    }

    public static func printSessionEvent(_ event: AgentSessionStreamEvent) {
        switch event {
        case .event(let streamEvent):
            printEvent(streamEvent)

        case .stateUpdated(let state):
            print("[state updated] session=\(state.sessionID) messages=\(state.messages.count)")
        }
    }

    public static func printMessages(_ messages: [AgentMessage]) {
        for message in messages {
            print("- \(message.role.rawValue): \(describe(message.parts))")
        }
    }

    public static func printDivider(_ title: String) {
        print("\n=== \(title) ===")
    }
}

private extension ExampleEventPrinter {
    static func describe(_ parts: [MessagePart]) -> String {
        parts.map(describe).joined(separator: " ")
    }

    static func describe(_ part: MessagePart) -> String {
        switch part {
        case .text(let text):
            return text
        case .image(let url):
            return "[image: \(url.absoluteString)]"
        }
    }

    static func describe(_ value: ToolValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .integer(let integer):
            return String(integer)
        case .number(let number):
            return String(number)
        case .boolean(let boolean):
            return String(boolean)
        case .array(let array):
            return "[" + array.map(describe).joined(separator: ", ") + "]"
        case .object(let object):
            let pairs = object.keys.sorted().map { key in
                "\(key): \(describe(object[key] ?? .null))"
            }
            return "{" + pairs.joined(separator: ", ") + "}"
        case .null:
            return "null"
        }
    }
}
