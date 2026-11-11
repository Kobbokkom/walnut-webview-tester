import CoreFoundation
import Foundation

@MainActor
enum AgentDevTools {
    static let tools = logTools + pageTools + storageTools + [AgentEngineInspection.tool]

    static func call(
        _ tool: String,
        arguments: [String: Any],
        navigator: WebViewNavigator,
        storage: StorageManager,
        console: ConsoleSession,
        authorize: @escaping (String) async -> Bool
    ) async throws -> Any {
        let context = AgentDevContext(navigator: navigator, authorize: authorize)
        try context.checkDocument()
        let input = AgentDevInput(values: arguments)

        if tool == "agent_engine_inspection" {
            return try await AgentEngineInspection.call(input: input, context: context)
        }
        if logTools.contains(where: { $0["name"] as? String == tool }) {
            return try await callLogs(tool, input, context, console)
        }
        if storageTools.contains(where: { $0["name"] as? String == tool }) {
            return try await callStorage(tool, input, context, storage)
        }
        return try await callPage(tool, input, context)
    }

    static let query = ["type": "string", "maxLength": 256] as [String: Any]
    static let raw = ["type": "boolean", "description": "Include page content. Requires confirmation on the iPhone."] as [String: Any]
    static let flag = ["type": "boolean"]
    static let limit = ["type": "integer", "minimum": 1, "maximum": 100, "default": 30] as [String: Any]
    static let offset = ["type": "integer", "minimum": 0, "maximum": 100000] as [String: Any]
    static let identifier = ["type": "string"]
    static let text = ["type": "string", "maxLength": 16384] as [String: Any]

    static func options(_ names: [String]) -> [String: Any] {
        ["type": "string", "enum": names]
    }

    static func options<T>(_ type: T.Type) -> [String: Any]
    where T: CaseIterable & RawRepresentable, T.RawValue == String {
        options(type.allCases.map(\.rawValue))
    }

    static func paginate<T>(_ input: AgentDevInput, _ records: [T]) throws -> ArraySlice<T> {
        try records.dropFirst(input.int("offset", default: 0, range: 0...100_000))
            .prefix(input.int("limit", default: 30, range: 1...100))
    }

    static func safeURL(_ raw: String) -> String {
        guard let parts = URLComponents(string: raw), let host = parts.host, let scheme = parts.scheme,
              ["http", "https", "ws", "wss"].contains(scheme.lowercased()) else { return "" }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = parts.port
        return origin.string ?? ""
    }

    static func clipped(_ value: String, limit: Int = 4096) -> String {
        String(value.prefix(limit))
    }

    static func parseJSON(_ value: Any?) throws -> Any {
        guard let json = value as? String, let bytes = json.data(using: .utf8) else {
            throw AgentError("No data returned from the page.")
        }
        return try JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed)
    }
}

@MainActor
struct AgentDevContext {
    let navigator: WebViewNavigator
    let document: UUID
    let authorize: (String) async -> Bool

    init(navigator: WebViewNavigator, authorize: @escaping (String) async -> Bool) {
        self.navigator = navigator
        self.document = navigator.documentID
        self.authorize = authorize
    }

    func checkDocument() throws {
        try Task.checkCancellation()
        guard navigator.isAttached, navigator.documentID == document else {
            throw AgentError("The active WKWebView document changed. Try again.")
        }
    }

    func confirm(_ prompt: String) async throws {
        guard await authorize(prompt) else {
            throw AgentError("The iPhone did not approve this action.")
        }
        try checkDocument()
    }
}

@MainActor
struct AgentDevInput {
    let values: [String: Any]

    func string(_ key: String, maxLength: Int = 256) throws -> String? {
        guard let value = values[key] else { return nil }
        guard let value = value as? String, value.count <= maxLength else {
            throw AgentError("\(key) must be a string of at most \(maxLength) characters.")
        }
        return value
    }

    func required(_ key: String, maxLength: Int = 256, allowEmpty: Bool = false) throws -> String {
        guard let value = try string(key, maxLength: maxLength), allowEmpty || !value.isEmpty else {
            throw AgentError("\(key) is required.")
        }
        return value
    }

    // swiftlint:disable:next discouraged_optional_boolean
    func bool(_ key: String) throws -> Bool? {
        guard let value = values[key] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw AgentError("\(key) must be a Boolean.")
        }
        return number.boolValue
    }

    func int(_ key: String, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value = values[key] else { return defaultValue }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = value as? Int, range.contains(integer) else {
            throw AgentError("\(key) must be an integer in \(range).")
        }
        return integer
    }

    func option<T: RawRepresentable>(_ key: String, as type: T.Type) throws -> T? where T.RawValue == String {
        guard let value = try string(key) else { return nil }
        guard let choice = T(rawValue: value) else {
            throw AgentError("Invalid \(key) option.")
        }
        return choice
    }

    func uuid(_ key: String) throws -> UUID {
        guard let uuid = try UUID(uuidString: required(key)) else {
            throw AgentError("\(key) must be a record ID.")
        }
        return uuid
    }
}
