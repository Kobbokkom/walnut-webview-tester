import AVFoundation
import CoreLocation
import Foundation
import UIKit

extension AgentSettings {
    private static let location = CLLocationManager()

    static func diagnostics(_ section: String, navigator: WebViewNavigator?) async throws -> Any {
        switch section {
        case "device":
            var device = try AgentTool.json(await DeviceInfo.load()) as? [String: Any] ?? [:]
            device.removeValue(forKey: "hostName")
            return ["source": "device", "data": device]
        case "benchmark":
            let benchmark = await PerformanceInfo.load { _ in }
            return ["source": "temporary_benchmark_webview", "data": try AgentTool.json(benchmark)]
        case "permissions": return permissionStates()
        case "safari": return safariDiagnostics()
        default: break
        }
        let shared = SharedInfoWebView(navigator: navigator)
        let isLive = shared.isUsingLiveWebView
        let initialDocument = navigator?.documentID
        let data: Any
        switch section {
        case "api", "browser": data = try AgentTool.json(await WebViewInfo.load(using: shared) { _ in })
        case "codecs": data = try AgentTool.json(await MediaCodecInfo.load(using: shared) { _ in })
        case "display": data = try AgentTool.json(await DisplayInfo.load(using: shared) { _ in })
        case "accessibility": data = try AgentTool.json(await AccessibilityInfo.load(using: shared) { _ in })
        default: throw AgentError("Unknown Info diagnostics section: \(section).")
        }
        try Task.checkCancellation()
        if isLive, navigator?.isAttached != true || initialDocument != navigator?.documentID {
            throw AgentError("The active WKWebView document changed. Try again.")
        }
        return ["source": isLive ? "live_wkwebview" : "temporary_wkwebview", "data": data]
    }

