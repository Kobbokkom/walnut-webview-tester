import Foundation

// MARK: - User Agent Preset Models

enum UserAgentPlatform: String, CaseIterable, Identifiable {
    case desktop = "Desktop"
    case mobile = "Mobile"
    case tablet = "Tablet"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .mobile: return "iphone"
        case .tablet: return "ipad"
        }
    }
}

enum UserAgentBrowser: String, CaseIterable, Identifiable {
    case chrome = "Chrome"
    case safari = "Safari"
    case firefox = "Firefox"
    case edge = "Edge"
    case opera = "Opera"
    case brave = "Brave"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chrome: return "globe"
        case .safari: return "safari"
        case .firefox: return "flame"
        case .edge: return "e.circle"
        case .opera: return "o.circle"
        case .brave: return "shield"
        }
    }

    var color: String {
        switch self {
        case .chrome: return "#4285F4"
        case .safari: return "#006CFF"
        case .firefox: return "#FF7139"
        case .edge: return "#0078D7"
        case .opera: return "#FF1B2D"
        case .brave: return "#FB542B"
        }
    }
}

enum UserAgentOS: String, CaseIterable, Identifiable {
    case windows = "Windows"
    case macOS = "macOS"
    case linux = "Linux"
    case iOS = "iOS"
    case android = "Android"
    case iPadOS = "iPadOS"

    var id: String { rawValue }
}

struct UserAgentPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let browser: UserAgentBrowser
    let platform: UserAgentPlatform
    let os: UserAgentOS
    let userAgent: String
    let description: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: UserAgentPreset, rhs: UserAgentPreset) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Preset Data (2025 Latest)

struct UserAgentPresets {

    // MARK: - Chrome Presets

    static let chromeDesktopWindows = UserAgentPreset(
        name: "Chrome Windows",
        browser: .chrome,
        platform: .desktop,
        os: .windows,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        description: "Chrome 131 on Windows 10/11"
    )

    static let chromeDesktopMac = UserAgentPreset(
        name: "Chrome macOS",
        browser: .chrome,
        platform: .desktop,
        os: .macOS,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        description: "Chrome 131 on macOS"
    )

    static let chromeDesktopLinux = UserAgentPreset(
        name: "Chrome Linux",
        browser: .chrome,
        platform: .desktop,
        os: .linux,
        userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        description: "Chrome 131 on Linux"
    )

    static let chromeMobileAndroid = UserAgentPreset(
        name: "Chrome Android",
        browser: .chrome,
        platform: .mobile,
        os: .android,
        userAgent: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
        description: "Chrome 131 on Android (Reduced UA)"
    )

    static let chromeMobileiOS = UserAgentPreset(
        name: "Chrome iOS",
        browser: .chrome,
        platform: .mobile,
        os: .iOS,
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.0.0 Mobile/15E148 Safari/604.1",
        description: "Chrome 131 on iOS 18"
    )

    static let chromeTabletAndroid = UserAgentPreset(
        name: "Chrome Android Tablet",
        browser: .chrome,
        platform: .tablet,
        os: .android,
        userAgent: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        description: "Chrome 131 on Android Tablet"
    )

    static let chromeTabletiPad = UserAgentPreset(
        name: "Chrome iPad",
        browser: .chrome,
        platform: .tablet,
        os: .iPadOS,
        userAgent: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.0.0 Mobile/15E148 Safari/604.1",
        description: "Chrome 131 on iPadOS 18"
    )

    // MARK: - Safari Presets

    static let safariDesktopMac = UserAgentPreset(
        name: "Safari macOS",
        browser: .safari,
        platform: .desktop,
        os: .macOS,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
        description: "Safari 18.2 on macOS"
    )

    static let safariMobileiPhone = UserAgentPreset(
        name: "Safari iPhone",
        browser: .safari,
        platform: .mobile,
        os: .iOS,
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
        description: "Safari 18.2 on iOS 18"
    )

    static let safariTabletiPad = UserAgentPreset(
        name: "Safari iPad",
        browser: .safari,
        platform: .tablet,
        os: .iPadOS,
        userAgent: "Mozilla/5.0 (iPad; CPU OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
        description: "Safari 18.2 on iPadOS 18"
    )

    // MARK: - Firefox Presets

    static let firefoxDesktopWindows = UserAgentPreset(
        name: "Firefox Windows",
        browser: .firefox,
        platform: .desktop,
        os: .windows,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0",
        description: "Firefox 133 on Windows"
    )

    static let firefoxDesktopMac = UserAgentPreset(
        name: "Firefox macOS",
        browser: .firefox,
        platform: .desktop,
        os: .macOS,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0",
        description: "Firefox 133 on macOS"
    )

    static let firefoxDesktopLinux = UserAgentPreset(
        name: "Firefox Linux",
        browser: .firefox,
        platform: .desktop,
        os: .linux,
        userAgent: "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0",
        description: "Firefox 133 on Linux"
    )

    static let firefoxMobileAndroid = UserAgentPreset(
        name: "Firefox Android",
        browser: .firefox,
        platform: .mobile,
        os: .android,
        userAgent: "Mozilla/5.0 (Android 15; Mobile; rv:133.0) Gecko/133.0 Firefox/133.0",
        description: "Firefox 133 on Android"
    )

