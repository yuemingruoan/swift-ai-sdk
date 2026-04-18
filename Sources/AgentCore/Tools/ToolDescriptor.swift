import Foundation

public enum ToolExecutionKind: String, Codable, Equatable, Sendable {
    case local
    case remote
}

public indirect enum ToolInputSchema: Codable, Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case array(items: ToolInputSchema)
    case object(properties: [String: ToolInputSchema] = [:], required: [String] = [])
}

public struct ToolDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let executionKind: ToolExecutionKind
    public let remoteTransportID: String?
    public let inputSchema: ToolInputSchema?

    public init(
        name: String,
        executionKind: ToolExecutionKind,
        remoteTransportID: String? = nil,
        inputSchema: ToolInputSchema? = nil
    ) {
        self.name = name
        self.executionKind = executionKind
        self.remoteTransportID = remoteTransportID
        self.inputSchema = inputSchema
    }

    public static func local<Input: Codable & Sendable, Output: Codable & Sendable>(
        name: String,
        input: Input.Type,
        output: Output.Type
    ) -> Self {
        ToolDescriptor(
            name: name,
            executionKind: .local
        )
    }

    public static func remote(
        name: String,
        transport: String,
        inputSchema: ToolInputSchema
    ) -> Self {
        ToolDescriptor(
            name: name,
            executionKind: .remote,
            remoteTransportID: transport,
            inputSchema: inputSchema
        )
    }
}
