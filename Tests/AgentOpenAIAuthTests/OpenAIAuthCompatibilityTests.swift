import AgentOpenAIAuth
import AgentOpenAI
import AgentCore
import Foundation
import Testing

struct OpenAIAuthCompatibilityTests {
    @Test func auth_module_exposes_public_marker_type() {
        _ = AgentOpenAIAuthModule.self
    }

    @Test func external_token_provider_returns_configured_tokens() async throws {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = OpenAIAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            chatGPTAccountID: "acc_123",
            chatGPTPlanType: "plus",
            expiresAt: expiresAt
        )
        let provider = OpenAIExternalTokenProvider(tokens: expected)

        let actual = try await provider.currentTokens()

        #expect(actual == expected)
    }

    @Test func external_token_provider_reports_refresh_unsupported() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(accessToken: "access-token")
        )

        await #expect(throws: AgentAuthError.refreshUnsupported) {
            _ = try await provider.refreshTokens(reason: .unauthorized)
        }
    }

    @Test func auth_tokens_preserve_optional_chatgpt_metadata() {
        let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        let tokens = OpenAIAuthTokens(
            accessToken: "access-token",
            refreshToken: nil,
            chatGPTAccountID: "acc_456",
            chatGPTPlanType: "pro",
            expiresAt: expiresAt
        )

        #expect(tokens.accessToken == "access-token")
        #expect(tokens.refreshToken == nil)
        #expect(tokens.chatGPTAccountID == "acc_456")
        #expect(tokens.chatGPTPlanType == "pro")
        #expect(tokens.expiresAt == expiresAt)
    }

    @Test func compatibility_profiles_expose_expected_follow_up_defaults() {
        #expect(OpenAICompatibilityProfile.openAI.responsesFollowUpStrategy == .previousResponseID)
        #expect(OpenAICompatibilityProfile.newAPI.responsesFollowUpStrategy == .replayInput)
        #expect(OpenAICompatibilityProfile.sub2api.responsesFollowUpStrategy == .replayInput)
        #expect(OpenAICompatibilityProfile.chatGPTCodexOAuth.responsesFollowUpStrategy == .replayInput)
    }

    @Test func chatgpt_codex_transform_normalizes_store_stream_and_instructions() throws {
        let original = try OpenAIResponseRequest(
            model: "gpt-5.4",
            messages: [.userText("hello")],
            previousResponseID: "resp_123",
            stream: false,
            tools: [],
            toolChoice: .auto
        )
        var request = original
        request.store = true
        request.instructions = nil
        request.promptCacheKey = "prompt-cache-key"

        let transformed = OpenAIChatGPTRequestTransform(profile: .chatGPTCodexOAuth)
            .transform(request)

        #expect(transformed.model == "gpt-5.4")
        #expect(transformed.store == false)
        #expect(transformed.stream == true)
        #expect(transformed.instructions == "")
        #expect(transformed.previousResponseID == nil)
        #expect(transformed.promptCacheKey == "prompt-cache-key")
    }

    @Test func openai_profile_transform_preserves_previous_response_id() throws {
        var request = try OpenAIResponseRequest(
            model: "gpt-5.4",
            messages: [.userText("hello")],
            previousResponseID: "resp_123",
            stream: false
        )
        request.store = nil
        request.instructions = "follow policy"

        let transformed = OpenAIChatGPTRequestTransform(profile: .openAI).transform(request)

        #expect(transformed.previousResponseID == "resp_123")
        #expect(transformed.instructions == "follow policy")
        #expect(transformed.store == nil)
        #expect(transformed.stream == false)
    }

    @Test func authenticated_request_builder_sets_chatgpt_codex_headers() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123",
                chatGPTPlanType: "plus"
            )
        )
        let builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: .init(),
            tokenProvider: provider
        )

        let request = try await builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == "acc_123")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == "responses=experimental")
        #expect(request.value(forHTTPHeaderField: "originator") == "codex_cli_rs")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["store"] as? Bool == false)
        #expect(json["stream"] as? Bool == true)
        #expect(json["instructions"] as? String == "")
        #expect(json["previous_response_id"] == nil)
    }

    @Test func authenticated_streaming_request_builder_sets_event_stream_accept_header() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: .init(),
            tokenProvider: provider
        )

        let request = try await builder.makeStreamingURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test func authenticated_request_builder_applies_shared_transport_configuration() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: .init(
                userAgent: "swift-ai-sdk-config/1.0",
                transport: .init(
                    timeoutInterval: 9,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-transport/2.0",
                    requestID: "req_auth_123"
                )
            ),
            tokenProvider: provider
        )

        let request = try await builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(request.timeoutInterval == 9)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-transport/2.0")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_auth_123")
    }

    @Test func authenticated_websocket_request_builder_sets_chatgpt_codex_headers() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let builder = OpenAIAuthenticatedResponsesWebSocketRequestBuilder(
            configuration: .init(),
            tokenProvider: provider
        )

        let request = try await builder.makeURLRequest()

        #expect(request.url?.absoluteString == "wss://chatgpt.com/backend-api/codex/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == "acc_123")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == "responses_websockets=2026-02-06")
        #expect(request.value(forHTTPHeaderField: "originator") == nil)
    }

    @Test func authenticated_websocket_request_builder_applies_shared_transport_configuration() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let builder = OpenAIAuthenticatedResponsesWebSocketRequestBuilder(
            configuration: .init(
                transport: .init(
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-transport/2.0",
                    requestID: "req_ws_123"
                )
            ),
            tokenProvider: provider
        )

        let request = try await builder.makeURLRequest(clientRequestID: "client_req_123")

        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-transport/2.0")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_ws_123")
        #expect(request.value(forHTTPHeaderField: "x-client-request-id") == "client_req_123")
    }

    @Test func authenticated_request_builder_uses_third_party_base_url_without_chatgpt_headers() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(accessToken: "access-token")
        )
        let builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: .init(
                baseURL: URL(string: "https://nowcoding.ai/v1")!,
                compatibilityProfile: .newAPI
            ),
            tokenProvider: provider
        )

        let request = try await builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(request.url?.absoluteString == "https://nowcoding.ai/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == nil)
        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == nil)
        #expect(request.value(forHTTPHeaderField: "originator") == nil)
    }

    @Test func authenticated_transport_retries_once_after_401_with_refreshed_token() async throws {
        let session = AuthStubHTTPSession(
            responses: [
                .init(statusCode: 401, body: Data()),
                .init(
                    statusCode: 200,
                    body: """
                    {"id":"resp_123","status":"completed","output":[]}
                    """.data(using: .utf8)!
                ),
            ]
        )
        let provider = RefreshingTokenProvider(
            initial: OpenAIAuthTokens(
                accessToken: "expired-token",
                chatGPTAccountID: "acc_123"
            ),
            refreshed: OpenAIAuthTokens(
                accessToken: "fresh-token",
                refreshToken: "refresh-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let transport = URLSessionOpenAIAuthenticatedResponsesTransport(
            configuration: .init(),
            tokenProvider: provider,
            session: session
        )

        let response = try await transport.createResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(response.id == "resp_123")
        let requests = await session.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer expired-token")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token")
        #expect(await provider.refreshCallCount == 1)
    }

    @Test func authenticated_transport_retries_retryable_status_codes_using_shared_retry_policy() async throws {
        let session = AuthStubHTTPSession(
            responses: [
                .init(statusCode: 503, body: Data()),
                .init(
                    statusCode: 200,
                    body: """
                    {"id":"resp_retry","status":"completed","output":[]}
                    """.data(using: .utf8)!
                ),
            ]
        )
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let transport = URLSessionOpenAIAuthenticatedResponsesTransport(
            configuration: .init(
                transport: .init(
                    retryPolicy: .init(
                        maxAttempts: 2,
                        backoff: .none,
                        retryableStatusCodes: [503]
                    )
                )
            ),
            tokenProvider: provider,
            session: session
        )

        let response = try await transport.createResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(response.id == "resp_retry")
        let requests = await session.recordedRequests
        #expect(requests.count == 2)
    }

    @Test func authenticated_transport_passes_shared_transport_configuration_to_injected_session() async throws {
        let session = AuthStubHTTPSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: """
                    {"id":"resp_transport_config","status":"completed","output":[]}
                    """.data(using: .utf8)!
                ),
            ]
        )
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let transport = URLSessionOpenAIAuthenticatedResponsesTransport(
            configuration: .init(
                userAgent: "swift-ai-sdk-auth-config/1.0",
                acceptLanguage: "en-US",
                transport: .init(
                    timeoutInterval: 9,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-auth-transport/2.0",
                    requestID: "req_auth_transport_123"
                )
            ),
            tokenProvider: provider,
            session: session
        )

        let response = try await transport.createResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(response.id == "resp_transport_config")
        let requests = await session.recordedRequests
        #expect(requests.count == 1)
        let request = requests[0]
        #expect(request.timeoutInterval == 9)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-auth-transport/2.0")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_auth_transport_123")
    }

    @Test func authenticated_streaming_transport_passes_shared_transport_configuration_to_injected_session() async throws {
        let session = AuthStubLineStreamingSession(
            lines: [
                "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_auth_stream\",\"status\":\"completed\",\"output\":[]}}",
                "",
            ]
        )
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let transport = URLSessionOpenAIAuthenticatedResponsesStreamingTransport(
            configuration: .init(
                userAgent: "swift-ai-sdk-auth-config/1.0",
                acceptLanguage: "en-US",
                transport: .init(
                    timeoutInterval: 11,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-auth-stream/2.0",
                    requestID: "req_auth_stream_123"
                )
            ),
            tokenProvider: provider,
            session: session
        )

        var events: [OpenAIResponseStreamEvent] = []
        for try await event in transport.streamResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        ) {
            events.append(event)
        }

        #expect(events == [
            .responseCompleted(
                OpenAIResponse(id: "resp_auth_stream", status: .completed, output: [])
            ),
        ])
        let requests = await session.recordedRequests
        #expect(requests.count == 1)
        let request = requests[0]
        #expect(request.timeoutInterval == 11)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-auth-stream/2.0")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_auth_stream_123")
    }

    @Test func authenticated_transport_surfaces_refresh_unsupported_after_401() async throws {
        let session = AuthStubHTTPSession(
            responses: [
                .init(statusCode: 401, body: Data()),
            ]
        )
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: "expired-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let transport = URLSessionOpenAIAuthenticatedResponsesTransport(
            configuration: .init(),
            tokenProvider: provider,
            session: session
        )

        await #expect(throws: AgentAuthError.refreshUnsupported) {
            _ = try await transport.createResponse(
                OpenAIResponseRequest(
                    model: "gpt-5.4",
                    input: [.message(.init(role: .user, content: [.inputText("hello")]))]
                )
            )
        }
    }

    @Test func managed_token_provider_reads_tokens_from_store() async throws {
        let store = InMemoryOpenAITokenStore(
            tokens: OpenAIAuthTokens(
                accessToken: "stored-token",
                refreshToken: "refresh-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let provider = OpenAIManagedTokenProvider(
            store: store,
            refresher: StaticTokenRefresher()
        )

        let tokens = try await provider.currentTokens()

        #expect(tokens.accessToken == "stored-token")
        #expect(await store.saveCallCount == 0)
    }

    @Test func managed_token_provider_refreshes_expired_tokens_on_current_tokens() async throws {
        let expired = Date(timeIntervalSince1970: 1_000)
        let refreshed = Date(timeIntervalSince1970: 2_000)
        let store = InMemoryOpenAITokenStore(
            tokens: OpenAIAuthTokens(
                accessToken: "expired-token",
                refreshToken: "refresh-token",
                chatGPTAccountID: "acc_123",
                expiresAt: expired
            )
        )
        let refresher = StaticTokenRefresher(
            refreshedTokens: OpenAIAuthTokens(
                accessToken: "fresh-token",
                refreshToken: "refresh-token-2",
                chatGPTAccountID: "acc_123",
                expiresAt: refreshed
            )
        )
        let provider = OpenAIManagedTokenProvider(
            store: store,
            refresher: refresher,
            clock: { Date(timeIntervalSince1970: 1_500) }
        )

        let tokens = try await provider.currentTokens()

        #expect(tokens.accessToken == "fresh-token")
        #expect(await refresher.refreshCallCount == 1)
        let persisted = try #require(await store.currentTokens)
        #expect(persisted.accessToken == "fresh-token")
        #expect(await store.saveCallCount == 1)
    }

    @Test func managed_token_provider_does_not_refresh_fresh_tokens() async throws {
        let future = Date(timeIntervalSince1970: 9_999_999_999)
        let store = InMemoryOpenAITokenStore(
            tokens: OpenAIAuthTokens(
                accessToken: "fresh-token",
                refreshToken: "refresh-token",
                chatGPTAccountID: "acc_123",
                expiresAt: future
            )
        )
        let refresher = StaticTokenRefresher()
        let provider = OpenAIManagedTokenProvider(
            store: store,
            refresher: refresher,
            clock: { Date(timeIntervalSince1970: 1_500) }
        )

        let tokens = try await provider.currentTokens()

        #expect(tokens.accessToken == "fresh-token")
        #expect(await refresher.refreshCallCount == 0)
        #expect(await store.saveCallCount == 0)
    }

    @Test func managed_token_provider_refresh_tokens_persists_refreshed_value() async throws {
        let store = InMemoryOpenAITokenStore(
            tokens: OpenAIAuthTokens(
                accessToken: "old-token",
                refreshToken: "refresh-token",
                chatGPTAccountID: "acc_123"
            )
        )
        let refresher = StaticTokenRefresher(
            refreshedTokens: OpenAIAuthTokens(
                accessToken: "new-token",
                refreshToken: "refresh-token-2",
                chatGPTAccountID: "acc_123"
            )
        )
        let provider = OpenAIManagedTokenProvider(
            store: store,
            refresher: refresher
        )

        let tokens = try await provider.refreshTokens(reason: .unauthorized)

        #expect(tokens.accessToken == "new-token")
        #expect(await refresher.refreshCallCount == 1)
        let persisted = try #require(await store.currentTokens)
        #expect(persisted.accessToken == "new-token")
        #expect(await store.saveCallCount == 1)
    }

    @Test func managed_token_provider_throws_when_store_is_empty() async throws {
        let store = InMemoryOpenAITokenStore(tokens: nil)
        let provider = OpenAIManagedTokenProvider(
            store: store,
            refresher: StaticTokenRefresher()
        )

        await #expect(throws: AgentAuthError.missingCredentials("tokens")) {
            _ = try await provider.currentTokens()
        }
    }

    @Test func oauth_flow_protocol_can_be_adopted_by_custom_components() async throws {
        let flow = StubOAuthFlow()

        let started = try await flow.startAuthorization(method: .deviceCode)
        let completed = try await flow.completeAuthorization(sessionID: started.sessionID)

        #expect(started.method == .deviceCode)
        #expect(started.verificationURL?.absoluteString == "https://auth.openai.com/codex/device")
        #expect(completed.chatGPTAccountID == "acc_123")
    }

    @Test func chatgpt_device_code_flow_requests_user_code_session() async throws {
        let session = OAuthStubHTTPSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: """
                    {"device_auth_id":"device-auth-123","user_code":"ABCD-1234","interval":"5"}
                    """.data(using: .utf8)!
                )
            ]
        )
        let flow = OpenAIChatGPTDeviceCodeFlow(session: session)

        let started = try await flow.startAuthorization(method: .deviceCode)

        #expect(started.method == .deviceCode)
        #expect(started.sessionID == "device-auth-123")
        #expect(started.authorizationURL == nil)
        #expect(started.verificationURL?.absoluteString == "https://auth.openai.com/codex/device")
        #expect(started.userCode == "ABCD-1234")

        let requests = await session.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/usercode")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(requests[0].httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["client_id"] as? String == OpenAIChatGPTOAuthConfiguration.codexCLIClientID)
    }

    @Test func chatgpt_device_code_flow_polls_and_exchanges_tokens() async throws {
        let accessToken = makeJWT(
            payload: [
                "exp": 1_900_000_000,
            ]
        )
        let idToken = makeJWT(
            payload: [
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": "acc_123",
                    "chatgpt_plan_type": "plus",
                ]
            ]
        )
        let session = OAuthStubHTTPSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: """
                    {"device_auth_id":"device-auth-123","user_code":"ABCD-1234","interval":"5"}
                    """.data(using: .utf8)!
                ),
                .init(statusCode: 403, body: Data()),
                .init(
                    statusCode: 200,
                    body: """
                    {"authorization_code":"auth-code-123","code_challenge":"challenge-123","code_verifier":"verifier-123"}
                    """.data(using: .utf8)!
                ),
                .init(
                    statusCode: 200,
                    body: """
                    {"access_token":"\(accessToken)","refresh_token":"refresh-token-2","id_token":"\(idToken)","expires_in":3600}
                    """.data(using: .utf8)!
                ),
            ]
        )
        let flow = OpenAIChatGPTDeviceCodeFlow(
            session: session,
            sleeper: { _ in },
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let started = try await flow.startAuthorization(method: .deviceCode)
        let tokens = try await flow.completeAuthorization(sessionID: started.sessionID)

        #expect(tokens.accessToken == accessToken)
        #expect(tokens.refreshToken == "refresh-token-2")
        #expect(tokens.chatGPTAccountID == "acc_123")
        #expect(tokens.chatGPTPlanType == "plus")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))

        let requests = await session.recordedRequests
        #expect(requests.count == 4)
        #expect(requests[1].url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/token")
        #expect(requests[2].url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/token")
        #expect(requests[3].url?.absoluteString == "https://auth.openai.com/oauth/token")
        let tokenBody = String(data: try #require(requests[3].httpBody), encoding: .utf8)
        #expect(tokenBody?.contains("grant_type=authorization_code") == true)
        #expect(tokenBody?.contains("client_id=\(OpenAIChatGPTOAuthConfiguration.codexCLIClientID)") == true)
        #expect(tokenBody?.contains("code=auth-code-123") == true)
        #expect(tokenBody?.contains("code_verifier=verifier-123") == true)
    }

    @Test func chatgpt_token_refresher_refreshes_using_refresh_token() async throws {
        let refreshedAccessToken = makeJWT(
            payload: [
                "exp": 1_950_000_000,
            ]
        )
        let refreshedIDToken = makeJWT(
            payload: [
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": "acc_456",
                    "chatgpt_plan_type": "pro",
                ]
            ]
        )
        let session = OAuthStubHTTPSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: """
                    {"access_token":"\(refreshedAccessToken)","refresh_token":"refresh-token-2","id_token":"\(refreshedIDToken)"}
                    """.data(using: .utf8)!
                )
            ]
        )
        let refresher = OpenAIChatGPTTokenRefresher(
            session: session,
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let refreshed = try await refresher.refreshTokens(
            current: OpenAIAuthTokens(
                accessToken: "stale-token",
                refreshToken: "refresh-token-1",
                chatGPTAccountID: "acc_123",
                chatGPTPlanType: "plus"
            ),
            reason: .unauthorized
        )

        #expect(refreshed.accessToken == refreshedAccessToken)
        #expect(refreshed.refreshToken == "refresh-token-2")
        #expect(refreshed.chatGPTAccountID == "acc_456")
        #expect(refreshed.chatGPTPlanType == "pro")
        #expect(refreshed.expiresAt == Date(timeIntervalSince1970: 1_950_000_000))

        let requests = await session.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(data: try #require(requests[0].httpBody), encoding: .utf8)
        #expect(body?.contains("grant_type=refresh_token") == true)
        #expect(body?.contains("client_id=\(OpenAIChatGPTOAuthConfiguration.codexCLIClientID)") == true)
        #expect(body?.contains("refresh_token=refresh-token-1") == true)
    }

    @Test func chatgpt_token_refresher_requires_refresh_token() async throws {
        let refresher = OpenAIChatGPTTokenRefresher()

        await #expect(throws: AgentAuthError.missingCredentials("refresh_token")) {
            _ = try await refresher.refreshTokens(
                current: OpenAIAuthTokens(accessToken: "access-token", refreshToken: nil),
                reason: .unauthorized
            )
        }
    }

    @Test func chatgpt_browser_flow_builds_authorization_url_with_pkce_state_and_workspace() async throws {
        let flow = OpenAIChatGPTBrowserFlow(
            configuration: .init(
                browserRedirectURL: URL(string: "http://localhost:1455/auth/callback")!,
                allowedWorkspaceID: "org_123"
            ),
            sessionFactory: {
                OpenAIChatGPTBrowserAuthorizationSessionData(
                    sessionID: "session-123",
                    state: "state-123",
                    codeVerifier: "verifier-123",
                    codeChallenge: "challenge-123"
                )
            }
        )

        let started = try await flow.startAuthorization(method: .browser)

        #expect(started.sessionID == "session-123")
        #expect(started.method == .browser)
        let authorizationURL = try #require(started.authorizationURL)
        let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        let queryItems: [String: String] = Dictionary(
            uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }
        )

        #expect(authorizationURL.absoluteString.hasPrefix("https://auth.openai.com/oauth/authorize?"))
        #expect(queryItems["response_type"] == "code")
        #expect(queryItems["client_id"] == OpenAIChatGPTOAuthConfiguration.codexCLIClientID)
        #expect(queryItems["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(
            queryItems["scope"] == "openid profile email offline_access api.connectors.read api.connectors.invoke"
        )
        #expect(queryItems["state"] == "state-123")
        #expect(queryItems["code_challenge"] == "challenge-123")
        #expect(queryItems["code_challenge_method"] == "S256")
        #expect(queryItems["id_token_add_organizations"] == "true")
        #expect(queryItems["codex_cli_simplified_flow"] == "true")
        #expect(queryItems["originator"] == OpenAIChatGPTOAuthConfiguration.codexCLIOriginator)
        #expect(queryItems["allowed_workspace_id"] == "org_123")
    }

    @Test func chatgpt_browser_authorization_session_generation_matches_codex_cli_style() {
        let session = OpenAIChatGPTBrowserAuthorizationSessionData.generate()

        #expect(session.sessionID.isEmpty == false)
        #expect(session.state.isEmpty == false)
        #expect(session.state.count == 43)
        #expect(session.state.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(session.codeVerifier.count == 86)
        #expect(
            session.codeVerifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        )
        #expect(session.codeChallenge.isEmpty == false)
    }

    @Test func chatgpt_browser_flow_exchanges_callback_code_for_tokens() async throws {
        let accessToken = makeJWT(
            payload: [
                "exp": 1_920_000_000,
            ]
        )
        let idToken = makeJWT(
            payload: [
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": "acc_browser",
                    "chatgpt_plan_type": "pro",
                ]
            ]
        )
        let session = OAuthStubHTTPSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: """
                    {"access_token":"\(accessToken)","refresh_token":"refresh-browser","id_token":"\(idToken)"}
                    """.data(using: .utf8)!
                )
            ]
        )
        let flow = OpenAIChatGPTBrowserFlow(
            configuration: .init(
                browserRedirectURL: URL(string: "http://localhost:1455/auth/callback")!
            ),
            session: session,
            sessionFactory: {
                OpenAIChatGPTBrowserAuthorizationSessionData(
                    sessionID: "browser-session",
                    state: "browser-state",
                    codeVerifier: "verifier-123",
                    codeChallenge: "challenge-123"
                )
            },
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let started = try await flow.startAuthorization(method: .browser)
        let tokens = try await flow.completeAuthorization(
            sessionID: started.sessionID,
            callbackURL: URL(string: "http://localhost:1455/auth/callback?code=abc123&state=browser-state")!
        )

        #expect(tokens.accessToken == accessToken)
        #expect(tokens.refreshToken == "refresh-browser")
        #expect(tokens.chatGPTAccountID == "acc_browser")
        #expect(tokens.chatGPTPlanType == "pro")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: 1_920_000_000))

        let requests = await session.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://auth.openai.com/oauth/token")
        let body = String(data: try #require(requests[0].httpBody), encoding: .utf8)
        #expect(body?.contains("grant_type=authorization_code") == true)
        #expect(body?.contains("code=abc123") == true)
        #expect(body?.contains("client_id=\(OpenAIChatGPTOAuthConfiguration.codexCLIClientID)") == true)
        #expect(body?.contains("redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback") == true)
        #expect(body?.contains("code_verifier=verifier-123") == true)
    }

    @Test func chatgpt_browser_flow_rejects_callback_state_mismatch() async throws {
        let flow = OpenAIChatGPTBrowserFlow(
            configuration: .init(
                browserRedirectURL: URL(string: "http://localhost:1455/auth/callback")!
            ),
            sessionFactory: {
                OpenAIChatGPTBrowserAuthorizationSessionData(
                    sessionID: "browser-session",
                    state: "expected-state",
                    codeVerifier: "verifier-123",
                    codeChallenge: "challenge-123"
                )
            }
        )

        let started = try await flow.startAuthorization(method: .browser)

        await #expect(throws: AgentAuthError.stateMismatch) {
            _ = try await flow.completeAuthorization(
                sessionID: started.sessionID,
                callbackURL: URL(string: "http://localhost:1455/auth/callback?code=abc123&state=wrong-state")!
            )
        }
    }
}

