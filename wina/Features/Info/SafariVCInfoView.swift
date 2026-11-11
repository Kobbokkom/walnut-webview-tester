//
//  SafariVCInfoView.swift
//  wina
//

import SafariServices
import SwiftUI
import SwiftUIBackports

struct SafariVCInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Binding var webViewID: UUID

    init(webViewID: Binding<UUID> = .constant(UUID())) {
        self._webViewID = webViewID
    }
    @State private var showingSettings = false
    @State private var searchText = ""

    // Current configuration values
    @AppStorage("safariEntersReaderIfAvailable") private var entersReaderIfAvailable: Bool = false
    @AppStorage("safariBarCollapsingEnabled") private var barCollapsingEnabled: Bool = true
    @AppStorage("safariDismissButtonStyle") private var dismissButtonStyle: Int = 0
    @AppStorage("safariControlTintColorHex") private var controlTintColorHex: String = ""
    @AppStorage("safariBarTintColorHex") private var barTintColorHex: String = ""

    private var allItems: [SafariInfoSearchItem] {
        var items: [SafariInfoSearchItem] = []

        // Active Settings
        items.append(contentsOf: [
            SafariInfoSearchItem(category: "Active Settings", label: "Reader Mode", value: entersReaderIfAvailable ? "Enabled" : "Disabled"),
            SafariInfoSearchItem(category: "Active Settings", label: "Bar Collapsing", value: barCollapsingEnabled ? "Enabled" : "Disabled"),
            SafariInfoSearchItem(category: "Active Settings", label: "Dismiss Button", value: SettingsFormatter.dismissButtonStyleText(dismissButtonStyle)),
            SafariInfoSearchItem(category: "Active Settings", label: "Control Tint", value: controlTintColorHex.isEmpty ? "System" : "\(controlTintColorHex) (iOS 18.4-25)"),
            SafariInfoSearchItem(category: "Active Settings", label: "Bar Tint", value: barTintColorHex.isEmpty ? "System" : "\(barTintColorHex) (iOS 18.4-25)"),
            SafariInfoSearchItem(
                category: "Active Settings",
                label: String(localized: LocalizedStringResource("Presentation", locale: locale)),
                value: String(localized: LocalizedStringResource("Full Screen", locale: locale))
            )
        ])

        // Safari Features
        items.append(contentsOf: [
            SafariInfoSearchItem(category: "Safari Features", label: "Reader Mode", value: "Supported"),
            SafariInfoSearchItem(category: "Safari Features", label: "AutoFill", value: "Supported"),
            SafariInfoSearchItem(category: "Safari Features", label: "Fraudulent Website Detection", value: "Supported"),
            SafariInfoSearchItem(category: "Safari Features", label: "Content Blockers", value: "Supported"),
            SafariInfoSearchItem(category: "Safari Features", label: "Safari Extensions", value: "Supported")
        ])

        // API Availability
        items.append(contentsOf: [
            SafariInfoSearchItem(category: "API Availability", label: "SFSafariViewController", value: "Supported"),
            SafariInfoSearchItem(category: "API Availability", label: "Configuration", value: "Supported"),
            SafariInfoSearchItem(category: "API Availability", label: "preferredBarTintColor", value: "iOS 18.4-25"),
            SafariInfoSearchItem(category: "API Availability", label: "preferredControlTintColor", value: "iOS 18.4-25"),
            SafariInfoSearchItem(category: "API Availability", label: "dismissButtonStyle", value: "Supported"),
            SafariInfoSearchItem(category: "API Availability", label: "prewarmConnections", value: "Supported"),
            SafariInfoSearchItem(category: "API Availability", label: "Activity Button", value: "Supported")
        ])

        // Privacy & Data
        items.append(contentsOf: [
            SafariInfoSearchItem(category: "Privacy & Data", label: "Cookie Isolation", value: "Enabled"),
            SafariInfoSearchItem(category: "Privacy & Data", label: "LocalStorage Isolation", value: "Enabled"),
            SafariInfoSearchItem(category: "Privacy & Data", label: "Session Isolation", value: "Enabled")
        ])

        // Delegate Events
        items.append(contentsOf: [
            SafariInfoSearchItem(category: "Delegate Events", label: "safariViewControllerDidFinish", value: "callback"),
            SafariInfoSearchItem(category: "Delegate Events", label: "didCompleteInitialLoad", value: "callback"),
            SafariInfoSearchItem(category: "Delegate Events", label: "activityItemsFor", value: "callback"),
            SafariInfoSearchItem(category: "Delegate Events", label: "initialLoadDidRedirectTo", value: "callback"),
            SafariInfoSearchItem(category: "Delegate Events", label: "willOpenInBrowser", value: "callback"),
            SafariInfoSearchItem(category: "Delegate Events", label: "excludedActivityTypes", value: "callback")
        ])

        // Limitations (positive labels, shown as N/A like WKWebView unavailable APIs)
        items.append(contentsOf: [
            SafariInfoSearchItem(category: "Limitations", label: "JavaScript Injection", value: "N/A"),
            SafariInfoSearchItem(category: "Limitations", label: "DOM Access", value: "N/A"),
            SafariInfoSearchItem(category: "Limitations", label: "Navigation Control", value: "N/A"),
            SafariInfoSearchItem(category: "Limitations", label: "URL Changes", value: "N/A"),
            SafariInfoSearchItem(category: "Limitations", label: "Full UI Customization", value: "N/A")
        ])

        return items
    }

    private var filteredItems: [String: [SafariInfoSearchItem]] {
        let filtered = searchText.isEmpty ? allItems : allItems.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: filtered, by: { $0.category })
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    searchResultsView
                } else {
                    menuView
                }
            }
            .searchable(text: $searchText, prompt: "Search all info")
            .navigationTitle(Text(verbatim: "SafariVC Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SafariVCSettingsView(webViewID: $webViewID)
                    .fullSizeSheet()
            }
            .task {
                // Show interstitial ad (30% probability, once per session)
                await AdManager.shared.showInterstitialAd(
                    options: AdOptions(id: "info_sheet"),
                    adUnitId: AdManager.interstitialAdUnitId
                )
            }
        }
    }

    // MARK: - Search Results View

    @ViewBuilder
    private var searchResultsView: some View {
        List {
            ForEach(filteredItems.keys.sorted(), id: \.self) { category in
                Section(category) {
                    ForEach(filteredItems[category] ?? []) { item in
                        HStack {
                            Text(item.label)
                            Spacer()
                            Text(item.value)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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

    // MARK: - Menu View

    @ViewBuilder
    private var menuView: some View {
        List {
            Section {
                NavigationLink {
                    SafariActiveSettingsDetailView(showSettings: $showingSettings)
                } label: {
                    SafariInfoCategoryRow(
                        icon: "slider.horizontal.3",
                        title: "Active Settings",
                        description: "Current SafariVC configuration"
                    )
                }
            } header: {
                Text("Current Configuration")
            }

            Section {
                NavigationLink {
                    SafariFeaturesDetailView()
                } label: {
                    SafariInfoCategoryRow(
                        icon: "safari",
                        title: "Safari Features",
                        description: "Reader, AutoFill, Content Blockers"
                    )
                }

                NavigationLink {
                    SafariAPIDetailView()
                } label: {
                    SafariInfoCategoryRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "API Availability",
                        description: "SFSafariViewController APIs"
                    )
                }

                NavigationLink {
                    SafariPrivacyDetailView()
                } label: {
                    SafariInfoCategoryRow(
                        icon: "lock.shield",
                        title: "Privacy & Data",
                        description: "Cookie, Storage isolation"
                    )
                }

                NavigationLink {
                    SafariDelegateDetailView()
                } label: {
                    SafariInfoCategoryRow(
                        icon: "arrow.triangle.branch",
                        title: "Delegate Events",
                        description: "Available callback methods"
                    )
                }

                NavigationLink {
                    SafariLimitationsDetailView()
                } label: {
                    SafariInfoCategoryRow(
                        icon: "exclamationmark.triangle",
                        title: "Limitations",
                        description: "What SafariVC cannot do"
                    )
                }
            } header: {
                Text("SafariVC Capabilities")
            }
        }
    }
}

// MARK: - Safari Info Category Row

private struct SafariInfoCategoryRow: View {
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

// MARK: - Active Settings Detail View

private struct SafariActiveSettingsDetailView: View {
    @Environment(\.locale) private var locale
    @Binding var showSettings: Bool

    @AppStorage("safariEntersReaderIfAvailable") private var entersReaderIfAvailable: Bool = false
    @AppStorage("safariBarCollapsingEnabled") private var barCollapsingEnabled: Bool = true
    @AppStorage("safariDismissButtonStyle") private var dismissButtonStyle: Int = 0
    @AppStorage("safariControlTintColorHex") private var controlTintColorHex: String = ""
    @AppStorage("safariBarTintColorHex") private var barTintColorHex: String = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .backport.glassEffect(in: .capsule)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            // MARK: - Configuration (all SafariVC settings require reload)
            Section {
                SafariActiveSettingRow(
                    label: "Reader Mode",
                    enabled: entersReaderIfAvailable,
                    info: "Automatically enters Reader mode when available for the page."
                )
                SafariActiveSettingRow(
                    label: "Bar Collapsing",
                    enabled: barCollapsingEnabled,
                    info: "Navigation bar collapses when scrolling down."
                )
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.orange)
                    Text("Configuration")
                }
            } footer: {
                Text("All changes require SafariVC reload")
            }

            Section("UI Style") {
                SafariInfoRow(
                    label: String(localized: LocalizedStringResource("Presentation", locale: locale)),
                    value: String(localized: LocalizedStringResource("Full Screen", locale: locale))
                )
                SafariInfoRow(
                    label: "Dismiss Button",
                    value: SettingsFormatter.dismissButtonStyleText(dismissButtonStyle),
                    info: "Button style shown in top-left corner."
                )
            }

            Section("Colors") {
                SafariInfoRow(
                    label: "Control Tint",
                    value: controlTintColorHex.isEmpty ? "System" : controlTintColorHex,
                    info: "Tint color for buttons and controls.\nApplied on iOS 18.4-25 only."
                )
                SafariInfoRow(
                    label: "Bar Tint",
                    value: barTintColorHex.isEmpty ? "System" : barTintColorHex,
                    info: "Background color of navigation bar.\nApplied on iOS 18.4-25 only."
                )
            }
        }
        .navigationTitle(Text(verbatim: "Active Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safari Active Setting Row

private struct SafariActiveSettingRow: View {
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

// MARK: - Safari Features Detail View

private struct SafariFeaturesDetailView: View {
    var body: some View {
        List {
            Section("Included Safari Features") {
                SafariCapabilityRow(
                    label: "Reader Mode",
                    supported: true,
                    info: "Distraction-free article view with customizable appearance."
                )
                SafariCapabilityRow(
                    label: "AutoFill",
                    supported: true,
                    info: "Access to saved passwords via iCloud Keychain."
                )
                SafariCapabilityRow(
                    label: "Fraudulent Website Detection",
                    supported: true,
                    info: "Warns users about suspected phishing sites."
                )
                SafariCapabilityRow(
                    label: "Content Blockers",
                    supported: true,
                    info: "User's installed Safari content blockers are applied."
                )
                SafariCapabilityRow(
                    label: "Safari Extensions",
                    supported: true,
                    info: "User's Safari web extensions are available."
                )
            }
        }
        .navigationTitle(Text(verbatim: "Safari Features"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safari API Detail View

private struct SafariAPIDetailView: View {
    var body: some View {
        List {
            Section("Core API") {
                SafariAPIRow(
                    api: "SFSafariViewController",
                    description: "Core Safari view controller"
                )
                SafariAPIRow(
                    api: "Configuration",
                    description: "Reader mode, bar collapsing options"
                )
            }

            Section("Appearance") {
                SafariAPIRow(
                    api: "preferredBarTintColor",
                    description: "Navigation bar background color. Deprecated in iOS 26."
                )
                SafariAPIRow(
                    api: "preferredControlTintColor",
                    description: "Button and control tint color. Deprecated in iOS 26."
                )
                SafariAPIRow(
                    api: "dismissButtonStyle",
                    description: "Done/Close/Cancel button style"
                )
            }

            Section("Advanced") {
                SafariAPIRow(
                    api: "prewarmConnections",
                    description: "Pre-load URLs before presenting"
                )
                SafariAPIRow(
                    api: "Activity Button",
                    description: "Custom Share Extension in toolbar"
                )
            }
        }
        .navigationTitle(Text(verbatim: "API Availability"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safari Privacy Detail View

private struct SafariPrivacyDetailView: View {
    var body: some View {
        List {
            Section("Data Isolation") {
                SafariPrivacyRow(
                    title: "Cookie Isolation",
                    description: "Cookies are NOT shared with Safari app. Each app has separate cookie storage."
                )
                SafariPrivacyRow(
                    title: "LocalStorage Isolation",
                    description: "Website data is sandboxed per app. Data stored in one app is not accessible from another."
                )
                SafariPrivacyRow(
                    title: "Session Isolation",
                    description: "Each SFSafariViewController instance has separate storage. Closing and reopening clears session."
                )
            }

            Section {
                Text("SafariVC data is sandboxed per app and not shared with Safari.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(verbatim: "Privacy & Data"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safari Delegate Detail View

private struct SafariDelegateDetailView: View {
    var body: some View {
        List {
            Section("SFSafariViewControllerDelegate") {
                SafariDelegateRow(
                    method: "safariViewControllerDidFinish(_:)",
                    description: "Called when user taps Done button. Use this to dismiss the view controller."
                )
                SafariDelegateRow(
                    method: "didCompleteInitialLoad",
                    description: "Called when initial page load completes (success or failure). Good for analytics."
                )
                SafariDelegateRow(
                    method: "initialLoadDidRedirectTo(_:)",
                    description: "Called when initial load redirects to new URL. Track final landing URL."
                )
                SafariDelegateRow(
                    method: "willOpenInBrowser()",
                    description: "Called before opening URL in Safari app. Clean up or save state."
                )
            }

            Section("Activity Customization") {
                SafariDelegateRow(
                    method: "activityItemsFor(_:title:)",
                    description: "Provide custom activities for Share sheet. Return array of UIActivity objects."
                )
                SafariDelegateRow(
                    method: "excludedActivityTypes",
                    description: "Exclude specific activities from Share sheet. Return array of activity type identifiers."
                )
            }
        }
        .navigationTitle(Text(verbatim: "Delegate Events"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safari Limitations Detail View

private struct SafariLimitationsDetailView: View {
    var body: some View {
        List {
            Section("Content Access") {
                SafariCapabilityRow(
                    label: "JavaScript Injection",
                    supported: false,
                    info: "Cannot execute custom JavaScript code. No evaluateJavaScript() method available.",
                    unavailable: true
                )
                SafariCapabilityRow(
                    label: "DOM Access",
                    supported: false,
                    info: "Cannot read or modify page content. Cannot extract text, images, or any page data.",
                    unavailable: true
                )
            }

            Section("Navigation") {
                SafariCapabilityRow(
                    label: "Navigation Control",
                    supported: false,
                    info: "Cannot intercept or redirect navigation. Cannot block or modify requests.",
                    unavailable: true
                )
                SafariCapabilityRow(
                    label: "URL Changes",
                    supported: false,
                    info: "Cannot change URL after presentation. Must dismiss and create new instance.",
                    unavailable: true
                )
            }

            Section("Customization") {
                SafariCapabilityRow(
                    label: "Full UI Customization",
                    supported: false,
                    info: "Only colors and dismiss button style can be changed. Cannot add custom toolbar items.",
                    unavailable: true
                )
            }

            Section {
                Text("These limitations exist because SFSafariViewController prioritizes user privacy and security. For full control, use WKWebView instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(verbatim: "Limitations"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views

private struct SafariInfoRow: View {
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

private struct SafariCapabilityRow: View {
    let label: String
    let supported: Bool
    var info: LocalizedStringKey?
    var unavailable = false  // Safari policy: never supported

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(unavailable ? .secondary : .primary)
            if let info {
                InfoPopoverButton(text: info)
            }
            Spacer()
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

private struct SafariAPIRow: View {
    let api: String
    let description: LocalizedStringKey

    var body: some View {
        HStack {
            Text(api)
                .font(.subheadline.monospaced())
            InfoPopoverButton(text: description, iconColor: .tertiary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct SafariPrivacyRow: View {
    let title: String
    let description: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
            InfoPopoverButton(text: description, iconColor: .tertiary)
            Spacer()
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.blue)
        }
    }
}

private struct SafariDelegateRow: View {
    let method: String
    let description: LocalizedStringKey

    var body: some View {
        HStack {
            Text(method)
                .font(.caption.monospaced())
                .lineLimit(1)
            InfoPopoverButton(text: description, iconColor: .tertiary)
            Spacer()
            Text("callback")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Search Item Model

private struct SafariInfoSearchItem: Identifiable {
    let id = UUID()
    let category: String
    let label: String
    let value: String
}

#Preview {
    SafariVCInfoView()
}
