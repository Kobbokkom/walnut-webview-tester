import Foundation

extension AgentSettings {
    static let userAgentTools = [
        AgentTool.definition("user_agent", "List Walnut's user-agent presets, build a custom value, or parse a value. Apply the returned userAgent with settings_apply customUserAgent; an empty string restores the system default.", [
            "action": choices(["presets", "build", "parse"]),
            "query": ["type": "string"],
            "browser": choices(UserAgentBrowser.allCases.map(\.rawValue)),
            "platform": choices(UserAgentBuilder.PlatformToken.all.map(\.description)),
            "version": ["type": "string"],
            "userAgent": ["type": "string"],
        ], required: ["action"]),
    ]

    static func userAgent(_ input: AgentSettingsInput) throws -> Any {
        switch try input.string("action") {
        case "presets":
            let query = try input.string("query", default: "", limit: 256)
            let presets = query.isEmpty ? UserAgentPresets.allPresets : UserAgentPresets.search(query)
            return presets.map { preset in
                [
                    "name": preset.name,
                    "browser": preset.browser.rawValue,
                    "platform": preset.platform.rawValue,
                    "os": preset.os.rawValue,
                    "userAgent": preset.userAgent,
                ]
            }
        case "build":
            let browserName = try input.string("browser")
            let platformName = try input.string("platform")
            let version = try input.string("version", limit: 40)
            guard let browser = UserAgentBrowser(rawValue: browserName),
                  let platform = UserAgentBuilder.PlatformToken.all.first(where: { $0.description == platformName }),
                  version.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil else {
                throw AgentError("Provide a supported browser, platform, and dotted numeric version.")
            }
            return ["userAgent": UserAgentBuilder.compose(browser: browser, platform: platform, version: version)]
        case "parse":
            let parsed = UserAgentParser.parse(try input.string("userAgent"))
            return [
                "browser": parsed.browser, "browserVersion": parsed.browserVersion,
                "platform": parsed.platform, "engine": parsed.engine, "engineVersion": parsed.engineVersion,
                "os": parsed.osName, "osVersion": parsed.osVersion, "deviceType": parsed.deviceType,
                "deviceVendor": parsed.deviceVendor, "deviceModel": parsed.deviceModel,
            ]
        default: throw AgentError("Unknown user-agent action.")
        }
    }
}
