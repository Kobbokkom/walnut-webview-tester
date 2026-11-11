import Foundation

extension AgentSettings {
    private static let bridgeLogPageLimit = 200

    static let preloadTools = [
        AgentTool.definition("preload", "Inspect and manage WKWebView Page Startup Setup: cookies, window values/functions, native bridge mocks, postMessage capture, and document-start scripts. Use template to obtain the full Codable profile shape. Apply/load/save/delete and sharing raw data need iPhone confirmation.", [
            "action": choices(["get", "list", "template", "apply", "load", "save", "delete", "disable", "reset", "logs", "clear_logs"]),
            "preset": choices(["empty", "native_bridge_demo"]),
            "id": ["type": "string", "format": "uuid"],
            "profile": [
                "type": "object",
                "description": "Complete profile from template or get(raw: true). Preserve entry IDs when editing; use new UUIDs for new entries.",
                "properties": [
                    "id": ["type": "string", "format": "uuid"],
                    "name": ["type": "string"],
                    "isEnabled": ["type": "boolean"],
                    "cookies": [
                        "type": "array", "items": ["type": "object"],
                        "description": "Cookie domainMode currentHost/custom; expires session/oneHour/oneDay/sevenDays; sameSite lax/strict/none. See the template for all fields.",
                    ],
                    "windowItems": [
                        "type": "array", "items": ["type": "object"],
                        "description": "Window kind variable/functionReturn/functionBody; valueKind string/json. Use a dotted JavaScript path for name.",
                    ],
                    "bridgeChannels": [
                        "type": "array", "items": ["type": "object"],
                        "description": #"Rule matchers {"any":{}}, {"typeEquals":{"_0":"type"}}, or {"jsonPathEquals":{"path":"field","value":"expected"}}. Response target postMessage/customEvent/callback/customJavaScript."#,
                    ],
                    "capturesWindowPostMessage": ["type": "boolean"],
                    "customScripts": ["type": "array", "items": ["type": "object"]],
                ],
                "required": ["id", "name", "isEnabled", "cookies", "windowItems", "bridgeChannels", "capturesWindowPostMessage", "customScripts"],
                "additionalProperties": false,
            ],
            "persist": ["type": "boolean", "default": false],
            "raw": ["type": "boolean", "default": false, "description": "Share full profile content or bridge log bodies with iPhone approval."],
            "offset": ["type": "integer", "minimum": 0, "default": 0, "description": "Skip this many of the newest retained bridge logs."],
            "limit": [
                "type": "integer", "minimum": 1, "maximum": bridgeLogPageLimit, "default": 50,
                "description": "Maximum number of bridge logs to list. Use 200 to list all retained entries.",
            ],
            "logId": [
                "type": "string", "format": "uuid",
                "description": "With logs and raw:true, read the selected log's entire retained body instead of a list preview. For a large record, concatenate content chunks and parse them as JSON.",
            ],
            "byteOffset": AgentDevTools.exportByteOffset,
            "contentId": ["type": "string", "description": "Continue a large log record with this contentId and nextByteOffset as byteOffset."],
        ], required: ["action"]),
    ]

    static func preload(_ input: AgentSettingsInput, navigator: WebViewNavigator?) async throws -> Any {
        let action = try input.string("action")
        switch action {
        case "get", "list", "template": return try await readProfiles(action, input)
        case "logs", "clear_logs": return try await bridgeLogs(action, input, navigator: navigator)
        case "apply", "load", "save", "delete", "disable", "reset": return try await changeProfiles(action, input)
        default: throw AgentError("Unknown Page Startup Setup action.")
        }
    }

