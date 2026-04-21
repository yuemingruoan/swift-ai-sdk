import Foundation

/// Declares whether a tool is resolved locally or through a remote transport.
public enum ToolExecutionKind: String, Codable, Equatable, Sendable {
    case local
    case remote
}

/// Lightweight schema description used for request and response tool payloads.
public indirect enum ToolInputSchema: Codable, Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case array(items: ToolInputSchema)
    case object(properties: [String: ToolInputSchema] = [:], required: [String] = [])
}

/// Provider-neutral metadata describing a callable tool.
public struct ToolDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let description: String?
    public let executionKind: ToolExecutionKind
    public let remoteTransportID: String?
    public let inputSchema: ToolInputSchema?
    public let outputSchema: ToolInputSchema?

    /// Creates a provider-neutral tool descriptor.
    /// - Parameters:
    ///   - name: Stable tool identifier used in model tool calls.
    ///   - description: Optional natural-language description presented to the model.
    ///   - executionKind: Whether the tool is executed locally or through a remote transport.
    ///   - remoteTransportID: Remote transport identifier used when `executionKind` is `.remote`.
    ///   - inputSchema: Optional schema describing accepted tool arguments.
    ///   - outputSchema: Optional schema describing the tool result shape.
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

    /// Creates a descriptor for a tool implemented in the current process.
    /// - Parameters:
    ///   - name: Stable tool identifier.
    ///   - input: Swift input type used by the local executable.
    ///   - output: Swift output type produced by the local executable.
    ///   - description: Optional natural-language description for model tool selection.
    ///   - outputSchema: Optional schema describing the returned payload.
    /// - Returns: A local tool descriptor.
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

    /// Creates a descriptor for a tool resolved through a named remote transport.
    /// - Parameters:
    ///   - name: Stable tool identifier.
    ///   - transport: Identifier of the remote transport that can execute the tool.
    ///   - inputSchema: Schema describing arguments accepted by the remote tool.
    ///   - description: Optional natural-language description for model tool selection.
    ///   - outputSchema: Optional schema describing the returned payload.
    /// - Returns: A remote tool descriptor.
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
