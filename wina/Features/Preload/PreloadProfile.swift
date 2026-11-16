//
//  PreloadProfile.swift
//  wina
//
//  Reusable WKWebView preload and bridge mock profile models.
//

import Foundation

// MARK: - Profile

struct WebViewPreloadProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var cookies: [PreloadCookie]
    var windowItems: [WindowInjectionItem]
    var bridgeChannels: [BridgeChannel]
    var capturesWindowPostMessage: Bool
    var customScripts: [PreloadCustomScript]

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isEnabled: Bool = false,
        cookies: [PreloadCookie] = [],
        windowItems: [WindowInjectionItem] = [],
        bridgeChannels: [BridgeChannel] = [],
        capturesWindowPostMessage: Bool = false,
        customScripts: [PreloadCustomScript] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.cookies = cookies
        self.windowItems = windowItems
        self.bridgeChannels = bridgeChannels
        self.capturesWindowPostMessage = capturesWindowPostMessage
        self.customScripts = customScripts
    }

    var enabledBridgeChannelNames: [String] {
        guard isEnabled else { return [] }
        var names =
            bridgeChannels
            .filter(\.isEnabled)
            .map(\.name)
            .filter { BridgeChannelNameValidator.isValid($0) && !BridgeChannelNameValidator.reservedNames.contains($0) }

        if capturesWindowPostMessage {
            names.append(PreloadBridgeConstants.postMessageCaptureChannel)
        }

        return Array(Set(names)).sorted()
    }

    var enabledSummary: String {
        guard isEnabled else { return "Off" }
        let count =
            cookies.filter(\.isEnabled).count + windowItems.filter(\.isEnabled).count
            + bridgeChannels.filter(\.isEnabled).count + customScripts.filter(\.isEnabled).count
        return count == 0 ? "On" : "\(count) items"
    }

    var localizedEnabledSummary: String {
        guard isEnabled else { return String.app("Off") }
        let count =
            cookies.filter(\.isEnabled).count + windowItems.filter(\.isEnabled).count
            + bridgeChannels.filter(\.isEnabled).count + customScripts.filter(\.isEnabled).count
        return count == 0 ? String.app("On") : String.app("\(count) items")
    }

    static var empty: WebViewPreloadProfile {
        WebViewPreloadProfile()
    }

    static let defaultSavedSetupID = UUID(uuidString: "95B93D1D-F8A0-4B62-9E22-9CE73A1B8F4E")!

    static var defaultSavedSetup: WebViewPreloadProfile {
        WebViewPreloadProfile(
            id: defaultSavedSetupID,
            name: "Default"
        )
    }

    var isLegacyGeneratedNativeBridgeDemoCopy: Bool {
        guard name == "Native Bridge Demo Copy" else { return false }
        let demo = Self.nativeBridgeDemoPreset
        return isEnabled == demo.isEnabled
            && LegacyCookiePayload.list(cookies) == LegacyCookiePayload.list(demo.cookies)
            && LegacyWindowItemPayload.list(windowItems) == LegacyWindowItemPayload.list(demo.windowItems)
            && LegacyBridgeChannelPayload.list(bridgeChannels) == LegacyBridgeChannelPayload.list(demo.bridgeChannels)
            && capturesWindowPostMessage == demo.capturesWindowPostMessage
            && LegacyCustomScriptPayload.list(customScripts) == LegacyCustomScriptPayload.list(demo.customScripts)
    }

    static let nativeBridgeDemoPresetID = UUID(uuidString: "C1E5AC13-F5CC-4CF2-A609-C2E38484B854")!

    static var nativeBridgeDemoPreset: WebViewPreloadProfile {
        WebViewPreloadProfile(
            id: nativeBridgeDemoPresetID,
            name: "Native Bridge Demo",
            isEnabled: true,
            cookies: [
                PreloadCookie(
                    name: "walnut_session",
                    value: "demo-session",
                    domainMode: .currentHost,
                    path: "/",
                    expires: .session,
                    isSecure: true,
                    sameSite: .lax
                )
            ],
            windowItems: [
                WindowInjectionItem(
                    name: "appVersion",
                    kind: .variable,
                    valueKind: .string,
                    value: "1.0.0-demo"
                ),
                WindowInjectionItem(
                    name: "getAuthToken",
                    kind: .functionReturn,
                    valueKind: .string,
                    value: "demo-token"
                ),
            ],
            bridgeChannels: [
                BridgeChannel(
                    name: "request",
                    responseRules: [
                        BridgeResponseRule(
                            name: "getAuthToken",
                            matcher: .typeEquals("getAuthToken"),
                            response: BridgeResponse(
                                target: .postMessage,
                                bodyTemplate: """
                                    {
                                      "id": "{{message.id}}",
                                      "type": "getAuthToken:response",
                                      "payload": {
                                        "token": "demo-token",
                                        "source": "Walnut Preload"
                                      }
                                    }
                                    """
                            ),
                            delayMilliseconds: 300
                        )
                    ]
                )
            ],
            capturesWindowPostMessage: true
        )
    }
}

