import SwiftUI

// MARK: - Storage Item Model

struct StorageCookieAddScope {
    let domain: String?
    let path: String

    static func documentPath(for pageURL: URL) -> String {
        let path = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        return path.isEmpty ? "/" : path
    }

    static func defaultPath(for documentPath: String) -> String {
        guard let slash = documentPath.lastIndex(of: "/"), slash != documentPath.startIndex else { return "/" }
        return String(documentPath[..<slash])
    }
}

struct StorageCookieAddKey: Hashable {
    let store: ObjectIdentifier
    let name: String
    let domain: String
    let path: String

    func matches(_ cookie: HTTPCookie) -> Bool {
        cookie.name == name && cookie.path == path && [domain, ".\(domain)"].contains(cookie.domain.lowercased())
    }
}

struct StorageShareContent: Identifiable {
    let id = UUID()
    let content: String
}

struct StorageScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}

struct StorageEditorTarget: Identifiable {
    enum Action {
        case edit(StorageItem)
        case add(StorageItem.StorageType, URL)
    }

    let id = UUID()
    let action: Action
}

enum StorageExporter {
    static func heading(for type: StorageItem.StorageType?) -> String {
        let title = type.map { "\($0.label) Storage Export" } ?? "All Storage Export"
        return "# \(title)\n# \(Date().formatted())\n\n"
    }

    static func line(_ item: StorageItem, includeType: Bool, decode: Bool = false) -> String {
        let prefix = includeType ? "[\(item.storageType.label)] " : ""
        let value = decode ? item.value.removingPercentEncoding ?? item.value : item.value
        return "\(prefix)\(item.key) = \(value)\n"
    }
}

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
            case .localStorage: return String(localized: "Local")
            case .sessionStorage: return String(localized: "Session")
            case .cookies: return String(localized: "Cookies")
            }
        }

        var emptyTitle: LocalizedStringKey {
            switch self {
            case .localStorage: return "No local storage data"
            case .sessionStorage: return "No session storage data"
            case .cookies: return "No cookies data"
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
            return TypeBadge(text: String(localized: "Number"), color: .blue, icon: "number")
        case .bool:
            return TypeBadge(text: String(localized: "Boolean"), color: .green, icon: "checkmark")
        case .string:
            return TypeBadge(text: String(localized: "Text"), color: .gray, icon: "textformat")
        case .empty:
            return nil
        }
    }

    var label: String {
        switch self {
        case .json: return "JSON"
        case .number: return String(localized: "Number")
        case .bool: return String(localized: "Boolean")
        case .string: return String(localized: "Text")
        case .empty: return String(localized: "Empty")
        }
    }
}
