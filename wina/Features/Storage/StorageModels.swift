import SwiftUI

// MARK: - Storage Item Model

struct StorageItem: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
    let storageType: StorageType
    var cookieMetadata: CookieMetadata?
    var origin: String?

    enum StorageType: String, CaseIterable {
        case localStorage
        case sessionStorage
        case cookies

        var icon: String {
            switch self {
            case .localStorage: return "internaldrive"
            case .sessionStorage: return "clock"
            case .cookies: return "birthday.cake"
            }
        }

        var label: String {
            switch self {
            case .localStorage: return "Local"
            case .sessionStorage: return "Session"
            case .cookies: return "Cookies"
            }
        }

        var sortOrder: Int {
            switch self {
            case .localStorage: return 0
            case .sessionStorage: return 1
            case .cookies: return 2
            }
        }

        var tintColor: Color {
            switch self {
            case .localStorage: return .blue
            case .sessionStorage: return .orange
            case .cookies: return .green
            }
        }
    }

    static func == (lhs: StorageItem, rhs: StorageItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.key == rhs.key &&
        lhs.value == rhs.value &&
        lhs.storageType == rhs.storageType &&
        lhs.cookieMetadata == rhs.cookieMetadata &&
        lhs.origin == rhs.origin
    }
}

// MARK: - Storage Value Type

enum StorageValueType {
    case json, number, bool, string, empty

    static func detect(from value: String) -> StorageValueType {
        if value.isEmpty { return .empty }
        if JsonParser.isValidJson(value) { return .json }
        if value.lowercased() == "true" || value.lowercased() == "false" { return .bool }
        if Double(value) != nil { return .number }
        return .string
    }

    var color: Color {
        switch self {
        case .json: return .purple
        case .number: return .blue
        case .bool: return .green
        case .string: return .gray
        case .empty: return .gray.opacity(0.5)
        }
    }

    var badge: TypeBadge? {
        switch self {
        case .json:
            return TypeBadge(text: "JSON", color: .purple, icon: "curlybraces")
        case .number:
            return TypeBadge(text: "Number", color: .blue, icon: "number")
        case .bool:
            return TypeBadge(text: "Boolean", color: .green, icon: "checkmark")
        case .string:
            return TypeBadge(text: "Text", color: .gray, icon: "textformat")
        case .empty:
            return nil
        }
    }

    var label: String {
        switch self {
        case .json: return "JSON"
        case .number: return "Number"
        case .bool: return "Boolean"
        case .string: return "Text"
        case .empty: return "Empty"
        }
    }
}
