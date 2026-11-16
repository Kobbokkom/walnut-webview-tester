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
    static func validMinimumFontSize(_ size: Double) -> Double {
        size >= 0 && size < Double(Int.max) ? size : 0
    }

    static func minimumFontSizeText(_ size: Double) -> String {
        let validSize = validMinimumFontSize(size)
        return validSize == 0 ? String.app("Default") : "\(Int(validSize)) pt"
    }

    /// Formats content mode integer to display string
    static func contentModeText(_ mode: Int) -> String {
        switch mode {
        case 1: return String.app("Mobile")
        case 2: return String.app("Desktop")
        default: return String.app("Recommended")
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
        if phone { detectors.append(String.app("Phone")) }
        if links { detectors.append(String.app("Links")) }
        if address { detectors.append(String.app("Address")) }
        if calendar { detectors.append(String.app("Calendar")) }
        return detectors.isEmpty ? String.app("None") : detectors.joined(separator: ", ")
    }

    /// Formats boolean to "Enabled" or "Disabled" in the app language
    static func enabledStatus(_ enabled: Bool) -> String {
        enabled ? String.app("Enabled") : String.app("Disabled")
    }

    /// Formats Safari dismiss button style integer to display string
    static func dismissButtonStyleText(_ style: Int) -> String {
        switch style {
        case 1: return String.app("Close")
        case 2: return String.app("Cancel")
        default: return String.app("Done")
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
