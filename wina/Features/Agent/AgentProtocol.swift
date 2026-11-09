import CoreFoundation
import Foundation

struct AgentError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

enum AgentTool {
    static func definition(
        _ name: String,
        _ description: String,
        _ properties: [String: [String: Any]] = [:],
        required: [String] = []
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ]
        ]
    }

    static func validate(_ arguments: [String: Any], using tool: [String: Any]) throws {
        guard let schema = tool["inputSchema"] as? [String: Any],
              let properties = schema["properties"] as? [String: [String: Any]] else { return }
        if let missing = (schema["required"] as? [String])?.first(where: { arguments[$0] == nil }) {
            throw AgentError("Missing argument: \(missing).")
        }
        for (key, value) in arguments {
            guard let field = properties[key] else { throw AgentError("Unknown argument: \(key).") }
            guard accepts(value, field: field) else { throw AgentError("Invalid argument: \(key).") }
        }
    }

    private static func accepts(_ value: Any, field: [String: Any]) -> Bool {
        let number = value as? NSNumber
        let isBoolean = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        switch field["type"] as? String {
        case "string" where !(value is String): return false
        case "boolean" where !isBoolean: return false
        case "number" where number == nil || isBoolean: return false
        case "integer" where !(value is Int) || isBoolean: return false
        case "array" where !(value is [Any]): return false
        case "object" where !(value is [String: Any]): return false
        default: break
        }
        if let choices = field["enum"] as? [String], let string = value as? String, !choices.contains(string) {
            return false
        }
        if let number, !isBoolean {
            let value = number.doubleValue
            if !value.isFinite { return false }
            if let minimum = (field["minimum"] as? NSNumber)?.doubleValue, value < minimum { return false }
            if let maximum = (field["maximum"] as? NSNumber)?.doubleValue, value > maximum { return false }
        }
        return true
    }

    static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
}

struct AgentRequest: Decodable {
    let id: String
    let tool: String

    static func decode(_ data: Data) throws -> (AgentRequest, [String: Any]) {
        let request = try JSONDecoder().decode(Self.self, from: data)
        guard request.id.utf8.count <= 128,
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arguments = envelope["arguments"] as? [String: Any] else {
            throw AgentError("Invalid Walnut request.")
        }
        return (request, arguments)
    }
}

struct AgentLogSettings {
    // nil inherits the user’s saved log setting.
    // swiftlint:disable:next discouraged_optional_boolean
    var consolePreserveLog: Bool?
    // swiftlint:disable:next discouraged_optional_boolean
    var networkPreserveLog: Bool?
    var consoleClearStrategy: LogClearStrategy?
    var networkClearStrategy: LogClearStrategy?
}
