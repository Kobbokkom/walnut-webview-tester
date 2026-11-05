import Foundation

enum SettingsSearchCatalog {
    static func items(for screen: SettingsSearchScreen) -> [SettingsSearchItem] {
        switch screen {
        case .settings: configuration + live + loaded
        case .loaded: loaded
        case .safari: []
        case .app: app
        case .configuration: configuration
        case .live: live
        case .emulation: emulation
        case .permissions: permissions
        case .safariConfiguration: safariConfiguration
        case .menu:
            DevToolsMenuItem.allCases.map {
                SettingsSearchItem("toolbar." + $0.rawValue, $0.titleKey.key, "Toolbar", $0.descriptionKey.key)
            } + AppBarMenuItem.allCases.map {
                SettingsSearchItem("appBar." + $0.rawValue, $0.titleKey.key, "App Bar", $0.descriptionKey.key)
            }
        case .safariMenu:
            SafariVCToolbarMenuItem.allCases.map {
                SettingsSearchItem("toolbar." + $0.rawValue, $0.titleKey.key, "Toolbar", $0.descriptionKey.key)
            } + SafariVCAppBarMenuItem.allCases.map {
                SettingsSearchItem("appBar." + $0.rawValue, $0.titleKey.key, "App Bar", $0.descriptionKey.key)
            }
        }
    }

    private static let loaded: [SettingsSearchItem] = [
        SettingsSearchItem("erudaModeEnabled", "Eruda Console", "Third-Party Tools", "In-page developer tools"),
    ]

    private static let app: [SettingsSearchItem] = [
        SettingsSearchItem("colorSchemeOverride", "Theme", "Appearance"),
        SettingsSearchItem("appLanguage", "Language", "Language"),
    ]

    private static let configuration: [SettingsSearchItem] = [
        SettingsSearchItem("enableJavaScript", "JavaScript", "Core", "Master switch for all JavaScript execution in WebView."),
        SettingsSearchItem("allowsContentJavaScript", "Content JavaScript", "Core", "Controls scripts from web pages only. App-injected scripts still work when disabled."),
        SettingsSearchItem("minimumFontSize", "Minimum Font Size", "Core"),
        SettingsSearchItem("mediaAutoplay", "Auto-play Media", "Media", "Allows videos with autoplay attribute to start without user interaction."),
        SettingsSearchItem("inlineMediaPlayback", "Inline Playback", "Media", "Plays videos inline instead of fullscreen. Required for background video effects."),
        SettingsSearchItem("allowsAirPlay", "AirPlay", "Media", "Enables streaming media to Apple TV and other AirPlay devices."),
        SettingsSearchItem("allowsPictureInPicture", "Picture in Picture", "Media", "Allows videos to continue playing in a floating window."),
        SettingsSearchItem("preferredContentMode", "Content Mode", "Content Mode"),
        SettingsSearchItem("javaScriptCanOpenWindows", "JS Can Open Windows", "Behavior", "Allows window.open() without user gesture. Disable to block pop-ups."),
        SettingsSearchItem("fraudulentWebsiteWarning", "Fraudulent Website Warning", "Behavior", "Shows warning for suspected phishing or malware sites."),
        SettingsSearchItem("elementFullscreenEnabled", "Element Fullscreen API", "Behavior", "Allows elements to enter fullscreen mode. Full API available on iPad only; iPhone is limited to video elements."),
        SettingsSearchItem("suppressesIncrementalRendering", "Suppress Incremental Rendering", "Behavior", "Waits for full page load before displaying. May feel slower but cleaner."),
        SettingsSearchItem("detectPhoneNumbers", "Phone Numbers", "Data Detectors", "Makes phone numbers tappable to call."),
        SettingsSearchItem("detectLinks", "Links", "Data Detectors", "Converts URL-like text to tappable links."),
        SettingsSearchItem("detectAddresses", "Addresses", "Data Detectors", "Makes addresses tappable to open in Maps."),
        SettingsSearchItem("detectCalendarEvents", "Calendar Events", "Data Detectors", "Detects dates and times, allowing to add to Calendar."),
        SettingsSearchItem("privateBrowsing", "Private Browsing", "Privacy & Security", "Uses non-persistent data store. No cookies or cache saved after session."),
        SettingsSearchItem("upgradeToHTTPS", "Upgrade to HTTPS", "Privacy & Security", "Automatically upgrades HTTP requests to HTTPS for known secure hosts."),
    ]

    private static let live: [SettingsSearchItem] = [
        SettingsSearchItem("allowsBackForwardGestures", "Back/Forward Gestures", "Navigation & Interaction", "Enables swipe from edge to navigate history."),
        SettingsSearchItem("allowsLinkPreview", "Link Preview", "Navigation & Interaction", "Shows page preview on long-press or 3D Touch on links."),
        SettingsSearchItem("allowZoom", "Ignore Viewport Scale Limits", "Navigation & Interaction", "Allows pinch-to-zoom even when the page disables it via viewport meta tag."),
        SettingsSearchItem("textInteractionEnabled", "Text Interaction", "Navigation & Interaction", "Enables text selection, copy, and other text interactions."),
        SettingsSearchItem("findInteractionEnabled", "Find Interaction", "Navigation & Interaction", "Enables the system find panel (Cmd+F on iPad with keyboard)."),
        SettingsSearchItem("pageZoom", "Page Zoom", "Display"),
        SettingsSearchItem("underPageBackgroundColor", "Under Page Background", "Display", "Background color shown when scrolling beyond page bounds."),
        SettingsSearchItem("customUserAgent", "User Agent", "Identity"),
        SettingsSearchItem("webViewSize", "WebView Size", "WebView Size", keywords: ["Width", "Height", "Presets"]),
    ]

    private static let emulation: [SettingsSearchItem] = [
        SettingsSearchItem("emulationColorScheme", "Color Scheme", "", "prefers-color-scheme\n\nOverrides JavaScript color scheme detection and the CSS color-scheme property. CSS @media rules keep system preferences."),
        SettingsSearchItem("emulationReducedMotion", "Reduced Motion", "", "prefers-reduced-motion\n\nDisables animations and transitions."),
        SettingsSearchItem("emulationHighContrast", "High Contrast", "", "prefers-contrast\n\nOverrides JavaScript contrast detection. Does not recolor the page or override CSS @media rules."),
        SettingsSearchItem("emulationReducedTransparency", "Reduced Transparency", "", "prefers-reduced-transparency\n\nDisables blur and transparency effects."),
    ]

    private static let permissions: [SettingsSearchItem] = [
        SettingsSearchItem("camera", "Camera", ""),
        SettingsSearchItem("microphone", "Microphone", ""),
        SettingsSearchItem("location", "Location", ""),
    ]

    private static let safariConfiguration: [SettingsSearchItem] = [
        SettingsSearchItem("safariEntersReaderIfAvailable", "Reader Mode", "Behavior", "Automatically enters Reader mode if available for the page."),
        SettingsSearchItem("safariBarCollapsingEnabled", "Bar Collapsing", "Behavior", "Allows the navigation bar to collapse when scrolling down."),
        SettingsSearchItem("safariDismissButtonStyle", "Dismiss Button", "UI Style"),
        SettingsSearchItem("safariControlTintColorHex", "Control Tint", "Colors", "Tint color for buttons and other controls."),
        SettingsSearchItem("safariBarTintColorHex", "Bar Tint", "Colors", "Background color of the navigation bar."),
        SettingsSearchItem("webViewSize", "WebView Size", "Size", keywords: ["Width", "Height", "Presets"]),
    ]
}
