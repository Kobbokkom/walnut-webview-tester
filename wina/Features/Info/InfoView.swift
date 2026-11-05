//
//  InfoView.swift
//  wina
//

import SwiftUI

// MARK: - InfoView

struct InfoView: View {
    /// External navigator for live page testing (nil = use test WebView with example.com)
    var navigator: WebViewNavigator?
    var webViewID: Binding<UUID>?
    var loadedURL: Binding<String>?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var webViewInfo: WebViewInfo?
    @State private var deviceInfo: DeviceInfo?
    @State private var codecInfo: MediaCodecInfo?
    @State private var displayInfo: DisplayInfo?
    @State private var accessibilityInfo: AccessibilityInfo?
    @State private var loadingStatus = "Loading..."
    @State private var isLoading = true
    @State private var showSettings = false

    // Instance Settings from AppStorage (internal for extension access)
    @AppStorage("allowsContentJavaScript") var allowsContentJavaScript: Bool = true
    @AppStorage("allowZoom") var allowZoom: Bool = false
    @AppStorage("minimumFontSize") var minimumFontSize: Double = 0
    @AppStorage("mediaAutoplay") var mediaAutoplay: Bool = false
    @AppStorage("inlineMediaPlayback") var inlineMediaPlayback: Bool = true
    @AppStorage("allowsAirPlay") var allowsAirPlay: Bool = true
    @AppStorage("allowsPictureInPicture") var allowsPictureInPicture: Bool = true
    @AppStorage("allowsBackForwardGestures") var allowsBackForwardGestures: Bool = false
    @AppStorage("allowsLinkPreview") var allowsLinkPreview: Bool = true
    @AppStorage("suppressesIncrementalRendering") var suppressesIncrementalRendering: Bool = false
    @AppStorage("javaScriptCanOpenWindows") var javaScriptCanOpenWindows: Bool = false
    @AppStorage("fraudulentWebsiteWarning") var fraudulentWebsiteWarning: Bool = true
    @AppStorage("textInteractionEnabled") var textInteractionEnabled: Bool = true
    @AppStorage("elementFullscreenEnabled") var elementFullscreenEnabled: Bool = false
    @AppStorage("detectPhoneNumbers") var detectPhoneNumbers: Bool = false
    @AppStorage("detectLinks") var detectLinks: Bool = false
    @AppStorage("detectAddresses") var detectAddresses: Bool = false
    @AppStorage("detectCalendarEvents") var detectCalendarEvents: Bool = false
    @AppStorage("privateBrowsing") var privateBrowsing: Bool = false
    @AppStorage("upgradeToHTTPS") var upgradeToHTTPS: Bool = true
    @AppStorage("preferredContentMode") var preferredContentMode: Int = 0
    @AppStorage("customUserAgent") var customUserAgent: String = ""
    @AppStorage("findInteractionEnabled") var findInteractionEnabled: Bool = false
    @AppStorage("pageZoom") var pageZoom: Double = 1.0
    @AppStorage("underPageBackgroundColor") var underPageBackgroundColorHex: String = ""
    @AppStorage("webViewWidthRatio") var webViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") var webViewHeightRatio: Double = 0.82
    @AppStorage("cachedSystemUserAgent") var cachedSystemUserAgent: String = ""

    var contentModeText: String {
        SettingsFormatter.contentModeText(preferredContentMode)
    }

    var activeDataDetectors: String {
        SettingsFormatter.activeDataDetectors(
            phone: detectPhoneNumbers,
            links: detectLinks,
            address: detectAddresses,
            calendar: detectCalendarEvents
        )
    }

    var isSearching: Bool {
        !searchText.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if isSearching {
                    searchResultsView
                } else {
                    defaultMenuView
                }
            }
            .searchable(text: $searchText, prompt: "Search all info")
            .navigationTitle(Text(verbatim: "WKWebView Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: showSettings) {
            guard !showSettings else { return }
            // Show interstitial ad (30% probability, once per session)
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "info_sheet"),
                adUnitId: AdManager.interstitialAdUnitId
            )

            guard !Task.isCancelled else { return }

