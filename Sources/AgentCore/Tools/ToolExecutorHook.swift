import Foundation

public struct ToolExecutorInvocationFailure: Equatable, Sendable {
    public let errorType: String
    public let message: String

    public init(errorType: String, message: String) {
        self.errorType = errorType
        self.message = message
    }

    public init(error: any Error) {
        self.init(
            errorType: String(describing: type(of: error)),
            message: ToolExecutorInvocationFailure.message(for: error)
        )
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}

public protocol ToolExecutorHook: Sendable {
    func willInvoke(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation
    ) async

    func didInvoke(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation,
        result: ToolResult
    ) async

    func didFail(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation,
        failure: ToolExecutorInvocationFailure
    ) async
}
