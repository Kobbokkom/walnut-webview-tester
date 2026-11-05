//
//  ConfigurationSettingsView.swift
//  wina
//
//  Extracted from SettingsView.swift for file length compliance
//

import SwiftUI

// MARK: - Configuration Settings View (Requires WebView Reload)

struct ConfigurationSettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @State private var didLoadFromStorage = false
    @Environment(\.dismiss) private var dismiss
    @Binding var webViewID: UUID
    @Binding var loadedURL: String
    let navigator: WebViewNavigator

    // AppStorage (persistent)
    @AppStorage("allowsContentJavaScript") private var storedAllowsContentJavaScript: Bool = true
    @AppStorage("minimumFontSize") private var storedMinimumFontSize: Double = 0
    @AppStorage("mediaAutoplay") private var storedMediaAutoplay: Bool = false
    @AppStorage("inlineMediaPlayback") private var storedInlineMediaPlayback: Bool = true
    @AppStorage("allowsAirPlay") private var storedAllowsAirPlay: Bool = true
    @AppStorage("allowsPictureInPicture") private var storedAllowsPictureInPicture: Bool = true
    @AppStorage("preferredContentMode") private var storedPreferredContentMode: Int = 0
    @AppStorage("allowZoom") private var storedAllowZoom: Bool = false
    @AppStorage("javaScriptCanOpenWindows") private var storedJavaScriptCanOpenWindows: Bool = false
    @AppStorage("fraudulentWebsiteWarning") private var storedFraudulentWebsiteWarning: Bool = true
    @AppStorage("elementFullscreenEnabled") private var storedElementFullscreenEnabled: Bool = false
    @AppStorage("suppressesIncrementalRendering") private var storedSuppressesIncrementalRendering: Bool = false
    @AppStorage("detectPhoneNumbers") private var storedDetectPhoneNumbers: Bool = false
    @AppStorage("detectLinks") private var storedDetectLinks: Bool = false
    @AppStorage("detectAddresses") private var storedDetectAddresses: Bool = false
    @AppStorage("detectCalendarEvents") private var storedDetectCalendarEvents: Bool = false
    @AppStorage("privateBrowsing") private var storedPrivateBrowsing: Bool = false
    @AppStorage("upgradeToHTTPS") private var storedUpgradeToHTTPS: Bool = true

    // Local state (editable)
    @State private var allowsContentJavaScript: Bool = true
    @State private var minimumFontSize: Double = 0
    @State private var mediaAutoplay: Bool = false
    @State private var inlineMediaPlayback: Bool = true
    @State private var allowsAirPlay: Bool = true
    @State private var allowsPictureInPicture: Bool = true
    @State private var preferredContentMode: Int = 0
    @State private var allowZoom: Bool = false
    @State private var javaScriptCanOpenWindows: Bool = false
    @State private var fraudulentWebsiteWarning: Bool = true
    @State private var elementFullscreenEnabled: Bool = false
    @State private var suppressesIncrementalRendering: Bool = false
    @State private var detectPhoneNumbers: Bool = false
    @State private var detectLinks: Bool = false
    @State private var detectAddresses: Bool = false
    @State private var detectCalendarEvents: Bool = false
    @State private var privateBrowsing: Bool = false
    @State private var upgradeToHTTPS: Bool = true

    private var isIPad: Bool {
        UIDevice.current.isIPad
    }

    private var hasChanges: Bool {
        allowsContentJavaScript != storedAllowsContentJavaScript ||
        minimumFontSize != storedMinimumFontSize ||
        mediaAutoplay != storedMediaAutoplay ||
        inlineMediaPlayback != storedInlineMediaPlayback ||
        allowsAirPlay != storedAllowsAirPlay ||
        allowsPictureInPicture != storedAllowsPictureInPicture ||
        preferredContentMode != storedPreferredContentMode ||
        allowZoom != storedAllowZoom ||
        javaScriptCanOpenWindows != storedJavaScriptCanOpenWindows ||
        fraudulentWebsiteWarning != storedFraudulentWebsiteWarning ||
        elementFullscreenEnabled != storedElementFullscreenEnabled ||
        suppressesIncrementalRendering != storedSuppressesIncrementalRendering ||
        detectPhoneNumbers != storedDetectPhoneNumbers ||
        detectLinks != storedDetectLinks ||
        detectAddresses != storedDetectAddresses ||
        detectCalendarEvents != storedDetectCalendarEvents ||
        privateBrowsing != storedPrivateBrowsing ||
        upgradeToHTTPS != storedUpgradeToHTTPS
    }

    var body: some View {
        SettingsSearchList(screen: .configuration, search: $settingsSearch) {
            configCoreSection
            configMediaSection
            ContentModeSection(selection: $preferredContentMode)
            configBehaviorSection
            configDataDetectorsSection
            configPrivacySection
            resetSection
        }
        .navigationTitle(Text(verbatim: "Configuration"))
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
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Changes will reload WebView")
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
        allowsContentJavaScript = storedAllowsContentJavaScript
        minimumFontSize = SettingsFormatter.validMinimumFontSize(storedMinimumFontSize)
        mediaAutoplay = storedMediaAutoplay
        inlineMediaPlayback = storedInlineMediaPlayback
        allowsAirPlay = storedAllowsAirPlay
        allowsPictureInPicture = storedAllowsPictureInPicture
        preferredContentMode = storedPreferredContentMode
        allowZoom = storedAllowZoom
        javaScriptCanOpenWindows = storedJavaScriptCanOpenWindows
        fraudulentWebsiteWarning = storedFraudulentWebsiteWarning
        elementFullscreenEnabled = storedElementFullscreenEnabled
        suppressesIncrementalRendering = storedSuppressesIncrementalRendering
        detectPhoneNumbers = storedDetectPhoneNumbers
        detectLinks = storedDetectLinks
        detectAddresses = storedDetectAddresses
        detectCalendarEvents = storedDetectCalendarEvents
        privateBrowsing = storedPrivateBrowsing
        upgradeToHTTPS = storedUpgradeToHTTPS
    }

    private func applyChanges() {
        storedAllowsContentJavaScript = allowsContentJavaScript
        storedMinimumFontSize = SettingsFormatter.validMinimumFontSize(minimumFontSize)
        storedMediaAutoplay = mediaAutoplay
        storedInlineMediaPlayback = inlineMediaPlayback
        storedAllowsAirPlay = allowsAirPlay
        storedAllowsPictureInPicture = allowsPictureInPicture
        storedPreferredContentMode = preferredContentMode
        storedAllowZoom = allowZoom
        storedJavaScriptCanOpenWindows = javaScriptCanOpenWindows
        storedFraudulentWebsiteWarning = fraudulentWebsiteWarning
        storedElementFullscreenEnabled = elementFullscreenEnabled
        storedSuppressesIncrementalRendering = suppressesIncrementalRendering
        storedDetectPhoneNumbers = detectPhoneNumbers
        storedDetectLinks = detectLinks
        storedDetectAddresses = detectAddresses
        storedDetectCalendarEvents = detectCalendarEvents
        storedPrivateBrowsing = privateBrowsing
        storedUpgradeToHTTPS = upgradeToHTTPS

        // Update loadedURL to current page before reload
        if let currentURL = navigator.currentURL?.absoluteString {
            loadedURL = currentURL
        }

        webViewID = UUID()
        dismiss()
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

    // MARK: - Configuration Sections

    @ViewBuilder
    private var configCoreSection: some View {
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
                TextField("0", value: $minimumFontSize, format: .number)
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
    private var configMediaSection: some View {
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
    private var configBehaviorSection: some View {
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
                info: "Allows elements to enter fullscreen mode. Full API available on iPad only; iPhone is limited to video elements.",
                disabled: !isIPad
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
    private var configDataDetectorsSection: some View {
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
    private var configPrivacySection: some View {
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

    private func resetAllToDefaults() {
        // Core
        allowsContentJavaScript = true
        minimumFontSize = 0

        // Media
        mediaAutoplay = false
        inlineMediaPlayback = true
        allowsAirPlay = true
        allowsPictureInPicture = true

        // Content
        allowZoom = false
        suppressesIncrementalRendering = false
        javaScriptCanOpenWindows = false
        fraudulentWebsiteWarning = true
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
    }
}

struct ContentModeSection: View {
    @Binding var selection: Int

    var body: some View {
        Section {
            // Keep each option a list row when search rebuilds the section.
            option("Recommended", value: 0)
            option("Mobile", value: 1)
            option("Desktop", value: 2)
        } header: {
            Text(verbatim: "Content Mode")
        }
    }

    private func option(_ title: LocalizedStringKey, value: Int) -> some View {
        Button {
            selection = value
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
        .settingsSearchItem("preferredContentMode")
    }
}

#Preview("Configuration Settings") {
    @Previewable @State var id = UUID()
    @Previewable @State var url = "https://example.com"
    NavigationStack {
        ConfigurationSettingsView(
            webViewID: $id,
            loadedURL: $url,
            navigator: WebViewNavigator()
        )
    }
}
