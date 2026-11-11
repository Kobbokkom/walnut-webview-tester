import CoreFoundation
import Foundation
import Observation

@Observable
@MainActor
final class AgentBrowserSettings {
    static let shared = AgentBrowserSettings()

    private(set) var rebuildID = UUID()
    private(set) var safariRebuildID = UUID()

    func browserRevision(safari: Bool) -> UUID { safari ? safariRebuildID : rebuildID }
    private var overrides: [String: AnyHashable] = [:]
    private var profile: WebViewPreloadProfile?

    func value<T>(_ key: String, fallback: T) -> T {
        overrides[key]?.base as? T ?? fallback
    }

    static func saveErudaMode(_ enabled: Bool, agentSettings: AgentBrowserSettings?, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: AgentSetting.erudaKey)
        agentSettings?.reset(keys: [AgentSetting.erudaKey])
    }

    var isolatesPreloadCookies: Bool {
        profile?.isEnabled == true && profile?.cookies.contains(where: \.isEnabled) == true
    }

    func preloadProfile(fallback: WebViewPreloadProfile) -> WebViewPreloadProfile {
        profile ?? fallback
    }

    func setPreloadProfile(_ next: WebViewPreloadProfile?, persist: Bool, defaults: UserDefaults = .standard) {
        if let next, persist {
            PreloadProfileStore.saveActiveProfile(next, defaults: defaults)
        }
        profile = persist ? nil : next
        rebuildID = UUID()
    }

    func setPreloadEnabledFromHome(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        var next = preloadProfile(fallback: PreloadProfileStore.activeProfile(defaults: defaults))
        guard next.isEnabled != isEnabled else { return }
        next.isEnabled = isEnabled
        setPreloadProfile(next, persist: profile == nil, defaults: defaults)
    }

    func effectiveValue(for setting: AgentSetting, defaults: UserDefaults = .standard) -> Any {
        overrides[setting.key]?.base ?? savedValue(for: setting, defaults: defaults)
    }

    func savedValue(for setting: AgentSetting, defaults: UserDefaults = .standard) -> Any {
        guard setting.canPersist, let value = defaults.object(forKey: setting.key),
              let validated = try? setting.validate(value) else { return setting.defaultValue.base }
        return validated.base
    }

    func apply(_ values: [String: AnyHashable], persist: Bool, defaults: UserDefaults = .standard) {
        for (key, value) in values {
            if persist {
                defaults.set(value.base, forKey: key)
                overrides.removeValue(forKey: key)
            } else {
                overrides[key] = value
            }
        }
        invalidateBrowser(for: values.keys)
    }

    func reset(keys: [String]? = nil) {
        let keysToRemove = keys ?? Array(overrides.keys)
        let changedKeys = keysToRemove.filter { overrides[$0] != nil }
        let changedProfile = keys == nil && profile != nil
        for key in keysToRemove {
            overrides.removeValue(forKey: key)
        }
        if keys == nil { profile = nil }
        invalidateBrowser(for: changedKeys)
        if changedProfile { rebuildID = UUID() }
    }

    private func invalidateBrowser(for keys: some Sequence<String>) {
        let settings = keys.compactMap { AgentSetting.catalog[$0] }.filter(\.rebuild)
        if settings.contains(where: { $0.group != "safari" }) { rebuildID = UUID() }
        if settings.contains(where: { $0.group == "safari" }) { safariRebuildID = UUID() }
    }
}

struct AgentSetting {
    enum Kind {
        case boolean
        case text
        case color
        case integer(ClosedRange<Int>)
        case number(ClosedRange<Double>, special: Double? = nil)
        case choice([String])
    }

    let key: String
    let title: String
    let group: String
    let kind: Kind
    let defaultValue: AnyHashable
    var rebuild = false
    var canPersist = true