    static let firefoxMobileiOS = UserAgentPreset(
        name: "Firefox iOS",
        browser: .firefox,
        platform: .mobile,
        os: .iOS,
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/133.0 Mobile/15E148 Safari/605.1.15",
        description: "Firefox 133 on iOS"
    )

    // MARK: - Edge Presets

    static let edgeDesktopWindows = UserAgentPreset(
        name: "Edge Windows",
        browser: .edge,
        platform: .desktop,
        os: .windows,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
        description: "Edge 131 on Windows"
    )

    static let edgeDesktopMac = UserAgentPreset(
        name: "Edge macOS",
        browser: .edge,
        platform: .desktop,
        os: .macOS,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
        description: "Edge 131 on macOS"
    )

    static let edgeMobileAndroid = UserAgentPreset(
        name: "Edge Android",
        browser: .edge,
        platform: .mobile,
        os: .android,
        userAgent: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36 EdgA/131.0.0.0",
        description: "Edge 131 on Android"
    )

    static let edgeMobileiOS = UserAgentPreset(
        name: "Edge iOS",
        browser: .edge,
        platform: .mobile,
        os: .iOS,
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 EdgiOS/131.0.0.0 Mobile/15E148 Safari/604.1",
        description: "Edge 131 on iOS"
    )

    // MARK: - Opera Presets

    static let operaDesktopWindows = UserAgentPreset(
        name: "Opera Windows",
        browser: .opera,
        platform: .desktop,
        os: .windows,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 OPR/116.0.0.0",
        description: "Opera 116 on Windows"
    )

    static let operaDesktopMac = UserAgentPreset(
        name: "Opera macOS",
        browser: .opera,
        platform: .desktop,
        os: .macOS,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 OPR/116.0.0.0",
        description: "Opera 116 on macOS"
    )

    static let operaMobileAndroid = UserAgentPreset(
        name: "Opera Android",
        browser: .opera,
        platform: .mobile,
        os: .android,
        userAgent: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36 OPR/85.0.0.0",
        description: "Opera Mobile on Android"
    )

    // MARK: - Brave Presets

    static let braveDesktopWindows = UserAgentPreset(
        name: "Brave Windows",
        browser: .brave,
        platform: .desktop,
        os: .windows,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        description: "Brave on Windows (Chrome-like UA)"
    )

    static let braveDesktopMac = UserAgentPreset(
        name: "Brave macOS",
        browser: .brave,
        platform: .desktop,
        os: .macOS,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        description: "Brave on macOS (Chrome-like UA)"
    )

    // MARK: - Bot/Crawler Presets

    static let googlebot = UserAgentPreset(
        name: "Googlebot",
        browser: .chrome,
        platform: .desktop,
        os: .linux,
        userAgent: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        description: "Google Search Crawler"
    )

    static let googlebotMobile = UserAgentPreset(
        name: "Googlebot Mobile",
        browser: .chrome,
        platform: .mobile,
        os: .android,
        userAgent: "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        description: "Google Mobile Search Crawler"
    )

    static let bingbot = UserAgentPreset(
        name: "Bingbot",
        browser: .edge,
        platform: .desktop,
        os: .windows,
        userAgent: "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
        description: "Bing Search Crawler"
    )

    // MARK: - All Presets

    static let allPresets: [UserAgentPreset] = [
        // Chrome
        chromeDesktopWindows,
        chromeDesktopMac,
        chromeDesktopLinux,
        chromeMobileAndroid,
        chromeMobileiOS,
        chromeTabletAndroid,
        chromeTabletiPad,
        // Safari
        safariDesktopMac,
        safariMobileiPhone,
        safariTabletiPad,
        // Firefox
        firefoxDesktopWindows,
        firefoxDesktopMac,
        firefoxDesktopLinux,
        firefoxMobileAndroid,
        firefoxMobileiOS,
        // Edge
        edgeDesktopWindows,
        edgeDesktopMac,
        edgeMobileAndroid,
        edgeMobileiOS,
        // Opera
        operaDesktopWindows,
        operaDesktopMac,
        operaMobileAndroid,
        // Brave
        braveDesktopWindows,
        braveDesktopMac,
        // Bots
        googlebot,
        googlebotMobile,
        bingbot,
    ]

    // MARK: - Filtering

    static func presets(for browser: UserAgentBrowser) -> [UserAgentPreset] {
        allPresets.filter { $0.browser == browser }
    }

    static func presets(for platform: UserAgentPlatform) -> [UserAgentPreset] {
        allPresets.filter { $0.platform == platform }
    }

    static func presets(for browser: UserAgentBrowser, platform: UserAgentPlatform) -> [UserAgentPreset] {
        allPresets.filter { $0.browser == browser && $0.platform == platform }
    }

    static func search(_ query: String, browser: UserAgentBrowser? = nil) -> [UserAgentPreset] {
        let lowercasedQuery = query.lowercased()
        return allPresets.filter {
            (browser == nil || $0.browser == browser) && (lowercasedQuery.isEmpty ||
            $0.name.lowercased().contains(lowercasedQuery) ||
            $0.description.lowercased().contains(lowercasedQuery) ||
            $0.userAgent.lowercased().contains(lowercasedQuery) ||
            $0.browser.rawValue.lowercased().contains(lowercasedQuery) ||
            $0.os.rawValue.lowercased().contains(lowercasedQuery))
        }
    }
}
