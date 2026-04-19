import Foundation

public enum OpenAIConversionError: Error, Equatable, Sendable {
    case unsupportedMessageRole(String)
    case unsupportedResponseMessageRole(String)
    case invalidFunctionCallArguments(String)
}
