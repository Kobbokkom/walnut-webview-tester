//
//  DeviceUtilities.swift
//  wina
//
//  Shared device and settings utility functions
//

import SwiftUI

// MARK: - UIDevice Extension

extension UIDevice {
    /// Returns true if the current device is an iPad
    var isIPad: Bool {
        userInterfaceIdiom == .pad
    }
}

// The presenting WebView's available size must survive presentation into a settings sheet.
private struct WebViewContainerSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    var webViewContainerSize: CGSize {
        get { self[WebViewContainerSizeKey.self] }
        set { self[WebViewContainerSizeKey.self] = newValue }
    }
}

// MARK: - Settings Formatters

enum SettingsFormatter {
    /// Formats content mode integer to display string
    static func contentModeText(_ mode: Int) -> String {
        switch mode {
        case 1: return "Mobile"
        case 2: return "Desktop"
        default: return "Recommended"
        }
    }

    /// Formats data detector flags to display string
    static func activeDataDetectors(
        phone: Bool,
        links: Bool,
        address: Bool,
        calendar: Bool
    ) -> String {
        var detectors: [String] = []
        if phone { detectors.append("Phone") }
        if links { detectors.append("Links") }
        if address { detectors.append("Address") }
        if calendar { detectors.append("Calendar") }
        return detectors.isEmpty ? "None" : detectors.joined(separator: ", ")
    }

    /// Formats boolean to "Enabled" or "Disabled"
    static func enabledStatus(_ enabled: Bool) -> String {
        enabled ? "Enabled" : "Disabled"
    }

    /// Formats Safari dismiss button style integer to display string
    static func dismissButtonStyleText(_ style: Int) -> String {
        switch style {
        case 1: return "Close"
        case 2: return "Cancel"
        default: return "Done"
        }
    }
}

// MARK: - Byte Formatter

enum ByteFormatter {
    /// Formats bytes to human-readable string (KB, MB)
    static func format(_ bytes: Int) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        }
        return "\(bytes) B"
    }
}

private struct CloseDevToolsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var closeDevTools: (() -> Void)? {
        get { self[CloseDevToolsKey.self] }
        set { self[CloseDevToolsKey.self] = newValue }
    }
}