private struct AuthStubHTTPResponse {
    let statusCode: Int
    let body: Data
}

private struct OAuthStubHTTPResponse {
    let statusCode: Int
    let body: Data
}

private actor AuthStubHTTPSession: OpenAIHTTPSession {
    private let responses: [AuthStubHTTPResponse]
    private var index = 0
    private(set) var recordedRequests: [URLRequest] = []

    init(responses: [AuthStubHTTPResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        let response = responses[index]
        index += 1
        return (
            response.body,
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor OAuthStubHTTPSession: OpenAIHTTPSession {
    private let responses: [OAuthStubHTTPResponse]
    private var index = 0
    private(set) var recordedRequests: [URLRequest] = []

    init(responses: [OAuthStubHTTPResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        let response = responses[index]
        index += 1
        return (
            response.body,
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://auth.openai.com/oauth/token")!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor AuthStubLineStreamingSession: OpenAIHTTPLineStreamingSession {
    let lines: [String]
    private(set) var recordedRequests: [URLRequest] = []

    init(lines: [String]) {
        self.lines = lines
    }

    func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        recordedRequests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (
            AsyncThrowingStream { continuation in
                Task {
                    for line in lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                }
            },
            response
        )
    }
}

private actor RefreshingTokenProvider: OpenAITokenProvider {
    private var current: OpenAIAuthTokens
    private let refreshed: OpenAIAuthTokens
    private(set) var refreshCallCount = 0

    init(initial: OpenAIAuthTokens, refreshed: OpenAIAuthTokens) {
        self.current = initial
        self.refreshed = refreshed
    }

    func currentTokens() async throws -> OpenAIAuthTokens {
        current
    }

    func refreshTokens(reason _: OpenAITokenRefreshReason) async throws -> OpenAIAuthTokens {
        refreshCallCount += 1
        current = refreshed
        return refreshed
    }
}

private actor InMemoryOpenAITokenStore: OpenAITokenStore {
    private(set) var currentTokens: OpenAIAuthTokens?
    private(set) var saveCallCount = 0

    init(tokens: OpenAIAuthTokens?) {
        self.currentTokens = tokens
    }

    func loadTokens() async throws -> OpenAIAuthTokens? {
        currentTokens
    }

    func saveTokens(_ tokens: OpenAIAuthTokens) async throws {
        currentTokens = tokens
        saveCallCount += 1
    }

    func clearTokens() async throws {
        currentTokens = nil
    }
}

private actor StaticTokenRefresher: OpenAITokenRefresher {
    private let refreshedTokens: OpenAIAuthTokens?
    private(set) var refreshCallCount = 0

    init(refreshedTokens: OpenAIAuthTokens? = nil) {
        self.refreshedTokens = refreshedTokens
    }

    func refreshTokens(
        current: OpenAIAuthTokens,
        reason _: OpenAITokenRefreshReason
    ) async throws -> OpenAIAuthTokens {
        refreshCallCount += 1
        return refreshedTokens ?? current
    }
}

private struct StubOAuthFlow: OpenAIOAuthFlow {
    func startAuthorization(method: OpenAIOAuthMethod) async throws -> OpenAIOAuthSession {
        OpenAIOAuthSession(
            sessionID: "session-123",
            method: method,
            authorizationURL: nil,
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "ABCD-1234"
        )
    }

    func completeAuthorization(sessionID _: String) async throws -> OpenAIAuthTokens {
        OpenAIAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            chatGPTAccountID: "acc_123",
            chatGPTPlanType: "plus"
        )
    }
}

private func makeJWT(payload: [String: Any]) -> String {
    let headerData = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
    let payloadData = try! JSONSerialization.data(withJSONObject: payload)
    return [
        base64URLEncoded(headerData),
        base64URLEncoded(payloadData),
        "signature",
    ].joined(separator: ".")
}

private func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
    @Test func authenticated_request_builder_requires_chatgpt_account_id_for_codex_profile() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(accessToken: "access-token")
        )
        let builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: .init(),
            tokenProvider: provider
        )

        await #expect(throws: AgentAuthError.missingCredentials("chatgpt_account_id")) {
            _ = try await builder.makeURLRequest(
                for: OpenAIResponseRequest(
                    model: "gpt-5.4",
                    input: [.message(.init(role: .user, content: [.inputText("hello")]))]
                )
            )
        }
    }

    @Test func authenticated_websocket_request_builder_requires_chatgpt_account_id_for_codex_profile() async throws {
        let provider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(accessToken: "access-token")
        )
        let builder = OpenAIAuthenticatedResponsesWebSocketRequestBuilder(
            configuration: .init(),
            tokenProvider: provider
        )

        await #expect(throws: AgentAuthError.missingCredentials("chatgpt_account_id")) {
            _ = try await builder.makeURLRequest()
        }
    }
