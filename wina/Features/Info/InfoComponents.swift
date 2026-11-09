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
    let name: String
    let items: [CapabilityItem]
}

struct CapabilityItem: Identifiable {
    let id = UUID()
    let label: String
    let supported: Bool
    var info: LocalizedStringKey?
    var unavailable = false
    var icon: String?
    var iconColor: Color?
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
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
            Text(value)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Capability Row

struct CapabilityRow: View {
    let label: String
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
    let label: String
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
    let label: String
    let support: CodecSupport

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: support.icon)
                .foregroundStyle(support.color)
        }
    }
}

// MARK: - Active Setting Row

struct ActiveSettingRow: View {
    let label: String
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
    let label: String
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

    private var statusText: String {
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
