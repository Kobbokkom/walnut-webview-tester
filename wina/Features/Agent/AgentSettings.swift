import CoreFoundation
import Foundation

@MainActor
enum AgentSettings {
    static let tools: [[String: Any]] = [
        AgentTool.definition("settings_get", "List available browser testing settings and their effective and saved values."),
        AgentTool.definition("settings_apply", "Apply a validated patch. Session overrides expire when the connection ends. Persistent edits, enabling Clean Start or Eruda, and disabling private browsing or site protections need iPhone confirmation.", [
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
        AgentTool.definition("bookmarks", "Read saved bookmarks and history, add or remove a bookmark, or remove and clear history. Use nextOffset to continue list or history. Existing full URLs and persistent mutations need confirmation.", [
            "action": choices(["list", "history", "add", "remove", "remove_history", "clear_history"]),
            "url": ["type": "string"],
            "query": ["type": "string"],
            "raw": ["type": "boolean", "default": false],
            "offset": ["type": "integer", "minimum": 0, "default": 0],
            "limit": ["type": "integer", "minimum": 1, "maximum": 100, "default": 50],
        ], required: ["action"]),
    ] + preloadTools + menuTools + userAgentTools

    static func call(
        _ tool: String,
        arguments: [String: Any],
        navigator: WebViewNavigator?,
        validateApplyTarget: () throws -> Void = {},
        authorize: @escaping (String) async -> Bool
    ) async throws -> Any {
        let input = AgentSettingsInput(arguments: arguments, authorize: authorize)
        try Task.checkCancellation()
        switch tool {
        case "settings_get": return settingsSnapshot()
        case "settings_apply": return try await apply(input, validateTarget: validateApplyTarget)
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

    static func configuredBrowserSettings(safari: Bool) -> [String: Any] {
        let settings = AgentBrowserSettings.shared
        let entries = AgentSetting.entries.filter { item in
            guard (item.group == "safari") == safari else { return false }
            switch item.key {
            case "cleanStart", "customUserAgent", "useCallbackTestPage":
                return false
            case "safariControlTintColorHex", "safariBarTintColorHex":
                if #available(iOS 26.0, *) { return false }
                return true
            default:
                return true
            }
        }
        var configured = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, settings.effectiveValue(for: $0)) })
        if safari { configured["presentation"] = "full_screen" }
        return configured
    }

    private static func apply(_ input: AgentSettingsInput, validateTarget: () throws -> Void) async throws -> Any {
        guard let raw = input.arguments["settings"] as? [String: Any] else {
            throw AgentError("Provide a settings object.")
        }
        let persist = try input.flag("persist")
        let values = try AgentSetting.validatePatch(raw, persist: persist)
        var effects: [String] = []
        if values["cleanStart"]?.base as? Bool == true {
            effects.append("With Clean Start on, opening a page from Walnut’s home screen clears all WKWebView website data unless private browsing is on.")
        }
        if values["privateBrowsing"]?.base as? Bool == false {
            effects.append("Turning off private browsing lets Walnut use its persistent WKWebView website data. If Clean Start is on, opening a page from home will clear that data.")
        }
        if values["erudaModeEnabled"]?.base as? Bool == true {
            effects.append("Eruda runs third-party JavaScript on the page.")
        }
        if values["fraudulentWebsiteWarning"]?.base as? Bool == false {
            effects.append("Walnut will stop warning about fraudulent websites.")
        }
        if values["upgradeToHTTPS"]?.base as? Bool == false {
            effects.append("Walnut will stop upgrading known hosts to HTTPS.")
        }
        if persist || !effects.isEmpty {
            let question = persist ? "Save changes to Walnut’s testing settings on this iPhone?"
                : "Apply changes to Walnut’s testing settings for this Mac connection?"
            try await input.confirm(([question] + effects).joined(separator: "\n\n"))
        }
        try validateTarget()
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
