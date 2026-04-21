import Foundation
import Testing
@testable import AppleHostExampleSupport

struct AppleHostExampleLoopbackCallbackListenerTests {
    @Test func parses_callback_url_from_http_request() {
        let request = """
        GET /auth/callback?code=test-code&state=test-state HTTP/1.1\r
        Host: localhost:1455\r
        Connection: keep-alive\r
        \r
        """
        let url = AppleHostExampleLoopbackHTTPRequestParser.callbackURL(
            from: Data(request.utf8),
            host: "localhost",
            port: 1455
        )

        #expect(url?.absoluteString == "http://localhost:1455/auth/callback?code=test-code&state=test-state")
    }

    @Test func returns_nil_for_invalid_http_request() {
        let url = AppleHostExampleLoopbackHTTPRequestParser.callbackURL(
            from: Data("not http".utf8),
            host: "localhost",
            port: 1455
        )

        #expect(url == nil)
    }
}