            // Set navigator for live page testing (or nil for test WebView)
            SharedInfoWebView.shared.setNavigator(navigator)
            await loadAllInfo()
        }
        .sheet(isPresented: $showSettings) {
            if let webViewID, let loadedURL, let navigator {
                LoadedSettingsView(
                    webViewID: webViewID,
                    loadedURL: loadedURL,
                    navigator: navigator
                )
                .fullSizeSheet()
            } else {
                SettingsView()
                    .fullSizeSheet()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(loadingStatus)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Default Menu View

    private var defaultMenuView: some View {
        List {
            Section {
                if let url = navigator?.currentURL {
                    Text("Tested with loaded page (\(url.host() ?? url.absoluteString)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tested with temporary WebView (example.com). Actual results may vary.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)

            Section {
                NavigationLink {
                    ActiveSettingsView(showSettings: $showSettings)
                } label: {
                    InfoCategoryRow(
                        icon: "slider.horizontal.3",
                        title: "Active Settings",
                        description: "Current WebView configuration values"
                    )
                }
            } header: {
                Text("Current Configuration")
            }

            Section {
                NavigationLink {
                    DeviceInfoView()
                } label: {
                    InfoCategoryRow(
                        icon: "iphone",
                        title: "Device",
                        description: "Hardware, CPU, Memory, Display, Locale"
                    )
                }

                NavigationLink {
                    BrowserInfoView()
                } label: {
                    InfoCategoryRow(
                        icon: "safari",
                        title: "Browser",
                        description: "User Agent, WebKit version, WebGL info"
                    )
                }

                NavigationLink {
                    APICapabilitiesView()
                } label: {
                    InfoCategoryRow(
                        icon: "checklist",
                        title: "API Capabilities",
                        description: "46+ Web APIs support status"
                    )
                }

                NavigationLink {
                    MediaCodecsView()
                } label: {
                    InfoCategoryRow(
                        icon: "play.rectangle",
                        title: "Media Codecs",
                        description: "Video, Audio, Container format support"
                    )
                }

                NavigationLink {
                    BenchmarkView()
                } label: {
                    InfoCategoryRow(
                        icon: "gauge.with.needle",
                        title: "Benchmark",
                        description: "JavaScript, DOM, Graphics benchmarks"
                    )
                }

                NavigationLink {
                    DisplayFeaturesView()
                } label: {
                    InfoCategoryRow(
                        icon: "sparkles.rectangle.stack",
                        title: "Display",
                        description: "Screen size, Color gamut, HDR support"
                    )
                }

                NavigationLink {
                    AccessibilityFeaturesView()
                } label: {
                    InfoCategoryRow(
                        icon: "accessibility",
                        title: "Accessibility",
                        description: "Motion, Contrast, Color scheme preferences"
                    )
                }
            } header: {
                Text("WebView Capabilities")
            }
        }
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        List {
            ForEach(filteredItems.keys.sorted(), id: \.self) { category in
                Section(category) {
                    ForEach(filteredItems[category] ?? []) { item in
                        searchResultRow(for: item)
                    }
                }
            }
        }
        .overlay {
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(for item: InfoSearchItem) -> some View {
        if item.linkToPerformance {
            NavigationLink {
                BenchmarkView()
            } label: {
                HStack {
                    Text(item.label)
                    Spacer()
                    Text(item.value)
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
            }
        } else {
            HStack {
                Text(item.label)
                Spacer()
                if item.value == "Supported" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if item.value == "Not Supported" {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllInfo() async {
        let generation = SharedInfoWebView.shared.cacheGeneration
        isLoading = true
        // Start device info loading in parallel with WebView init (no WebView needed)
        async let device = DeviceInfo.load()

        // Pre-initialize shared WebView in background
        await SharedInfoWebView.shared.initialize { status in
            loadingStatus = status
        }

        // Load all info using shared WebView (parallel)
        async let webView = WebViewInfo.load { _ in }
        async let codec = MediaCodecInfo.load { _ in }
        async let display = DisplayInfo.load { _ in }
        async let accessibility = AccessibilityInfo.load { _ in }

        // Await all results (device likely already completed)
        let results = await (device, webView, codec, display, accessibility)
        guard !Task.isCancelled, SharedInfoWebView.shared.cacheGeneration == generation else { return }
        deviceInfo = results.0
        webViewInfo = results.1
        codecInfo = results.2
        displayInfo = results.3
        accessibilityInfo = results.4
        isLoading = false

        // Cache system user agent for UserAgentPickerView
        if customUserAgent.isEmpty, let ua = webViewInfo?.userAgent, !ua.isEmpty, ua != "Unknown" {
            cachedSystemUserAgent = ua
        }
    }

    // MARK: - Search Data

    private var filteredItems: [String: [InfoSearchItem]] {
        let filtered = searchText.isEmpty ? allItems : allItems.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.value.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: filtered, by: { $0.category })
    }

    private var allItems: [InfoSearchItem] {
        var items: [InfoSearchItem] = []

        // Active Settings (always available)
        items.append(contentsOf: activeSettingsItems)

        // Device items
        if let info = deviceInfo {
            items.append(contentsOf: deviceItems(from: info))
        }

        // Browser & API items from WebViewInfo
        if let info = webViewInfo {
            items.append(contentsOf: browserItems(from: info))
            items.append(contentsOf: apiItems(from: info))
        }

        // Media Codecs
        if let info = codecInfo {
            items.append(contentsOf: codecItems(from: info))
        }

        // Display
        if let info = displayInfo {
            items.append(contentsOf: displayItems(from: info))
        }

        // Accessibility
        if let info = accessibilityInfo {
            items.append(contentsOf: accessibilityItems(from: info))
        }

        // Performance (items only, values require benchmark execution)
        items.append(contentsOf: performanceItems)

        return items
    }

}

// Search item builders are in InfoView+SearchItems.swift
