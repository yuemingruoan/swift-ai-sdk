import Foundation

public struct ToolResult: Codable, Equatable, Sendable {
    public let payload: ToolValue

    public init(payload: ToolValue) {
        self.payload = payload
    }
}
