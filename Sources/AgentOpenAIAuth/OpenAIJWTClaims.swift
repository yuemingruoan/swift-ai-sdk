import Foundation

struct OpenAIJWTClaims: Sendable {
    var expiresAt: Date?
    var chatGPTAccountID: String?
    var chatGPTPlanType: String?
}

func parseOpenAIJWTClaims(_ jwt: String) -> OpenAIJWTClaims? {
    let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else {
        return nil
    }

    guard let payload = decodeBase64URL(String(parts[1])),
          let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    else {
        return nil
    }

    let expiration = (object["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    let authClaims = object["https://api.openai.com/auth"] as? [String: Any]

    return OpenAIJWTClaims(
        expiresAt: expiration,
        chatGPTAccountID: authClaims?["chatgpt_account_id"] as? String,
        chatGPTPlanType: authClaims?["chatgpt_plan_type"] as? String
    )
}

private func decodeBase64URL(_ string: String) -> Data? {
    var normalized = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    let remainder = normalized.count % 4
    if remainder != 0 {
        normalized += String(repeating: "=", count: 4 - remainder)
    }

    return Data(base64Encoded: normalized)
}
