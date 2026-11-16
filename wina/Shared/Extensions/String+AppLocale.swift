import Foundation

extension Locale {
    /// The in-app language chosen in App Settings (`appLanguage`), or the system locale.
    static var app: Locale {
        let identifier = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return identifier.isEmpty ? .current : Locale(identifier: identifier)
    }
}

extension String {
    /// Localizes `key` in the in-app language. `String(localized:)` alone follows the system language,
    /// while SwiftUI text follows the app's `\.locale` override, so non-view text uses this instead.
    static func app(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: .app))
    }

    /// Resolves a stored resource (for example a model's title) in the in-app language.
    static func app(resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = .app
        return String(localized: resource)
    }
}
