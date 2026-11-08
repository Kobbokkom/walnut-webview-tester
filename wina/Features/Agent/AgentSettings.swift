import CoreFoundation
import Foundation

@MainActor
enum AgentSettings {
    static let tools: [[String: Any]] = [
        AgentTool.definition("settings_get", "List available browser testing settings and their effective and saved values."),
        AgentTool.definition("settings_apply", "Apply a validated patch. Session overrides expire when the connection ends. Persistent edits and Eruda activation need iPhone confirmation.", [
            "settings": [
                "type": "object",
                "properties": AgentSetting.catalog.mapValues(\.schema),
                "additionalProperties": false,
                "minProperties": 1,
            ],
            "persist": ["type": "boolean", "default": false],
        ], required: ["settings"]),
        AgentTool.definition("settings_reset", "Clear session testing overrides to reveal saved values. Omit keys to also clear the startup profile and menu overrides.", [
            "keys": ["type": "array", "items": ["type": "string", "enum": AgentSetting.catalog.keys.sorted()]],
        ]),
        AgentTool.definition("diagnostics", "Run Walnut's Info diagnostics. Use the active WKWebView when attached, or a temporary WKWebView for feature detection. Benchmark always runs separately.", [
            "section": choices(["device", "browser", "api", "codecs", "benchmark", "display", "accessibility", "permissions", "safari"]),
        ], required: ["section"]),
        AgentTool.definition("permissions", "Read iOS permission states. Request hands off to the iPhone user and iOS. If already determined, opens the iOS Settings page.", [
            "action": choices(["status", "request"]),
            "permission": choices(["camera", "microphone", "location"]),
        ], required: ["action"]),
        AgentTool.definition("callbacks", "Read, clear, or locate the Walnut URL scheme test page. Raw callback URL and query values need confirmation.", [
            "action": choices(["get", "clear", "test_page"]),
            "raw": ["type": "boolean", "default": false],
        ], required: ["action"]),
        AgentTool.definition("bookmarks", "Read saved bookmarks and history, add or remove a bookmark, or remove and clear history. Existing full URLs and persistent mutations need confirmation.", [
            "action": choices(["list", "history", "add", "remove", "remove_history", "clear_history"]),
            "url": ["type": "string"],
            "query": ["type": "string"],
            "raw": ["type": "boolean", "default": false],
        ], required: ["action"]),
    ] + preloadTools + menuTools + userAgentTools

    static func call(
        _ tool: String,
        arguments: [String: Any],
        navigator: WebViewNavigator?,
        authorize: @escaping (String) async -> Bool
    ) async throws -> Any {
        let input = AgentSettingsInput(arguments: arguments, authorize: authorize)
        try Task.checkCancellation()
        switch tool {
        case "settings_get": return settingsSnapshot()
        case "settings_apply": return try await apply(input)
        case "settings_reset": return try reset(input)
        case "diagnostics": return try await diagnostics(input.string("section"), navigator: navigator)
        case "permissions": return try await permissions(input)
        case "callbacks": return try await callbacks(input)
        case "bookmarks": return try await bookmarks(input)
        case "preload": return try await preload(input, navigator: navigator)
        case "menus": return try await menus(input)
        case "user_agent": return try userAgent(input)
        default: throw AgentError("Unknown testing tool: \(tool).")
        }
    }

    static func choices(_ values: [String]) -> [String: Any] {
        ["type": "string", "enum": values]
    }

    private static func settingsSnapshot() -> [[String: Any]] {
        let settings = AgentBrowserSettings.shared
        return AgentSetting.entries.map { item in
            [
                "key": item.key,
                "group": item.group,
                "schema": item.schema,
                "value": settings.effectiveValue(for: item),
                "saved": settings.savedValue(for: item),
                "recreatesBrowser": item.rebuild,
                "canPersist": item.canPersist,
            ]
        }
    }

    private static func apply(_ input: AgentSettingsInput) async throws -> Any {
        guard let raw = input.arguments["settings"] as? [String: Any] else {
            throw AgentError("Provide a settings object.")
        }
        let persist = try input.flag("persist")
        let values = try AgentSetting.validatePatch(raw, persist: persist)
        let enablingEruda = values["erudaModeEnabled"]?.base as? Bool == true
        if enablingEruda {
            let prompt = persist
                ? "Save the test settings and enable third-party Eruda JavaScript in Walnut?"
                : "Enable third-party Eruda JavaScript for this Walnut session?"
            try await input.confirm(prompt)
        } else if persist {
            try await input.confirm("Save changes to Walnut's testing settings on this iPhone?")
        }
        AgentBrowserSettings.shared.apply(values, persist: persist)
        return [
            "applied": values.mapValues(\.base),
            "persisted": persist,
            "browserRecreationRequested": values.keys.contains { AgentSetting.catalog[$0]?.rebuild == true },
        ] as [String: Any]
    }

    private static func reset(_ input: AgentSettingsInput) throws -> Any {
        var keys: [String]?
        if let value = input.arguments["keys"] {
            guard let list = value as? [String], list.allSatisfy({ AgentSetting.catalog[$0] != nil }) else {
                throw AgentError("Provide a list of known setting keys.")
            }
            keys = list
        }
        let settings = AgentBrowserSettings.shared
        let previous = (settings.rebuildID, settings.safariRebuildID)
        settings.reset(keys: keys)
        return [
            "browserRecreationRequested": previous != (settings.rebuildID, settings.safariRebuildID),
            "settings": settingsSnapshot()
        ]
    }
}

@MainActor
struct AgentSettingsInput {
    let arguments: [String: Any]
    let authorize: (String) async -> Bool

    func string(_ name: String, default fallback: String? = nil, limit: Int = 4_096) throws -> String {
        if arguments[name] == nil, let fallback { return fallback }
        guard let text = arguments[name] as? String, text.utf8.count <= limit,
              text.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw AgentError("Invalid or missing \(name).")
        }
        return text
    }

    func flag(_ name: String, default fallback: Bool = false) throws -> Bool {
        guard let value = arguments[name] else { return fallback }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw AgentError("\(name) must be a Boolean.")
        }
        return number.boolValue
    }

    func confirm(_ prompt: String) async throws {
        guard await authorize(prompt) else { throw AgentError("The iPhone did not approve this action.") }
        try Task.checkCancellation()
    }
}