    private static func readProfiles(_ action: String, _ input: AgentSettingsInput) async throws -> Any {
        switch action {
        case "list":
            return PreloadProfileStore.savedProfiles().map(profileSummary)
        case "template":
            switch try input.string("preset", default: "native_bridge_demo") {
            case "empty": return try AgentTool.json(WebViewPreloadProfile.empty)
            case "native_bridge_demo":
                var demo = WebViewPreloadProfile.nativeBridgeDemoPreset
                demo.id = UUID()
                demo.customScripts.append(PreloadCustomScript(isEnabled: false, name: "Document start example", source: "window.walnutDemo = true;"))
                return try AgentTool.json(demo)
            default: throw AgentError("Unknown Page Startup Setup preset.")
            }
        default:
            let profile = try input.arguments["id"] == nil ? currentProfile() : savedProfile(input)
            if try input.flag("raw") {
                try await input.confirm("Share this Walnut startup profile, including cookie values and JavaScript, with the paired Mac?")
                return try AgentTool.json(profile)
            }
            return profileSummary(profile)
        }
    }

    private static func changeProfiles(_ action: String, _ input: AgentSettingsInput) async throws -> Any {
        let settings = AgentBrowserSettings.shared
        let persist = try input.flag("persist")
        switch action {
        case "apply", "load":
            let candidate = try action == "load" ? savedProfile(input) : decodeProfile(input)
            try await input.confirm("\(persist ? "Save and apply" : "Apply for this session") the startup profile in Walnut? It can set cookies and run JavaScript on subsequent WKWebView loads.")
            settings.setPreloadProfile(candidate, persist: persist)
        case "save":
            let candidate = try input.arguments["profile"] == nil ? currentProfile() : decodeProfile(input)
            try await input.confirm("Save this startup profile to Walnut on this iPhone?")
            return profileSummary(PreloadProfileStore.upsertSavedProfile(candidate))
        case "delete":
            let id = try savedProfile(input).id
            try await input.confirm("Delete this saved startup profile from Walnut?")
            let remaining = PreloadProfileStore.savedProfiles().filter { $0.id != id }
            PreloadProfileStore.saveProfiles(remaining)
            return ["deleted": id.uuidString]
        case "disable":
            if persist { try await input.confirm("Disable Walnut's startup profile for future sessions?") }
            var candidate = currentProfile()
            candidate.isEnabled = false
            settings.setPreloadProfile(candidate, persist: persist)
        default:
            guard !persist else { throw AgentError("Reset only removes the session override. Use disable to update the saved configuration.") }
            settings.setPreloadProfile(nil, persist: false)
        }
        return profileSummary(currentProfile())
    }

    private static func bridgeLogs(_ action: String, _ input: AgentSettingsInput, navigator: WebViewNavigator?) async throws -> Any {
        guard let navigator, navigator.isAttached else { throw AgentError("Open an active WKWebView first.") }
        let context = AgentDevContext(navigator: navigator, authorize: input.authorize)
        let raw = try input.flag("raw")
        if action == "clear_logs" {
            try await context.confirm("Clear Walnut's startup bridge log?")
            navigator.preloadBridgeLogManager.clear()
            return ["cleared": true]
        }

        let options = AgentDevInput(values: input.arguments)
        if input.arguments["logId"] != nil {
            guard raw else { throw AgentError("Set raw to true to request the retained bridge log body.") }
            return try await bridgeLogDetail(options, context: context)
        }
        let offset = try options.int("offset", default: 0, range: 0...Int.max)
        let limit = try options.int("limit", default: 50, range: 1...bridgeLogPageLimit)
        if raw { try await context.confirm("Share startup bridge message bodies with the paired Mac?") }
        return navigator.preloadBridgeLogManager.entries.dropFirst(offset).prefix(limit).map { entry in
            var record = bridgeLogRecord(entry)
            // Bound list previews by scalars because one Swift Character can contain many of them.
            record["channel"] = String(entry.channel.unicodeScalars.prefix(4_096))
            if raw { record["body"] = String(entry.body.prefix(4_096).unicodeScalars.prefix(8_192)) }
            return record
        }
    }

