import Foundation

public enum ExampleEnvironment {
    public static func require(_ name: String, help: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment[name], !value.isEmpty else {
            fputs("\(help)\n", stderr)
            Foundation.exit(1)
        }
        return value
    }

    public static func value(_ name: String, default defaultValue: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment[name], !value.isEmpty else {
            return defaultValue
        }
        return value
    }

    public static func url(_ name: String, default defaultValue: String) -> URL {
        let rawValue = value(name, default: defaultValue)
        guard let url = URL(string: rawValue) else {
            fputs("Invalid URL for \(name): \(rawValue)\n", stderr)
            Foundation.exit(1)
        }
        return url
    }
}
