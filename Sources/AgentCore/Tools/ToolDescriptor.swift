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
    public let description: String?
    public let executionKind: ToolExecutionKind
    public let remoteTransportID: String?
    public let inputSchema: ToolInputSchema?
    public let outputSchema: ToolInputSchema?

    public init(
        name: String,
        description: String? = nil,
        executionKind: ToolExecutionKind,
        remoteTransportID: String? = nil,
        inputSchema: ToolInputSchema? = nil,
        outputSchema: ToolInputSchema? = nil
    ) {
        self.name = name
        self.description = description
        self.executionKind = executionKind
        self.remoteTransportID = remoteTransportID
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
    }

    public static func local<Input: Codable & Sendable, Output: Codable & Sendable>(
        name: String,
        input: Input.Type,
        output: Output.Type,
        description: String? = nil,
        outputSchema: ToolInputSchema? = nil
    ) -> Self {
        ToolDescriptor(
            name: name,
            description: description,
            executionKind: .local,
            outputSchema: outputSchema
        )
    }

    public static func remote(
        name: String,
        transport: String,
        inputSchema: ToolInputSchema,
        description: String? = nil,
        outputSchema: ToolInputSchema? = nil
    ) -> Self {
        ToolDescriptor(
            name: name,
            description: description,
            executionKind: .remote,
            remoteTransportID: transport,
            inputSchema: inputSchema,
            outputSchema: outputSchema
        )
    }
}
