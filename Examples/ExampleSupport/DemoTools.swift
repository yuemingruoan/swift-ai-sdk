import Foundation
import OpenAIAgentRuntime

public func demoWeatherToolDescriptor() -> ToolDescriptor {
    ToolDescriptor.remote(
        name: "lookup_weather",
        transport: DemoWeatherTransport.demoTransportID,
        inputSchema: .object(
            properties: [
                "city": .string,
            ],
            required: ["city"]
        ),
        description: "Look up a deterministic weather summary for a city. Use this when the user asks for current weather in a specific city.",
        outputSchema: .object(
            properties: [
                "city": .string,
                "forecast": .string,
                "temperature_c": .integer,
            ],
            required: ["city", "forecast", "temperature_c"]
        )
    )
}

public actor DemoWeatherTransport: RemoteToolTransport {
    public static let demoTransportID = "weather-demo"

    public let transportID = DemoWeatherTransport.demoTransportID

    public init() {}

    public func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        let city = invocation.arguments?["city"].flatMap(cityName(from:)) ?? "Unknown"
        let forecast: String
        let temperature: Int

        switch city.lowercased() {
        case "paris":
            forecast = "Sunny"
            temperature = 22
        case "tokyo":
            forecast = "Cloudy"
            temperature = 19
        case "san francisco":
            forecast = "Foggy"
            temperature = 15
        default:
            forecast = "Clear"
            temperature = 20
        }

        return ToolResult(
            payload: .object([
                "city": .string(city),
                "forecast": .string(forecast),
                "temperature_c": .integer(temperature),
            ])
        )
    }

    private func cityName(from value: ToolValue) -> String? {
        guard case .string(let city) = value else {
            return nil
        }
        return city
    }
}