    var schema: [String: Any] {
        var schema: [String: Any] = ["description": title, "default": defaultValue.base]
        switch kind {
        case .boolean:
            schema["type"] = "boolean"
        case .text, .color:
            schema["type"] = "string"
        case .integer(let range):
            schema["type"] = "integer"
            schema["minimum"] = range.lowerBound
            schema["maximum"] = range.upperBound
        case .number(let range, let special):
            schema["type"] = "number"
            if let special {
                schema["anyOf"] = [["const": special], ["minimum": range.lowerBound, "maximum": range.upperBound]]
            } else {
                schema["minimum"] = range.lowerBound
                schema["maximum"] = range.upperBound
            }
        case .choice(let choices):
            schema["type"] = "string"
            schema["enum"] = choices
        }
        return schema
    }

    func validate(_ value: Any) throws -> AnyHashable {
        let number = value as? NSNumber
        let isBoolean = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        switch kind {
        case .boolean:
            if isBoolean, let number { return number.boolValue }
        case .text:
            if let text = value as? String, text.utf8.count <= 4_096,
               text.rangeOfCharacter(from: .controlCharacters) == nil { return text }
        case .color:
            if let text = value as? String,
               text.isEmpty || text.range(of: #"^#?[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil {
                return text
            }
        case .integer(let range):
            if !isBoolean, let number, let integer = Int(exactly: number.doubleValue), range.contains(integer) {
                return integer
            }
        case .number(let range, let special):
            if !isBoolean, let number, range.contains(number.doubleValue) || number.doubleValue == special {
                return number.doubleValue
            }
        case .choice(let choices):
            if let text = value as? String, choices.contains(text) { return text }
        }
        throw AgentError("Invalid value for \(key).")
    }

    static func validatePatch(_ raw: [String: Any], persist: Bool) throws -> [String: AnyHashable] {
        guard !raw.isEmpty else { throw AgentError("Provide at least one setting.") }
        return try Dictionary(uniqueKeysWithValues: raw.map { key, value in
            guard let setting = catalog[key] else { throw AgentError("Unknown setting: \(key).") }
            guard !persist || setting.canPersist else { throw AgentError("\(key) is session-only.") }
            return (key, try setting.validate(value))
        })
    }

    static let entries = browserConfiguration + browserLive + emulation + safari
    static let catalog = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
    static let emulationKeys = Set(emulation.map(\.key))
    static let erudaKey = "erudaModeEnabled"

    private static let browserConfiguration: [Self] = [
        .init(key: "allowsContentJavaScript", title: "Page JavaScript (app scripts stay available)", group: "configuration", kind: .boolean, defaultValue: true, rebuild: true),
        .init(key: "minimumFontSize", title: "Minimum font size in points, 0 uses default", group: "configuration", kind: .number(0...Double(Int.max).nextDown), defaultValue: 0.0, rebuild: true),
        .init(key: "mediaAutoplay", title: "Media autoplay", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "inlineMediaPlayback", title: "Inline media playback", group: "configuration", kind: .boolean, defaultValue: true, rebuild: true),
        .init(key: "allowsAirPlay", title: "AirPlay", group: "configuration", kind: .boolean, defaultValue: true, rebuild: true),
        .init(key: "allowsPictureInPicture", title: "Picture in Picture", group: "configuration", kind: .boolean, defaultValue: true, rebuild: true),
        .init(key: "preferredContentMode", title: "Content mode (0 recommended, 1 mobile, 2 desktop)", group: "configuration", kind: .integer(0...2), defaultValue: 0, rebuild: true),
        .init(key: "allowZoom", title: "Ignore viewport scale limits", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "javaScriptCanOpenWindows", title: "Allow JavaScript to open windows", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "fraudulentWebsiteWarning", title: "Fraudulent website warning", group: "configuration", kind: .boolean, defaultValue: true, rebuild: true),
        .init(key: "elementFullscreenEnabled", title: "Element Fullscreen API", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "suppressesIncrementalRendering", title: "Suppress incremental rendering", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "detectPhoneNumbers", title: "Detect phone numbers", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "detectLinks", title: "Detect links", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "detectAddresses", title: "Detect addresses", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "detectCalendarEvents", title: "Detect calendar events", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "privateBrowsing", title: "Use a nonpersistent website data store", group: "configuration", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "upgradeToHTTPS", title: "Upgrade known hosts to HTTPS", group: "configuration", kind: .boolean, defaultValue: true, rebuild: true),
    ]