private struct LegacyCookiePayload: Equatable {
    let isEnabled: Bool
    let name: String
    let value: String
    let domainMode: PreloadCookieDomainMode
    let customDomain: String
    let path: String
    let expires: PreloadCookieExpiration
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSite: PreloadCookieSameSite

    init(_ cookie: PreloadCookie) {
        isEnabled = cookie.isEnabled
        name = cookie.name
        value = cookie.value
        domainMode = cookie.domainMode
        customDomain = cookie.customDomain
        path = cookie.path
        expires = cookie.expires
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        sameSite = cookie.sameSite
    }

    static func list(_ cookies: [PreloadCookie]) -> [Self] {
        cookies.map(Self.init)
    }
}

private struct LegacyWindowItemPayload: Equatable {
    let isEnabled: Bool
    let name: String
    let kind: WindowInjectionKind
    let valueKind: PreloadValueKind
    let value: String

    init(_ item: WindowInjectionItem) {
        isEnabled = item.isEnabled
        name = item.name
        kind = item.kind
        valueKind = item.valueKind
        value = item.value
    }

    static func list(_ items: [WindowInjectionItem]) -> [Self] {
        items.map(Self.init)
    }
}

private struct LegacyBridgeChannelPayload: Equatable {
    let isEnabled: Bool
    let name: String
    let responseRules: [LegacyBridgeResponseRulePayload]

    init(_ channel: BridgeChannel) {
        isEnabled = channel.isEnabled
        name = channel.name
        responseRules = LegacyBridgeResponseRulePayload.list(channel.responseRules)
    }

    static func list(_ channels: [BridgeChannel]) -> [Self] {
        channels.map(Self.init)
    }
}

private struct LegacyBridgeResponseRulePayload: Equatable {
    let isEnabled: Bool
    let name: String
    let matcher: BridgeMatcher
    let response: BridgeResponse
    let delayMilliseconds: Int

    init(_ rule: BridgeResponseRule) {
        isEnabled = rule.isEnabled
        name = rule.name
        matcher = rule.matcher
        response = rule.response
        delayMilliseconds = rule.delayMilliseconds
    }

    static func list(_ rules: [BridgeResponseRule]) -> [Self] {
        rules.map(Self.init)
    }
}

private struct LegacyCustomScriptPayload: Equatable {
    let isEnabled: Bool
    let name: String
    let source: String
    let forMainFrameOnly: Bool

    init(_ script: PreloadCustomScript) {
        isEnabled = script.isEnabled
        name = script.name
        source = script.source
        forMainFrameOnly = script.forMainFrameOnly
    }

    static func list(_ scripts: [PreloadCustomScript]) -> [Self] {
        scripts.map(Self.init)
    }
}

// MARK: - Cookies

struct PreloadCookie: Codable, Equatable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var value: String
    var domainMode: PreloadCookieDomainMode
    var customDomain: String
    var path: String
    var expires: PreloadCookieExpiration
    var isSecure: Bool
    var isHTTPOnly: Bool
    var sameSite: PreloadCookieSameSite

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        name: String = "",
        value: String = "",
        domainMode: PreloadCookieDomainMode = .currentHost,
        customDomain: String = "",
        path: String = "/",
        expires: PreloadCookieExpiration = .session,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        sameSite: PreloadCookieSameSite = .lax
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.value = value
        self.domainMode = domainMode
        self.customDomain = customDomain
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
    }
}

enum PreloadCookieDomainMode: String, Codable, CaseIterable, Equatable {
    case currentHost
    case custom

    var title: String {
        switch self {
        case .currentHost: "Current host"
        case .custom: "Custom domain"
        }
    }

    var localizedTitle: String {
        switch self {
        case .currentHost: String.app("Current host")
        case .custom: String.app("Custom domain")
        }
    }
}

enum PreloadCookieExpiration: String, Codable, CaseIterable, Equatable {
    case session
    case oneHour
    case oneDay
    case sevenDays

    var title: String {
        switch self {
        case .session: "Session"
        case .oneHour: "1 hour"
        case .oneDay: "1 day"
        case .sevenDays: "7 days"
        }
    }

