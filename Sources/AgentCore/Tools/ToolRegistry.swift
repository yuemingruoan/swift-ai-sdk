import Foundation

public enum ToolRegistryError: Error, Equatable, Sendable {
    case duplicateDescriptor(name: String)
}

public actor ToolRegistry {
    private var descriptors: [String: ToolDescriptor] = [:]

    public init() {}

    public func register(_ descriptor: ToolDescriptor) throws {
        guard descriptors[descriptor.name] == nil else {
            throw ToolRegistryError.duplicateDescriptor(name: descriptor.name)
        }

        descriptors[descriptor.name] = descriptor
    }

    public func descriptor(named name: String) -> ToolDescriptor? {
        descriptors[name]
    }
}
