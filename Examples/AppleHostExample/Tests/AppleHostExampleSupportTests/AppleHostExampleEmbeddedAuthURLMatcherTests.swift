import Foundation
import Testing
@testable import AppleHostExampleSupport

struct AppleHostExampleEmbeddedAuthURLMatcherTests {
    @Test func matches_localhost_callback_url() {
        let matcher = AppleHostExampleEmbeddedAuthURLMatcher(
            callbackURL: URL(string: "http://localhost:1455/auth/callback")!
        )
        let callbackURL = URL(
            string: "http://localhost:1455/auth/callback?code=test-code&state=test-state"
        )!

        #expect(matcher.matches(callbackURL))
    }

    @Test func rejects_different_host_when_callback_uses_localhost() {
        let matcher = AppleHostExampleEmbeddedAuthURLMatcher(
            callbackURL: URL(string: "http://localhost:1455/auth/callback")!
        )
        let callbackURL = URL(
            string: "http://127.0.0.1:1455/auth/callback?code=test-code&state=test-state"
        )!

        #expect(matcher.matches(callbackURL) == false)
    }

    @Test func rejects_non_callback_path() {
        let matcher = AppleHostExampleEmbeddedAuthURLMatcher(
            callbackURL: URL(string: "http://localhost:1455/auth/callback")!
        )
        let otherURL = URL(
            string: "https://auth.openai.com/oauth/authorize?state=test-state"
        )!

        #expect(matcher.matches(otherURL) == false)
    }
}
