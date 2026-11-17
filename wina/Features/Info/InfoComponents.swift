//
//  InfoComponents.swift
//  wina
//

import AVFoundation
import CoreLocation
import SwiftUI

// MARK: - Info Category Row

struct InfoCategoryRow: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Info Search Item

struct InfoSearchItem: Identifiable {
    let id = UUID()
    let category: String
    let label: String
    let value: String
    var info: LocalizedStringKey?
    var linkToPerformance = false
}

// MARK: - Capability Data Models

struct CapabilitySection: Identifiable {
    let id = UUID()
    let name: LocalizedStringKey
    let items: [CapabilityItem]
}

struct CapabilityItem: Identifiable {
    let id = UUID()
    let label: LocalizedStringKey
    let supported: Bool
    var info: LocalizedStringKey?
    var unavailable = false
    var icon: String?
    var iconColor: Color?
}

// MARK: - Info Row

struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String
    var info: LocalizedStringKey?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            if let info {
                InfoPopoverButton(text: info, iconColor: .tertiary)
            }
            Spacer()
            Text(Self.displayValue(value))
                .textSelection(.enabled)
        }
    }

    /// Status words stay English in the data sent to the Mac agent and are translated only on screen.
    static func displayValue(_ value: String) -> String {
        switch value {
        case "Unknown": String.app("Unknown")
        case "N/A": String.app("N/A")
        case "Nominal": String.app("Nominal")
        case "Fair": String.app("Fair")
        case "Serious": String.app("Serious")
        case "Critical": String.app("Critical")
        case "Yes": String.app("Yes")
        case "No": String.app("No")
        case "None": String.app("None")
        case "Enabled": String.app("Enabled")
        case "Disabled": String.app("Disabled")
        case "Supported": String.app("Supported")
        case "On": String.app("On")
        case "Off": String.app("Off")
        case "Online": String.app("Online")
        case "Offline": String.app("Offline")
        case "Granted": String.app("Granted")
        case "Denied": String.app("Denied")
        default: value
        }
    }
}

// MARK: - Capability Row

struct CapabilityRow: View {
    let label: LocalizedStringKey
    let supported: Bool
    var info: LocalizedStringKey?
    var unavailable = false  // WebKit policy: never supported
    var icon: String?
    var iconColor: Color?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(unavailable ? .secondary : .primary)
            if let info {
                InfoPopoverButton(text: info)
            }
            Spacer()
            if let icon, supported, !unavailable {
                Image(systemName: icon)
                    .foregroundStyle(iconColor ?? .secondary)
            }
            if unavailable {
                Text("N/A")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(supported ? .green : .red)
            }
        }
    }
}

// MARK: - User Agent Text

struct UserAgentText: View {
    let userAgent: String

    var body: some View {
        Text(formattedUserAgent)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
    }

    private var formattedUserAgent: AttributedString {
        // Pattern: key/value or parenthesized content
        let patterns: [(pattern: String, color: Color)] = [
            ("Mozilla/[\\d.]+", .blue),
            ("AppleWebKit/[\\d.]+", .orange),
            ("Version/[\\d.]+", .purple),
            ("Mobile/[\\w]+", .green),
            ("Safari/[\\d.]+", .pink),
            ("\\([^)]+\\)", .secondary),
        ]

        var text = userAgent

        // Add line breaks at major separators
        text = text.replacingOccurrences(of: ") ", with: ")\n")

        var attributed = AttributedString(text)

        for (pattern, color) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsRange = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: nsRange) {
                    if let range = Range(match.range, in: text),
                       let attrRange = Range(range, in: attributed)
                    {
                        attributed[attrRange].foregroundColor = color
                    }
                }
            }
        }

        return attributed
    }
}

// MARK: - Benchmark Row

struct BenchmarkRow: View {
    let label: LocalizedStringKey
    let ops: String
    var info: LocalizedStringKey?

    var body: some View {
        HStack {
            Text(label)
            if let info {
                InfoPopoverButton(text: info, iconColor: .tertiary)
            }
            Spacer()
            Text(ops)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Codec Support

enum CodecSupport: String, Encodable {
    case probably = "probably"
    case maybe = "maybe"
    case none = ""

    var icon: String {
        switch self {
        case .probably: return "checkmark.circle.fill"
        case .maybe: return "questionmark.circle.fill"
        case .none: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .probably: return .green
        case .maybe: return .orange
        case .none: return .red
        }
    }

    /// English catalog key; localized when displayed (see `InfoView.searchResultRow`).
    var displayValue: String {
        switch self {
        case .probably: return "Supported"
        case .maybe: return "Maybe"
        case .none: return "Not Supported"
        }
    }
}

// MARK: - Codec Row

struct CodecRow: View {
    let label: String  // codec/container names are technical, not localized
    let support: CodecSupport

    var body: some View {
        HStack {
            Text(verbatim: label)
            Spacer()
            Image(systemName: support.icon)
                .foregroundStyle(support.color)
        }
    }
}

// MARK: - Active Setting Row

struct ActiveSettingRow: View {
    let label: LocalizedStringKey
    let enabled: Bool
    var info: LocalizedStringKey?
    var unavailable = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(unavailable ? .secondary : .primary)
            if unavailable {
                Text("(iPad only)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let info {
                InfoPopoverButton(text: info)
            }
            Spacer()
            if unavailable {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(enabled ? .green : .secondary)
            }
        }
    }
}

// MARK: - Permission Status Row

struct PermissionStatusRow: View {
    let label: LocalizedStringKey
    let status: Any
    var info: LocalizedStringKey?

    var body: some View {
        HStack {
            Text(label)
            if let info {
                InfoPopoverButton(text: info)
            }
            Spacer()
            Text(statusText)
                .foregroundStyle(statusColor)
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
        }
    }

    private var statusText: LocalizedStringKey {
        if let avStatus = status as? AVAuthorizationStatus {
            switch avStatus {
            case .authorized: return "Granted"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            case .notDetermined: return "Not Asked"
            @unknown default: return "Unknown"
            }
        } else if let clStatus = status as? CLAuthorizationStatus {
            switch clStatus {
            case .authorizedWhenInUse, .authorizedAlways: return "Granted"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            case .notDetermined: return "Not Asked"
            @unknown default: return "Unknown"
            }
        }
        return "Unknown"
    }

    private var statusColor: Color {
        if let avStatus = status as? AVAuthorizationStatus {
            return avStatus == .authorized ? .green : .secondary
        } else if let clStatus = status as? CLAuthorizationStatus {
            return (clStatus == .authorizedWhenInUse || clStatus == .authorizedAlways) ? .green : .secondary
        }
        return .secondary
    }

    private var statusIcon: String {
        if let avStatus = status as? AVAuthorizationStatus {
            return avStatus == .authorized ? "checkmark.circle.fill" : "xmark.circle.fill"
        } else if let clStatus = status as? CLAuthorizationStatus {
            return (clStatus == .authorizedWhenInUse || clStatus == .authorizedAlways) ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        return "questionmark.circle.fill"
    }
}
