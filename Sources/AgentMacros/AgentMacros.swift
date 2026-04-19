import Foundation
import AgentCore

@attached(member, names: named(toolDescriptor))
public macro Tool(_ name: String? = nil) = #externalMacro(
    module: "AgentMacrosPlugin",
    type: "ToolMacro"
)