    var localizedTitle: String {
        switch self {
        case .session: String.app("Session")
        case .oneHour: String.app("1 hour")
        case .oneDay: String.app("1 day")
        case .sevenDays: String.app("7 days")
        }
    }

    var expiresDate: Date? {
        switch self {
        case .session: nil
        case .oneHour: Date(timeIntervalSinceNow: 60 * 60)
        case .oneDay: Date(timeIntervalSinceNow: 60 * 60 * 24)
        case .sevenDays: Date(timeIntervalSinceNow: 60 * 60 * 24 * 7)
        }
    }
}

enum PreloadCookieSameSite: String, Codable, CaseIterable, Equatable {
    case lax
    case strict
    case none

    var title: String { rawValue.capitalized }

    var localizedTitle: String {
        switch self {
        case .lax: String.app("Lax")
        case .strict: String.app("Strict")
        case .none: String.app("None")
        }
    }

    var httpCookieString: String {
        switch self {
        case .lax: "Lax"
        case .strict: "Strict"
        case .none: "None"
        }
    }
}

// MARK: - Window Injection

struct WindowInjectionItem: Codable, Equatable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var kind: WindowInjectionKind
    var valueKind: PreloadValueKind
    var value: String

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        name: String = "",
        kind: WindowInjectionKind = .variable,
        valueKind: PreloadValueKind = .string,
        value: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.kind = kind
        self.valueKind = valueKind
        self.value = value
    }
}

enum WindowInjectionKind: String, Codable, CaseIterable, Equatable {
    case variable
    case functionReturn
    case functionBody

    var title: String {
        switch self {
        case .variable: "Variable"
        case .functionReturn: "Function returns value"
        case .functionBody: "Raw function body"
        }
    }

    var localizedTitle: String {
        switch self {
        case .variable: String.app("Variable")
        case .functionReturn: String.app("Function returns value")
        case .functionBody: String.app("Raw function body")
        }
    }
}

enum PreloadValueKind: String, Codable, CaseIterable, Equatable {
    case string
    case json

    var title: String {
        switch self {
        case .string: "String"
        case .json: "JSON"
        }
    }

    var localizedTitle: String {
        switch self {
        case .string: String.app("String")
        case .json: String.app("JSON")
        }
    }
}

// MARK: - Bridge

enum PreloadBridgeConstants {
    static let postMessageCaptureChannel = "winaPostMessage"
}

struct BridgeChannel: Codable, Equatable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var responseRules: [BridgeResponseRule]

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        name: String = "request",
        responseRules: [BridgeResponseRule] = []
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.responseRules = responseRules
    }
}

struct BridgeResponseRule: Codable, Equatable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var matcher: BridgeMatcher
    var response: BridgeResponse
    var delayMilliseconds: Int

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        name: String = "Response",
        matcher: BridgeMatcher = .any,
        response: BridgeResponse = BridgeResponse(),
        delayMilliseconds: Int = 0
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.matcher = matcher
        self.response = response
        self.delayMilliseconds = delayMilliseconds
    }
}

enum BridgeMatcher: Codable, Equatable {
    case any
    case typeEquals(String)
    case jsonPathEquals(path: String, value: String)
}

struct BridgeResponse: Codable, Equatable {
    var target: BridgeResponseTarget
    var bodyTemplate: String
    var eventName: String
    var callbackName: String
    var customJavaScript: String

    init(
        target: BridgeResponseTarget = .postMessage,
        bodyTemplate: String = "{\n  \"ok\": true\n}",
        eventName: String = "nativeMessage",
        callbackName: String = "onNativeResponse",
        customJavaScript: String = ""
    ) {
        self.target = target
        self.bodyTemplate = bodyTemplate
        self.eventName = eventName
        self.callbackName = callbackName
        self.customJavaScript = customJavaScript
    }
}

enum BridgeResponseTarget: String, Codable, CaseIterable, Equatable {
    case postMessage
    case customEvent
    case callback
    case customJavaScript

    var title: String {
        switch self {
        case .postMessage: "window.postMessage"
        case .customEvent: "CustomEvent"
        case .callback: "Callback function"
        case .customJavaScript: "Custom JS"
        }
    }

    var localizedTitle: String {
        switch self {
        case .postMessage: String.app("window.postMessage")
        case .customEvent: String.app("CustomEvent")
        case .callback: String.app("Callback function")
        case .customJavaScript: String.app("Custom JS")
        }
    }
}

// MARK: - Custom Script

struct PreloadCustomScript: Codable, Equatable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var source: String
    var forMainFrameOnly: Bool

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        name: String = "Custom Script",
        source: String = "",
        forMainFrameOnly: Bool = false
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.source = source
        self.forMainFrameOnly = forMainFrameOnly
    }
}