    private static let browserLive: [Self] = [
        .init(key: "allowsBackForwardGestures", title: "Back/forward gestures", group: "live", kind: .boolean, defaultValue: false),
        .init(key: "allowsLinkPreview", title: "Link preview", group: "live", kind: .boolean, defaultValue: true),
        .init(key: "textInteractionEnabled", title: "Text interaction", group: "live", kind: .boolean, defaultValue: true),
        .init(key: "findInteractionEnabled", title: "System Find interaction", group: "live", kind: .boolean, defaultValue: false),
        .init(key: "pageZoom", title: "Page zoom ratio", group: "live", kind: .number(0.5...3), defaultValue: 1.0),
        .init(key: "underPageBackgroundColor", title: "Under-page background hex color, empty uses default", group: "live", kind: .color, defaultValue: ""),
        .init(key: "customUserAgent", title: "User-Agent string, empty uses default; applies to next request", group: "live", kind: .text, defaultValue: ""),
        .init(key: "webViewWidthRatio", title: "WKWebView width ratio", group: "live", kind: .number(0.25...1), defaultValue: 1.0),
        .init(key: "webViewHeightRatio", title: "WKWebView height ratio, 0 selects App preset", group: "live", kind: .number(0.25...1, special: BarConstants.appHeightPreset), defaultValue: 0.82),
        .init(key: "cleanStart", title: "Default for local WKWebView fresh-data launches; remote deletion requires explicit approval", group: "startup", kind: .boolean, defaultValue: true),
        .init(key: erudaKey, title: "Enable third-party Eruda Console in WKWebView", group: "developer_tools", kind: .boolean, defaultValue: false),
    ]

    private static let emulation: [Self] = [
        .init(key: "emulationColorScheme", title: "Emulated matchMedia and color-scheme property", group: "emulation", kind: .choice(["system", "light", "dark"]), defaultValue: "system"),
        .init(key: "emulationReducedMotion", title: "Emulate reduced motion", group: "emulation", kind: .boolean, defaultValue: false),
        .init(key: "emulationHighContrast", title: "Emulate JavaScript high contrast", group: "emulation", kind: .boolean, defaultValue: false),
        .init(key: "emulationReducedTransparency", title: "Emulate reduced transparency", group: "emulation", kind: .boolean, defaultValue: false),
    ]

    private static let safari: [Self] = [
        .init(key: "safariEntersReaderIfAvailable", title: "Enter SafariVC Reader Mode when available", group: "safari", kind: .boolean, defaultValue: false, rebuild: true),
        .init(key: "safariBarCollapsingEnabled", title: "SafariVC bar collapsing", group: "safari", kind: .boolean, defaultValue: true, rebuild: true),
        .init(key: "safariDismissButtonStyle", title: "SafariVC dismiss style (0 done, 1 close, 2 cancel)", group: "safari", kind: .integer(0...2), defaultValue: 0),
        .init(key: "safariControlTintColorHex", title: "SafariVC control tint before iOS 26, empty uses default", group: "safari", kind: .color, defaultValue: "", rebuild: true),
        .init(key: "safariBarTintColorHex", title: "SafariVC bar tint before iOS 26, empty uses default", group: "safari", kind: .color, defaultValue: "", rebuild: true),
        .init(key: "useCallbackTestPage", title: "Use Walnut's callback test page for SafariVC launches", group: "safari", kind: .boolean, defaultValue: false, canPersist: false),
    ]
}
