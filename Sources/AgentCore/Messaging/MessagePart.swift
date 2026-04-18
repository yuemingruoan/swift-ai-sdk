import Foundation

public enum MessagePart: Codable, Equatable, Sendable {
    case text(String)
    case image(url: URL)
}

