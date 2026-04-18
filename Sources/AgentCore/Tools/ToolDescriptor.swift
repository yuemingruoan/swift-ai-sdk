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

public struct ToolTypeReference: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public init<T>(_ type: T.Type) {
        self.name = String(reflecting: type)
    }
}

public struct ToolDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let executionKind: ToolExecutionKind
    public let inputType: ToolTypeReference?
    public let outputType: ToolTypeReference?
    public let remoteTransportID: String?
    public let inputSchema: ToolInputSchema?

    public init(
        name: String,
        executionKind: ToolExecutionKind,
        inputType: ToolTypeReference? = nil,
        outputType: ToolTypeReference? = nil,
        remoteTransportID: String? = nil,
        inputSchema: ToolInputSchema? = nil
    ) {
        self.name = name
        self.executionKind = executionKind
        self.inputType = inputType
        self.outputType = outputType
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
            executionKind: .local,
            inputType: ToolTypeReference(input),
            outputType: ToolTypeReference(output)
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