    static func permissions(_ input: AgentSettingsInput) async throws -> Any {
        switch try input.string("action") {
        case "status": return permissionStates()
        case "request": break
        default: throw AgentError("Unknown permission action.")
        }
        let permission = try input.string("permission")
        guard permissionStates()[permission] != nil else { throw AgentError("Unknown permission: \(permission).") }
        try await input.confirm("Let Walnut request \(permission) access or open iOS Settings?")
        if permissionStates()[permission] == "not_requested" {
            switch permission {
            case "camera": AVCaptureDevice.requestAccess(for: .video) { _ in }
            case "microphone": AVCaptureDevice.requestAccess(for: .audio) { _ in }
            case "location": location.requestWhenInUseAuthorization()
            default: break
            }
            return ["action": "requested", "permission": permission]
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            throw AgentError("iOS Settings is unavailable.")
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return ["action": "opened_ios_settings", "permission": permission]
    }

    static func callbacks(_ input: AgentSettingsInput) async throws -> Any {
        let manager = CallbackTestManager.shared
        switch try input.string("action") {
        case "test_page": return ["url": CallbackTestManager.testPageURL.absoluteString, "scheme": CallbackTestManager.urlScheme]
        case "clear":
            try await input.confirm("Clear the last URL scheme callback in Walnut?")
            manager.clearHistory()
            return ["cleared": true]
        case "get":
            let raw = try input.flag("raw")
            if raw { try await input.confirm("Share the latest callback URL and its parameter values with the paired Mac?") }
            guard let url = manager.lastCallbackURL else { return ["received": false] }
            let timestamp = manager.lastCallbackTime?.formatted(.iso8601) ?? ""
            var result: [String: Any] = ["received": true, "scheme": url.scheme ?? "", "host": url.host ?? "", "receivedAt": timestamp]
            result["parameterCount"] = manager.callbackParameters.count
            if raw {
                result["url"] = url.absoluteString
                result["parameters"] = manager.callbackParameters.map { item -> [String: Any] in
                    ["name": item.name, "value": item.value.map { $0 as Any } ?? NSNull()]
                }
            }
            return result
        default: throw AgentError("Unknown callback action.")
        }
    }

    static func bookmarks(_ input: AgentSettingsInput) async throws -> Any {
        let storage = URLStorageManager.shared
        let action = try input.string("action")
        switch action {
        case "list", "history":
            return try await savedURLPage(input, action: action) {
                action == "list" ? storage.bookmarks : storage.history
            }
        case "clear_history":
            try await input.confirm("Clear all Walnut URL history on this iPhone?")
            storage.clearHistory()
        case "add", "remove", "remove_history":
            let url = try input.string("url").trimmingCharacters(in: .whitespacesAndNewlines)
            if action == "add" {
                let normalized = URLValidator.normalizeURL(url)
                guard URLValidator.isValidURL(url), let parsed = URL(string: normalized),
                      ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.user == nil, parsed.password == nil else {
                    throw AgentError("Provide a valid HTTP or HTTPS bookmark without embedded credentials.")
                }
            }
            try await input.confirm("Update Walnut's saved \(action == "remove_history" ? "history" : "bookmarks") on this iPhone?")
            switch action {
            case "add": storage.addBookmark(url)
            case "remove": storage.removeBookmark(url)
            default: storage.removeFromHistory(url)
            }
        default: throw AgentError("Unknown bookmark action.")
        }
        return ["action": action, "bookmarkCount": storage.bookmarks.count, "historyCount": storage.history.count]
    }

    static func savedURLPage(
        _ input: AgentSettingsInput, action: String, collection: () -> [String]
    ) async throws -> [String: Any] {
        let raw = try input.flag("raw")
        let query = try input.string("query", default: "", limit: 256)
        let pagination = AgentDevInput(values: input.arguments)
        let offset = try pagination.int("offset", default: 0, range: 0...Int.max)
        let limit = try pagination.int("limit", default: 50, range: 1...100)
        if raw { try await input.confirm("Share full saved Walnut \(action == "history" ? "history" : "bookmark") URLs with the paired Mac?") }
        let urls = collection()
        let visibleURLs = raw ? urls : urls.map(safeOrigin)
        let matching = visibleURLs.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        let page = Array(matching.dropFirst(offset).prefix(limit))
        var result: [String: Any] = ["urls": page, "total": matching.count, "redacted": !raw]
        let nextOffset = offset + page.count
        if nextOffset < matching.count { result["nextOffset"] = nextOffset }
        return result
    }

    private static func safeOrigin(_ raw: String) -> String {
        guard let components = URLComponents(string: URLValidator.normalizeURL(raw)), let host = components.host else { return "" }
        var origin = URLComponents()
        origin.scheme = components.scheme
        origin.host = host
        origin.port = components.port
        return origin.string ?? ""
    }

    private static func permissionStates() -> [String: String] {
        let locationStatus: String
        switch location.authorizationStatus {
        case .notDetermined: locationStatus = "not_requested"
        case .restricted: locationStatus = "restricted"
        case .denied: locationStatus = "denied"
        case .authorizedAlways: locationStatus = "always"
        case .authorizedWhenInUse: locationStatus = "when_in_use"
        @unknown default: locationStatus = "unknown"
        }
        return [
            "camera": permissionState(for: .video),
            "microphone": permissionState(for: .audio),
            "location": locationStatus,
        ]
    }

    private static func permissionState(for media: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .notDetermined: return "not_requested"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "granted"
        @unknown default: return "unknown"
        }
    }

    private static func safariDiagnostics() -> [String: Any] {
        let settings = AgentBrowserSettings.shared
        return [
            "source": "safariviewcontroller_public_api",
            "presentation": "full_screen",
            "settings": Dictionary(uniqueKeysWithValues: AgentSetting.entries.filter { $0.group == "safari" }.map { ($0.key, settings.effectiveValue(for: $0)) }),
            "contentInspection": false,
            "hostAccessibleWebsiteData": false,
            "nativeControls": ["Reader Mode", "AutoFill", "Fraudulent Website Warning", "Content Blockers"],
            "delegateEvents": ["initial_load", "initial_redirect", "dismissed"],
            "appearanceTintsAvailable": !ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 26, minorVersion: 0, patchVersion: 0)),
        ]
    }
}
