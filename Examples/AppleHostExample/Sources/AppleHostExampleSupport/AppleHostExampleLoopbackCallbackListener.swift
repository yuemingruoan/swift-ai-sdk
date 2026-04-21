import AppKit
import Foundation
import Network

public enum AppleHostExampleLoopbackCallbackListenerError: Error, Equatable {
    case failedToOpenBrowser
    case invalidCallbackPort
    case cancelled
}

struct AppleHostExampleLoopbackHTTPRequestParser {
    static func callbackURL(from data: Data, host: String, port: UInt16) -> URL? {
        guard let request = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }

        return URL(string: "http://\(host):\(port)\(parts[1])")
    }
}

public actor AppleHostExampleLoopbackCallbackListener {
    private let callbackMatcher: AppleHostExampleEmbeddedAuthURLMatcher
    private let callbackHost: String
    private let callbackPort: UInt16
    private let queue = DispatchQueue(label: "AppleHostExampleLoopbackCallbackListener")

    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var bufferedCallbackURL: URL?

    public init(callbackURL: URL) {
        callbackMatcher = AppleHostExampleEmbeddedAuthURLMatcher(callbackURL: callbackURL)
        callbackHost = callbackURL.host ?? "localhost"
        callbackPort = UInt16(callbackURL.port ?? Int(AppleHostExampleDefaults.callbackPort))
    }

    public func start() async throws {
        if listener != nil {
            return
        }

        guard let nwPort = NWEndpoint.Port(rawValue: callbackPort) else {
            throw AppleHostExampleLoopbackCallbackListenerError.invalidCallbackPort
        }

        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleListenerState(state)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        self.listener = listener
        listener.start(queue: queue)

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    public func waitForCallback() async throws -> URL {
        if let bufferedCallbackURL {
            self.bufferedCallbackURL = nil
            return bufferedCallbackURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    public func cancel() {
        listener?.cancel()
        listener = nil

        startContinuation?.resume(throwing: AppleHostExampleLoopbackCallbackListenerError.cancelled)
        startContinuation = nil

        callbackContinuation?.resume(throwing: AppleHostExampleLoopbackCallbackListenerError.cancelled)
        callbackContinuation = nil
    }

    @MainActor
    public static func openBrowser(at authorizationURL: URL) -> Bool {
        NSWorkspace.shared.open(authorizationURL)
    }
}

private extension AppleHostExampleLoopbackCallbackListener {
    func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            callbackContinuation?.resume(throwing: error)
            callbackContinuation = nil
            listener = nil
        case .cancelled:
            listener = nil
            startContinuation?.resume(throwing: AppleHostExampleLoopbackCallbackListenerError.cancelled)
            startContinuation = nil
        default:
            break
        }
    }

    func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task {
                await self?.handleReceivedData(data, from: connection)
            }
        }
    }

    func handleReceivedData(_ data: Data?, from connection: NWConnection) {
        guard let data,
              let url = AppleHostExampleLoopbackHTTPRequestParser.callbackURL(
                  from: data,
                  host: callbackHost,
                  port: callbackPort
              )
        else {
            sendResponse(status: "400 Bad Request", body: "Invalid callback request.", over: connection)
            return
        }

        guard callbackMatcher.matches(url) else {
            sendResponse(status: "404 Not Found", body: "Not a callback URL.", over: connection)
            return
        }

        sendResponse(status: "200 OK", body: "Callback captured. You can return to the app.", over: connection)
        listener?.cancel()
        listener = nil

        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(returning: url)
        } else {
            bufferedCallbackURL = url
        }
    }

    func sendResponse(status: String, body: String, over connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
