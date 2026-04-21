import AppleHostExampleSupport
import SwiftUI
import WebKit

struct AppleHostExampleEmbeddedAuthSheet: View {
    let authorizationURL: URL
    let strings: AppleHostExampleStrings
    let onCallback: (URL) -> Void
    let onCancel: () -> Void
    let onFailure: (Error) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.signIn)
                        .font(.title2.weight(.semibold))
                    Text(AppleHostExampleDefaults.redirectURLString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(strings.signOut, action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.thinMaterial)

            Divider()

            AppleHostExampleEmbeddedAuthWebView(
                authorizationURL: authorizationURL,
                callbackURL: AppleHostExampleDefaults.redirectURL,
                onCallback: onCallback,
                onFailure: onFailure
            )
        }
        .frame(minWidth: 980, minHeight: 720)
    }
}

private struct AppleHostExampleEmbeddedAuthWebView: NSViewRepresentable {
    let authorizationURL: URL
    let callbackURL: URL
    let onCallback: (URL) -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            matcher: AppleHostExampleEmbeddedAuthURLMatcher(callbackURL: callbackURL),
            onCallback: onCallback,
            onFailure: onFailure
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: authorizationURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        if webView.url == nil {
            webView.load(URLRequest(url: authorizationURL))
        }
    }
}

private final class Coordinator: NSObject, WKNavigationDelegate {
    private let matcher: AppleHostExampleEmbeddedAuthURLMatcher
    private let onCallback: (URL) -> Void
    private let onFailure: (Error) -> Void
    private var handledCallback = false

    init(
        matcher: AppleHostExampleEmbeddedAuthURLMatcher,
        onCallback: @escaping (URL) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.matcher = matcher
        self.onCallback = onCallback
        self.onFailure = onFailure
    }

    @MainActor
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        guard matcher.matches(url) else {
            decisionHandler(.allow)
            return
        }

        handledCallback = true
        onCallback(url)
        decisionHandler(.cancel)
        webView.stopLoading()
    }

    func webView(
        _: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        report(error)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        report(error)
    }

    private func report(_ error: Error) {
        guard handledCallback == false else {
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        onFailure(error)
    }
}