    private static func bridgeLogDetail(_ input: AgentDevInput, context: AgentDevContext) async throws -> [String: Any] {
        let id = try input.uuid("logId")
        let cursor = try AgentDevTools.exportCursor(input, source: "startup bridge log")
        try await context.confirm("Share the selected startup bridge log and its retained message body with the paired Mac?")
        guard let entry = context.navigator.preloadBridgeLogManager.entries.first(where: { $0.id == id }) else {
            throw AgentError("Startup bridge log entry not found.")
        }
        var record = bridgeLogRecord(entry)
        record["body"] = entry.body
        return try AgentDevTools.exportRecord(record, cursor: cursor, source: "startup bridge log")
    }

    private static func bridgeLogRecord(_ entry: PreloadBridgeLogEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "date": entry.date.formatted(.iso8601),
            "channel": entry.channel,
            "direction": entry.direction == .received ? "received" : "responded",
        ]
    }

    private static func currentProfile() -> WebViewPreloadProfile {
        AgentBrowserSettings.shared.preloadProfile(fallback: PreloadProfileStore.activeProfile())
    }

    private static func savedProfile(_ input: AgentSettingsInput) throws -> WebViewPreloadProfile {
        guard let id = UUID(uuidString: try input.string("id")),
              let profile = PreloadProfileStore.savedProfiles().first(where: { $0.id == id }) else {
            throw AgentError("No saved startup profile with that ID.")
        }
        return profile
    }

    private static func decodeProfile(_ input: AgentSettingsInput) throws -> WebViewPreloadProfile {
        guard let raw = input.arguments["profile"] as? [String: Any], JSONSerialization.isValidJSONObject(raw) else {
            throw AgentError("Provide a startup profile from preload template or get.")
        }
        let bytes = try JSONSerialization.data(withJSONObject: raw)
        guard bytes.count <= 65_536,
              let profile = try? JSONDecoder().decode(WebViewPreloadProfile.self, from: bytes) else {
            throw AgentError("Invalid startup profile or profile exceeds 64 KiB.")
        }
        if let message = PreloadProfileValidation.message(for: profile) { throw AgentError(message) }
        try validateProfileEntries(profile)
        return profile
    }

    private static func validateProfileEntries(_ profile: WebViewPreloadProfile) throws {
        try requireUniqueIDs(profile.cookies)
        try requireUniqueIDs(profile.windowItems)
        try requireUniqueIDs(profile.bridgeChannels)
        try requireUniqueIDs(profile.customScripts)
        for channel in profile.bridgeChannels {
            try requireUniqueIDs(channel.responseRules)
            guard channel.responseRules.allSatisfy({ (0...60_000).contains($0.delayMilliseconds) }) else {
                throw AgentError("Bridge delay must be between 0 and 60,000 ms.")
            }
        }
        for item in profile.windowItems where item.isEnabled {
            guard JavaScriptPath.isValid(item.name) else {
                throw AgentError("Enabled window values must have a valid JavaScript path.")
            }
            if item.kind != .functionBody, item.valueKind == .json {
                let data = Data(item.value.utf8)
                guard (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil else {
                    throw AgentError("Invalid JSON for window value: \(item.name).")
                }
            }
        }
    }

    private static func requireUniqueIDs<Entry: Identifiable>(_ entries: [Entry]) throws {
        guard Set(entries.map(\.id)).count == entries.count else {
            throw AgentError("Profile entries must have unique IDs within their list.")
        }
    }

    private static func profileSummary(_ profile: WebViewPreloadProfile) -> [String: Any] {
        [
            "id": profile.id.uuidString,
            "name": profile.name,
            "enabled": profile.isEnabled,
            "cookieCount": profile.cookies.count,
            "windowItemCount": profile.windowItems.count,
            "bridgeChannelCount": profile.bridgeChannels.count,
            "scriptCount": profile.customScripts.count,
            "capturesWindowPostMessage": profile.capturesWindowPostMessage,
        ]
    }
}
