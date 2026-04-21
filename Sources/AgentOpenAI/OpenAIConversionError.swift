import Foundation

/// OpenAI-specific conversion errors raised while mapping between SDK models and provider wire shapes.
///
/// These stay separate from the SDK-facing `Agent*Error` runtime taxonomy because they describe
/// deterministic model-shaping failures rather than transport or execution failures.
public enum OpenAIConversionError: Error, Equatable, Sendable {
    case unsupportedMessageRole(String)
    case unsupportedResponseMessageRole(String)
    case invalidFunctionCallArguments(String)
}
