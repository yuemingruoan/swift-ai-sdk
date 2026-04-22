import Testing
@testable import AgentCore

struct AgentMiddlewareStackTests {
    @Test func empty_stack_preserves_request_response_and_messages() async throws {
        let stack = AgentMiddlewareStack()

        let request = AgentModelRequestContext(
            provider: .openAI,
            model: "gpt-5.4",
            input: [.userText("hello")],
            tools: [],
            stream: true
        )
        let response = AgentModelResponseContext(
            provider: .openAI,
            model: "gpt-5.4",
            messages: [.init(role: .assistant, parts: [.text("done")])],
            toolCalls: []
        )

        let prepared = try await stack.prepareModelRequest(request)
        let processed = try await stack.processModelResponse(response)
        let redacted = try await stack.redactMessages(
            response.messages,
            reason: .messagesCompleted
        )

        #expect(prepared == request)
        #expect(processed == response)
        #expect(redacted == response.messages)
    }

    @Test func request_and_response_middleware_run_in_registration_order() async throws {
        let recorder = MiddlewareRecorder()
        let stack = AgentMiddlewareStack(
            modelRequest: [
                RecordingRequestMiddleware(label: "request-1", recorder: recorder),
                RecordingRequestMiddleware(label: "request-2", recorder: recorder),
            ],
            modelResponse: [
                RecordingResponseMiddleware(label: "response-1", recorder: recorder),
                RecordingResponseMiddleware(label: "response-2", recorder: recorder),
            ]
        )

        let prepared = try await stack.prepareModelRequest(
            AgentModelRequestContext(
                provider: .anthropic,
                model: "claude-sonnet-4-20250514",
                input: [.userText("hello")],
                tools: [],
                stream: true
            )
        )
        let processed = try await stack.processModelResponse(
            AgentModelResponseContext(
                provider: .anthropic,
                model: "claude-sonnet-4-20250514",
                messages: [.init(role: .assistant, parts: [.text("done")])],
                toolCalls: []
            )
        )

        #expect(prepared.metadata["request-1"] == "seen")
        #expect(prepared.metadata["request-2"] == "seen")
        #expect(processed.metadata["response-1"] == "seen")
        #expect(processed.metadata["response-2"] == "seen")
        #expect(await recorder.events == [
            "request:request-1",
            "request:request-2",
            "response:response-1",
            "response:response-2",
        ])
    }

    @Test func authorization_stack_returns_deny_when_any_middleware_denies() async throws {
        let recorder = MiddlewareRecorder()
        let stack = AgentMiddlewareStack(
            toolAuthorization: [
                AllowAllToolAuthorizationMiddleware(recorder: recorder),
                DenyToolAuthorizationMiddleware(reason: "blocked", recorder: recorder),
            ]
        )
        let context = AgentToolInvocationContext(
            descriptor: .remote(
                name: "lookup_weather",
                transport: "weather-api",
                inputSchema: .object(required: ["city"])
            ),
            invocation: .init(toolName: "lookup_weather", arguments: ["city": .string("Paris")])
        )

        let decision = try await stack.authorizeToolInvocation(context)

        #expect(decision == .deny(reason: "blocked"))
        #expect(await recorder.events == [
            "authorize:allow:lookup_weather",
            "authorize:deny:lookup_weather",
        ])
    }

    @Test func redaction_middleware_redacts_completed_messages_without_touching_text_deltas() async throws {
        let recorder = MiddlewareRecorder()
        let stack = AgentMiddlewareStack(
            messageRedaction: [
                RedactingMessageMiddleware(recorder: recorder),
            ]
        )

        let original = [
            AgentMessage(role: .assistant, parts: [.text("secret")]),
        ]
        let redacted = try await stack.redactMessages(original, reason: .messagesCompleted)

        #expect(redacted == [
            AgentMessage(role: .assistant, parts: [.text("[redacted]")]),
        ])
        #expect(await recorder.events == [
            "redact:messagesCompleted",
        ])
    }

    @Test func audit_middleware_receives_structured_events() async throws {
        let recorder = MiddlewareRecorder()
        let stack = AgentMiddlewareStack(
            audit: [
                RecordingAuditMiddleware(recorder: recorder),
            ]
        )

        await stack.recordAuditEvent(
            .toolDenied(
                .init(
                    context: .init(
                        descriptor: .local(
                            name: "dangerous",
                            input: String.self,
                            output: String.self
                        ),
                        invocation: .init(toolName: "dangerous", input: .string("rm -rf /"))
                    ),
                    reason: "blocked"
                )
            )
        )

        #expect(await recorder.events == [
            "audit:toolDenied:dangerous",
        ])
    }
}

private actor MiddlewareRecorder {
    private var storedEvents: [String] = []

    var events: [String] {
        storedEvents
    }

    func append(_ event: String) {
        storedEvents.append(event)
    }
}

private struct RecordingRequestMiddleware: AgentModelRequestMiddleware {
    let label: String
    let recorder: MiddlewareRecorder

    func prepare(_ context: AgentModelRequestContext) async throws -> AgentModelRequestContext {
        await recorder.append("request:\(label)")
        var context = context
        context.metadata[label] = "seen"
        return context
    }
}

private struct RecordingResponseMiddleware: AgentModelResponseMiddleware {
    let label: String
    let recorder: MiddlewareRecorder

    func process(_ context: AgentModelResponseContext) async throws -> AgentModelResponseContext {
        await recorder.append("response:\(label)")
        var context = context
        context.metadata[label] = "seen"
        return context
    }
}

private struct AllowAllToolAuthorizationMiddleware: AgentToolAuthorizationMiddleware {
    let recorder: MiddlewareRecorder

    func authorize(_ context: AgentToolInvocationContext) async throws -> AgentToolAuthorizationDecision {
        await recorder.append("authorize:allow:\(context.descriptor.name)")
        return .allow
    }
}

private struct DenyToolAuthorizationMiddleware: AgentToolAuthorizationMiddleware {
    let reason: String
    let recorder: MiddlewareRecorder

    func authorize(_ context: AgentToolInvocationContext) async throws -> AgentToolAuthorizationDecision {
        await recorder.append("authorize:deny:\(context.descriptor.name)")
        return .deny(reason: reason)
    }
}

private struct RedactingMessageMiddleware: AgentMessageRedactionMiddleware {
    let recorder: MiddlewareRecorder

    func redact(
        _ messages: [AgentMessage],
        reason: AgentMessageRedactionReason
    ) async throws -> [AgentMessage] {
        await recorder.append("redact:\(reason.rawValue)")
        return messages.map { message in
            AgentMessage(
                role: message.role,
                parts: message.parts.map { part in
                    switch part {
                    case .text:
                        return .text("[redacted]")
                    case .image:
                        return part
                    }
                }
            )
        }
    }
}

private struct RecordingAuditMiddleware: AgentAuditMiddleware {
    let recorder: MiddlewareRecorder

    func record(_ event: AgentAuditEvent) async {
        switch event {
        case .toolDenied(let event):
            await recorder.append("audit:toolDenied:\(event.context.descriptor.name)")
        default:
            await recorder.append("audit:other")
        }
    }
}
