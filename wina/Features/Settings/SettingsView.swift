//
//  SettingsView.swift
//  wina
//
//  Created by Claude on 12/7/25.
//

import SwiftUI

enum SettingsCopy {
    static let liveSettingsDescription: LocalizedStringResource = "Apply to save changes"
}

// ConfigurationSettingsView moved to ConfigurationSettingsView.swift

// MARK: - Live Settings View (Apply to Save)

struct LiveSettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @Environment(\.dismiss) private var dismiss

    // AppStorage (persistent)
    @AppStorage("allowsBackForwardGestures") private var storedAllowsBackForwardGestures: Bool = false
    @AppStorage("allowsLinkPreview") private var storedAllowsLinkPreview: Bool = true
    @AppStorage("textInteractionEnabled") private var storedTextInteractionEnabled: Bool = true
    @AppStorage("pageZoom") private var storedPageZoom: Double = 1.0
    @AppStorage("underPageBackgroundColor") private var storedUnderPageBackgroundColorHex: String = ""
    @AppStorage("findInteractionEnabled") private var storedFindInteractionEnabled: Bool = false
    @AppStorage("customUserAgent") private var storedCustomUserAgent: String = ""
    @AppStorage("webViewWidthRatio") private var storedWebViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") private var storedWebViewHeightRatio: Double = 0.82

    // Local state (editable)
    @State private var allowsBackForwardGestures: Bool = false
    @State private var allowsLinkPreview: Bool = true
    @State private var textInteractionEnabled: Bool = true
    @State private var pageZoom: Double = 1.0
    @State private var underPageBackgroundColorHex: String = ""
    @State private var findInteractionEnabled: Bool = false
    @State private var didLoadFromStorage = false
    @State private var customUserAgent: String = ""
    @State private var webViewWidthRatio: Double = 1.0
    @State private var webViewHeightRatio: Double = 0.82

    private var hasChanges: Bool {
        allowsBackForwardGestures != storedAllowsBackForwardGestures ||
        allowsLinkPreview != storedAllowsLinkPreview ||
        textInteractionEnabled != storedTextInteractionEnabled ||
        pageZoom != storedPageZoom ||
        underPageBackgroundColorHex != storedUnderPageBackgroundColorHex ||
        findInteractionEnabled != storedFindInteractionEnabled ||
        customUserAgent != storedCustomUserAgent ||
        webViewWidthRatio != storedWebViewWidthRatio ||
        webViewHeightRatio != storedWebViewHeightRatio
    }

    var body: some View {
        SettingsSearchList(screen: .live, search: $settingsSearch) {
            Section {
                SettingToggleRow(
                    title: "Back/Forward Gestures",
                    isOn: $allowsBackForwardGestures,
                    info: "Enables swipe from edge to navigate history."
                )
                .settingsSearchItem("allowsBackForwardGestures")
                SettingToggleRow(
                    title: "Link Preview",
                    isOn: $allowsLinkPreview,
                    info: "Shows page preview on long-press or 3D Touch on links."
                )
                .settingsSearchItem("allowsLinkPreview")
                SettingToggleRow(
                    title: "Text Interaction",
                    isOn: $textInteractionEnabled,
                    info: "Enables text selection, copy, and other text interactions."
                )
                .settingsSearchItem("textInteractionEnabled")
                SettingToggleRow(
                    title: "Find Interaction",
                    isOn: $findInteractionEnabled,
                    info: "Enables the system find panel (Cmd+F on iPad with keyboard)."
                )
                .settingsSearchItem("findInteractionEnabled")
            } header: {
                Text("Navigation & Interaction")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Page Zoom")
                        Spacer()
                        Text("\(Int(pageZoom * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $pageZoom, in: 0.5...3.0, step: 0.1)
                }
                .settingsSearchItem("pageZoom")

                ColorPickerRow(
                    title: "Under Page Background",
                    colorHex: $underPageBackgroundColorHex,
                    info: "Background color shown when scrolling beyond page bounds."
                )
                .settingsSearchItem("underPageBackgroundColor")
            } header: {
                Text("Display")
            }

            Section {
                NavigationLink {
                    UserAgentPickerView(localUserAgent: $customUserAgent)
                } label: {
                    HStack {
                        Text("User Agent")
                        Spacer()
                        Text(customUserAgent.isEmpty ? "Default" : "Custom")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .settingsSearchItem("customUserAgent")
            } header: {
                Text(verbatim: "Identity")
            }

            Section {
                WebViewSizeControl(
                    widthRatio: $webViewWidthRatio,
                    heightRatio: $webViewHeightRatio
                )
                .settingsSearchItem("webViewSize")
            } header: {
                Text("WebView Size")
            }

            Section {
                HStack {
                    Spacer()
                    GlassActionButton("Reset", icon: "arrow.counterclockwise", style: .destructive) {
                        resetToDefaults()
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text(verbatim: "Live Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") { applyChanges() }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if hasChanges {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Changes will apply to WebView")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .onAppear {
            guard !didLoadFromStorage else { return }
            loadFromStorage()
            didLoadFromStorage = true
        }
    }

    private func loadFromStorage() {
        allowsBackForwardGestures = storedAllowsBackForwardGestures
        allowsLinkPreview = storedAllowsLinkPreview
        textInteractionEnabled = storedTextInteractionEnabled
        pageZoom = storedPageZoom
        underPageBackgroundColorHex = storedUnderPageBackgroundColorHex
        findInteractionEnabled = storedFindInteractionEnabled
        customUserAgent = storedCustomUserAgent
        webViewWidthRatio = storedWebViewWidthRatio
        webViewHeightRatio = storedWebViewHeightRatio
    }

    private func applyChanges() {
        storedAllowsBackForwardGestures = allowsBackForwardGestures
        storedAllowsLinkPreview = allowsLinkPreview
        storedTextInteractionEnabled = textInteractionEnabled
        storedPageZoom = pageZoom
        storedUnderPageBackgroundColorHex = underPageBackgroundColorHex
        storedFindInteractionEnabled = findInteractionEnabled
        storedCustomUserAgent = customUserAgent
        storedWebViewWidthRatio = webViewWidthRatio
        storedWebViewHeightRatio = webViewHeightRatio
        dismiss()
    }

    private func resetToDefaults() {
        allowsBackForwardGestures = false
        allowsLinkPreview = true
        textInteractionEnabled = true
        pageZoom = 1.0
        underPageBackgroundColorHex = ""
        findInteractionEnabled = false
        customUserAgent = ""
        webViewWidthRatio = 1.0
        webViewHeightRatio = BarConstants.appHeightPreset
    }
}

// MARK: - Loaded Settings View (WebView Active - Menu Style)

struct LoadedSettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Binding var webViewID: UUID
    @Binding var loadedURL: String
    let navigator: WebViewNavigator

    @Environment(\.agentBrowserSettings) private var agentSettings
    @AppStorage(AgentSetting.erudaKey) private var savedErudaModeEnabled = false
    @State private var showErudaWarning: Bool = false

    private var erudaModeEnabled: Bool {
        agentSettings?.value(AgentSetting.erudaKey, fallback: savedErudaModeEnabled) ?? savedErudaModeEnabled
    }

    var body: some View {
        NavigationStack {
            SettingsSearchList(screen: .loaded, search: $settingsSearch) {
                SettingsSearchResults(results: settingsSearch.results(in: .loaded, locale: locale)) { result in
                    searchDestination(result)
                }
                Section {
                    SettingsCategoryRow(
                        icon: "app.badge.fill",
                        iconColor: .cyan,
                        title: "App Settings",
                        description: "Language, preferences"
                    ).link {
                        AppSettingsView()
                    }
                } header: {
                    Text("App")
                }

                Section {
                    SettingsCategoryRow(
                        icon: "menubar.rectangle",
                        iconColor: .indigo,
                        title: "Menu",
                        description: "Customize toolbar & app bar"
                    ).link {
                        MenuSettingsView()
                    }
                } header: {
                    Text("Developer Tools Settings")
                }

                Section {
                    SettingsCategoryRow(
                        icon: "bolt.fill",
                        iconColor: .green,
                        title: "Live Settings",
                        description: SettingsCopy.liveSettingsDescription
                    ).link {
                        LiveSettingsView()
                    }

                    SettingsCategoryRow(
                        icon: "gearshape.fill",
                        iconColor: .orange,
                        title: "Configuration",
                        description: "Changes reload WebView"
                    ).link {
                        ConfigurationSettingsView(
                            webViewID: $webViewID,
                            loadedURL: $loadedURL,
                            navigator: navigator
                        )
                    }

                    SettingsCategoryRow(
                        icon: "wand.and.stars",
                        iconColor: .purple,
                        title: "Emulation",
                        description: "Dark mode, Reduced motion, Contrast"
                    ).link {
                        EmulationSettingsView(navigator: navigator)
                    }

                    SettingsCategoryRow(
                        icon: "lock.shield.fill",
                        iconColor: .blue,
                        title: "Permissions",
                        description: "Camera, Microphone, Location"
                    ).link {
                        PermissionsSettingsView()
                    }
                } header: {
                    Text("WebView Settings")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { erudaModeEnabled },
                        set: { newValue in
                            if newValue {
                                showErudaWarning = true
                            } else {
                                AgentBrowserSettings.saveErudaMode(false, agentSettings: agentSettings)
                            }
                        }
                    )) {
                        HStack {
                            SettingsCategoryRow(
                                icon: "terminal.fill",
                                iconColor: .mint,
                                title: "Eruda Console",
                                description: "In-page developer tools"
                            )
                            RichInfoPopoverButton {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Eruda is a third-party mobile console.")
                                    HStack(spacing: 4) {
                                        Text("MIT License")
                                            .padding(.horizontal, 2)
                                            .padding(.vertical, 2)
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                        Text("© liriliri")
                                            .foregroundStyle(.secondary)
                                        Link("Link", destination: URL(string: "https://github.com/liriliri/eruda")!)
                                    }
                                }
                            }
                        }
                    }
                    .settingsSearchItem("erudaModeEnabled")
                    .tint(.mint)
                } header: {
                    Text("Third-Party Tools")
                } footer: {
                    if erudaModeEnabled {
                        Label("Built-in DevTools menu is disabled", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Enable Eruda Console", isPresented: $showErudaWarning) {
                Button("Cancel", role: .cancel) { }
                Button("Enable") {
                    AgentBrowserSettings.saveErudaMode(true, agentSettings: agentSettings)
                }
            } message: {
                Text("""
                    Eruda is a third-party in-page console that will be injected into web pages.

                    • This is open-source software (MIT License)
                    • Use at your own risk
                    • The built-in DevTools menu will be disabled while Eruda mode is active

                    You can disable Eruda mode anytime from Settings.
                    """)
            }
            .task {
                // Show interstitial ad (30% probability, once per session)
                await AdManager.shared.showInterstitialAd(
                    options: AdOptions(id: "settings_sheet"),
                    adUnitId: AdManager.interstitialAdUnitId
                )
            }
        }
    }

    @ViewBuilder
    private func searchDestination(_ result: SettingsSearchResult) -> some View {
        let search = SettingsSearch(item: result.item, locale: locale)
        switch result.screen {
        case .app: AppSettingsView(settingsSearch: search)
        case .menu: MenuSettingsView(settingsSearch: search)
        case .live: LiveSettingsView(settingsSearch: search)
        case .configuration:
            ConfigurationSettingsView(settingsSearch: search, webViewID: $webViewID, loadedURL: $loadedURL, navigator: navigator)
        case .emulation: EmulationSettingsView(settingsSearch: search, navigator: navigator)
        case .permissions: PermissionsSettingsView(settingsSearch: search)
        default: EmptyView()
        }
    }
}

// MARK: - Settings Category Row (Shared)

struct SettingsCategoryRow: View {
    var icon: String?
    var iconColor = Color.accentColor
    let title: LocalizedStringKey
    let description: LocalizedStringResource

    func link<Destination: View>(@ViewBuilder _ destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) { self }
            .containerValue(\.settingsSearchRole, .menuDescription(description.key))
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(LocalizedStringKey(description.key))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Combined Settings View (For Initial Setup)

struct SettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    // Core Settings
    @AppStorage("allowsContentJavaScript") private var allowsContentJavaScript: Bool = true
    @AppStorage("minimumFontSize") private var minimumFontSize: Double = 0

    // Media Settings
    @AppStorage("mediaAutoplay") private var mediaAutoplay: Bool = false
    @AppStorage("inlineMediaPlayback") private var inlineMediaPlayback: Bool = true
    @AppStorage("allowsAirPlay") private var allowsAirPlay: Bool = true
    @AppStorage("allowsPictureInPicture") private var allowsPictureInPicture: Bool = true

    // Navigation & Gestures
    @AppStorage("allowsBackForwardGestures") private var allowsBackForwardGestures: Bool = false
    @AppStorage("allowsLinkPreview") private var allowsLinkPreview: Bool = true
    @AppStorage("findInteractionEnabled") private var findInteractionEnabled: Bool = false

    // Content Settings
    @AppStorage("allowZoom") private var allowZoom: Bool = false
    @AppStorage("suppressesIncrementalRendering") private var suppressesIncrementalRendering: Bool = false
    @AppStorage("javaScriptCanOpenWindows") private var javaScriptCanOpenWindows: Bool = false
    @AppStorage("fraudulentWebsiteWarning") private var fraudulentWebsiteWarning: Bool = true
    @AppStorage("textInteractionEnabled") private var textInteractionEnabled: Bool = true
    @AppStorage("elementFullscreenEnabled") private var elementFullscreenEnabled: Bool = false

    // Data Detectors
    @AppStorage("detectPhoneNumbers") private var detectPhoneNumbers: Bool = false
    @AppStorage("detectLinks") private var detectLinks: Bool = false
    @AppStorage("detectAddresses") private var detectAddresses: Bool = false
    @AppStorage("detectCalendarEvents") private var detectCalendarEvents: Bool = false

    // Privacy & Security
    @AppStorage("privateBrowsing") private var privateBrowsing: Bool = false
    @AppStorage("upgradeToHTTPS") private var upgradeToHTTPS: Bool = true

    // Content Mode
    @AppStorage("preferredContentMode") private var preferredContentMode: Int = 0

    // User Agent
    @AppStorage("customUserAgent") private var customUserAgent: String = ""

    // Display
    @AppStorage("pageZoom") private var pageZoom: Double = 1.0
    @AppStorage("underPageBackgroundColor") private var underPageBackgroundColorHex: String = ""

    // WebView Size
    @AppStorage("webViewWidthRatio") private var webViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") private var webViewHeightRatio: Double = 0.82

    // Eruda Mode
    @Environment(\.agentBrowserSettings) private var agentSettings
    @AppStorage(AgentSetting.erudaKey) private var savedErudaModeEnabled = false
    @State private var showErudaWarning: Bool = false

    private var erudaModeEnabled: Bool {
        agentSettings?.value(AgentSetting.erudaKey, fallback: savedErudaModeEnabled) ?? savedErudaModeEnabled
    }

    // App Language
    @AppStorage("appLanguage") private var appLanguage: String = ""

    private var isIPad: Bool {
        UIDevice.current.isIPad
    }

    var body: some View {
        NavigationStack {
            SettingsSearchList(screen: .settings, search: $settingsSearch) {
                SettingsSearchResults(results: settingsSearch.results(in: .settings, locale: locale)) { result in
                    searchDestination(result)
                }
                appSection
                coreSection
                mediaSection
                ContentModeSection(selection: $preferredContentMode)
                behaviorSection
                dataDetectorsSection
                privacySection
                navigationSection
                displaySection
                userAgentSection
                webViewSizeSection
                erudaSection
                resetSection
            }
            .navigationTitle(Text(verbatim: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Enable Eruda Console", isPresented: $showErudaWarning) {
                Button("Cancel", role: .cancel) { }
                Button("Enable") {
                    AgentBrowserSettings.saveErudaMode(true, agentSettings: agentSettings)
                }
            } message: {
                Text("""
                    Eruda is a third-party in-page console that will be injected into web pages.

                    • This is open-source software (MIT License)
                    • Use at your own risk
                    • The built-in DevTools menu will be disabled while Eruda mode is active

                    You can disable Eruda mode anytime from Settings.
                    """)
            }
        }
    }

    @ViewBuilder
    private var erudaSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { erudaModeEnabled },
                set: { newValue in
                    if newValue {
                        showErudaWarning = true
                    } else {
                        AgentBrowserSettings.saveErudaMode(false, agentSettings: agentSettings)
                    }
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Eruda Console")
                            .font(.body)
                        Text("In-page developer tools")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    RichInfoPopoverButton {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Eruda is a third-party mobile console.")
                            HStack(spacing: 4) {
                                Text("MIT License")
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                                Text("©")
                                    .foregroundStyle(.secondary)
                                Link("liriliri", destination: URL(string: "https://github.com/liriliri/eruda")!)
                            }
                        }
                    }
                }
            }
            .settingsSearchItem("erudaModeEnabled")
            .tint(.mint)
        } header: {
            Text("Third-Party Tools")
        } footer: {
            if erudaModeEnabled {
                Label("Built-in DevTools menu is disabled", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Section {
            HStack {
                Spacer()
                GlassActionButton("Reset", icon: "arrow.counterclockwise", style: .destructive) {
                    resetAllToDefaults()
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var appSection: some View {
        Section {
            NavigationLink {
                AppSettingsView()
            } label: {
                HStack {
                    Text("App Settings")
                    Spacer()
                    Text(AppLanguage(rawValue: appLanguage)?.displayName ?? "System")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("App")
        }
    }

    @ViewBuilder
    private var coreSection: some View {
        Section {
            SettingToggleRow(
                title: "Content JavaScript",
                isOn: $allowsContentJavaScript,
                info: "Controls scripts from web pages only. App-injected scripts still work when disabled."
            )
            .settingsSearchItem("allowsContentJavaScript")
            HStack {
                Text("Minimum Font Size")
                Spacer()
                TextField("0", value: Binding(
                    get: { SettingsFormatter.validMinimumFontSize(minimumFontSize) },
                    set: { minimumFontSize = SettingsFormatter.validMinimumFontSize($0) }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("pt")
                    .foregroundStyle(.secondary)
            }
            .settingsSearchItem("minimumFontSize")
        } header: {
            Text(verbatim: "Core")
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        Section {
            SettingToggleRow(
                title: "Auto-play Media",
                isOn: $mediaAutoplay,
                info: "Allows videos with autoplay attribute to start without user interaction."
            )
            .settingsSearchItem("mediaAutoplay")
            SettingToggleRow(
                title: "Inline Playback",
                isOn: $inlineMediaPlayback,
                info: "Plays videos inline instead of fullscreen. Required for background video effects."
            )
            .settingsSearchItem("inlineMediaPlayback")
            SettingToggleRow(
                title: "AirPlay",
                isOn: $allowsAirPlay,
                info: "Enables streaming media to Apple TV and other AirPlay devices."
            )
            .settingsSearchItem("allowsAirPlay")
            SettingToggleRow(
                title: "Picture in Picture",
                isOn: $allowsPictureInPicture,
                info: "Allows videos to continue playing in a floating window."
            )
            .settingsSearchItem("allowsPictureInPicture")
        } header: {
            Text("Media")
        }
    }

    @ViewBuilder
    private var behaviorSection: some View {
        Section {
            SettingToggleRow(
                title: "Ignore Viewport Scale Limits",
                isOn: $allowZoom,
                info: "Allows pinch-to-zoom even when the page disables it via viewport meta tag."
            )
            .settingsSearchItem("allowZoom")
            SettingToggleRow(
                title: "JS Can Open Windows",
                isOn: $javaScriptCanOpenWindows,
                info: "Allows window.open() without user gesture. Disable to block pop-ups."
            )
            .settingsSearchItem("javaScriptCanOpenWindows")
            SettingToggleRow(
                title: "Fraudulent Website Warning",
                isOn: $fraudulentWebsiteWarning,
                info: "Shows warning for suspected phishing or malware sites."
            )
            .settingsSearchItem("fraudulentWebsiteWarning")
            SettingToggleRow(
                title: "Element Fullscreen API",
                isOn: $elementFullscreenEnabled,
                info: isIPad ? "iPad: Full element fullscreen support." : "iPhone: Limited to video elements only.",
                disabled: !isIPad,
                disabledLabel: "(iPad only)"
            )
            .settingsSearchItem("elementFullscreenEnabled")
            SettingToggleRow(
                title: "Suppress Incremental Rendering",
                isOn: $suppressesIncrementalRendering,
                info: "Waits for full page load before displaying. May feel slower but cleaner."
            )
            .settingsSearchItem("suppressesIncrementalRendering")
        } header: {
            Text("Behavior")
        }
    }

    @ViewBuilder
    private var dataDetectorsSection: some View {
        Section {
            SettingToggleRow(
                title: "Phone Numbers",
                isOn: $detectPhoneNumbers,
                info: "Makes phone numbers tappable to call."
            )
            .settingsSearchItem("detectPhoneNumbers")
            SettingToggleRow(
                title: "Links",
                isOn: $detectLinks,
                info: "Converts URL-like text to tappable links."
            )
            .settingsSearchItem("detectLinks")
            SettingToggleRow(
                title: "Addresses",
                isOn: $detectAddresses,
                info: "Makes addresses tappable to open in Maps."
            )
            .settingsSearchItem("detectAddresses")
            SettingToggleRow(
                title: "Calendar Events",
                isOn: $detectCalendarEvents,
                info: "Detects dates and times, allowing to add to Calendar."
            )
            .settingsSearchItem("detectCalendarEvents")
        } header: {
            Text("Data Detectors")
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        Section {
            SettingToggleRow(
                title: "Private Browsing",
                isOn: $privateBrowsing,
                info: "Uses non-persistent data store. No cookies or cache saved after session."
            )
            .settingsSearchItem("privateBrowsing")
            SettingToggleRow(
                title: "Upgrade to HTTPS",
                isOn: $upgradeToHTTPS,
                info: "Automatically upgrades HTTP requests to HTTPS for known secure hosts."
            )
            .settingsSearchItem("upgradeToHTTPS")
        } header: {
            Text("Privacy & Security")
        }
    }

    @ViewBuilder
    private var navigationSection: some View {
        Section {
            SettingToggleRow(
                title: "Back/Forward Gestures",
                isOn: $allowsBackForwardGestures,
                info: "Enables swipe from edge to navigate history."
            )
            .settingsSearchItem("allowsBackForwardGestures")
            SettingToggleRow(
                title: "Link Preview",
                isOn: $allowsLinkPreview,
                info: "Shows page preview on long-press or 3D Touch on links."
            )
            .settingsSearchItem("allowsLinkPreview")
            SettingToggleRow(
                title: "Text Interaction",
                isOn: $textInteractionEnabled,
                info: "Enables text selection, copy, and other text interactions."
            )
            .settingsSearchItem("textInteractionEnabled")
            SettingToggleRow(
                title: "Find Interaction",
                isOn: $findInteractionEnabled,
                info: "Enables the system find panel (Cmd+F on iPad with keyboard)."
            )
            .settingsSearchItem("findInteractionEnabled")
        } header: {
            Text("Navigation & Interaction")
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Page Zoom")
                    Spacer()
                    Text("\(Int(pageZoom * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $pageZoom, in: 0.5...3.0, step: 0.1)
            }
            .settingsSearchItem("pageZoom")

            ColorPickerRow(
                title: "Under Page Background",
                colorHex: $underPageBackgroundColorHex,
                info: "Background color shown when scrolling beyond page bounds."
            )
            .settingsSearchItem("underPageBackgroundColor")
        } header: {
            Text("Display")
        }
    }

    @ViewBuilder
    private var userAgentSection: some View {
        Section {
            NavigationLink {
                UserAgentPickerView()
            } label: {
                HStack {
                    Text("User Agent")
                    Spacer()
                    Text(customUserAgent.isEmpty ? "Default" : "Custom")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .settingsSearchItem("customUserAgent")
        } header: {
            Text(verbatim: "Identity")
        }
    }

    @ViewBuilder
    private var webViewSizeSection: some View {
        Section {
            WebViewSizeControl(
                widthRatio: $webViewWidthRatio,
                heightRatio: $webViewHeightRatio
            )
            .settingsSearchItem("webViewSize")
        } header: {
            Text("WebView Size")
        }
    }

    private func resetAllToDefaults() {
        // Core
        allowsContentJavaScript = true
        minimumFontSize = 0

        // Media
        mediaAutoplay = false
        inlineMediaPlayback = true
        allowsAirPlay = true
        allowsPictureInPicture = true

        // Navigation & Gestures
        allowsBackForwardGestures = false
        allowsLinkPreview = true
        findInteractionEnabled = false

        // Content
        allowZoom = false
        suppressesIncrementalRendering = false
        javaScriptCanOpenWindows = false
        fraudulentWebsiteWarning = true
        textInteractionEnabled = true
        elementFullscreenEnabled = false

        // Data Detectors
        detectPhoneNumbers = false
        detectLinks = false
        detectAddresses = false
        detectCalendarEvents = false

        // Privacy & Security
        privateBrowsing = false
        upgradeToHTTPS = true

        // Content Mode
        preferredContentMode = 0

        // User Agent
        customUserAgent = ""

        // WebView Size (App preset)
        webViewWidthRatio = 1.0
        webViewHeightRatio = BarConstants.appHeightPreset

        // Third-Party Tools
        AgentBrowserSettings.saveErudaMode(false, agentSettings: agentSettings)
    }

    private func searchDestination(_ result: SettingsSearchResult) -> some View {
        AppSettingsView(settingsSearch: SettingsSearch(item: result.item, locale: locale))
    }
}

// WebViewSizeControl and PresetButton moved to Shared/Components/WebViewSizeControl.swift
// PermissionsSettingsView, PermissionRow, LocationManagerDelegate moved to PermissionsSettingsView.swift

#Preview("Settings") {
    SettingsView()
}

#Preview("Loaded Settings") {
    @Previewable @State var id = UUID()
    @Previewable @State var url = "https://example.com"
    LoadedSettingsView(
        webViewID: $id,
        loadedURL: $url,
        navigator: WebViewNavigator()
    )
}

#Preview("Live Settings") {
    NavigationStack {
        LiveSettingsView()
    }
}
