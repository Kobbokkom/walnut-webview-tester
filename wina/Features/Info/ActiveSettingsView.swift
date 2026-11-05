//
//  ActiveSettingsView.swift
//  wina
//

import AVFoundation
import CoreLocation
import SwiftUI
import SwiftUIBackports

// MARK: - Active Settings View

struct ActiveSettingsView: View {
    @Binding var showSettings: Bool

    // Permission status
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined

    // Configuration Settings (require WebView reload)
    @AppStorage("enableJavaScript") private var enableJavaScript: Bool = true
    @AppStorage("allowsContentJavaScript") private var allowsContentJavaScript: Bool = true
    @AppStorage("minimumFontSize") private var minimumFontSize: Double = 0
    @AppStorage("mediaAutoplay") private var mediaAutoplay: Bool = false
    @AppStorage("inlineMediaPlayback") private var inlineMediaPlayback: Bool = true
    @AppStorage("allowsAirPlay") private var allowsAirPlay: Bool = true
    @AppStorage("allowsPictureInPicture") private var allowsPictureInPicture: Bool = true
    @AppStorage("preferredContentMode") private var preferredContentMode: Int = 0
    @AppStorage("allowZoom") private var allowZoom: Bool = false
    @AppStorage("javaScriptCanOpenWindows") private var javaScriptCanOpenWindows: Bool = false
    @AppStorage("fraudulentWebsiteWarning") private var fraudulentWebsiteWarning: Bool = true
    @AppStorage("elementFullscreenEnabled") private var elementFullscreenEnabled: Bool = false
    @AppStorage("suppressesIncrementalRendering") private var suppressesIncrementalRendering: Bool = false
    @AppStorage("detectPhoneNumbers") private var detectPhoneNumbers: Bool = false
    @AppStorage("detectLinks") private var detectLinks: Bool = false
    @AppStorage("detectAddresses") private var detectAddresses: Bool = false
    @AppStorage("detectCalendarEvents") private var detectCalendarEvents: Bool = false
    @AppStorage("privateBrowsing") private var privateBrowsing: Bool = false
    @AppStorage("upgradeToHTTPS") private var upgradeToHTTPS: Bool = true

    // Live Settings (instant apply)
    @AppStorage("allowsBackForwardGestures") private var allowsBackForwardGestures: Bool = false
    @AppStorage("allowsLinkPreview") private var allowsLinkPreview: Bool = true
    @AppStorage("textInteractionEnabled") private var textInteractionEnabled: Bool = true
    @AppStorage("findInteractionEnabled") private var findInteractionEnabled: Bool = false
    @AppStorage("pageZoom") private var pageZoom: Double = 1.0
    @AppStorage("underPageBackgroundColor") private var underPageBackgroundColorHex: String = ""
    @AppStorage("customUserAgent") private var customUserAgent: String = ""
    @AppStorage("webViewWidthRatio") private var webViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") private var webViewHeightRatio: Double = 0.82

    private var isIPad: Bool {
        UIDevice.current.isIPad
    }

    private var contentModeText: String {
        SettingsFormatter.contentModeText(preferredContentMode)
    }

    private var activeDataDetectors: String {
        SettingsFormatter.activeDataDetectors(
            phone: detectPhoneNumbers,
            links: detectLinks,
            address: detectAddresses,
            calendar: detectCalendarEvents
        )
    }

    @Environment(\.webViewContainerSize) private var containerSize

    private var webViewSizeText: String {
        let w = Int(containerSize.width * webViewWidthRatio)
        let h = Int(containerSize.height * webViewHeightRatio)
        return "\(w) × \(h)"
    }

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

            // MARK: - Live Settings
            Section {
                ActiveSettingRow(
                    label: "Back/Forward Gestures", enabled: allowsBackForwardGestures,
                    info: "Swipe to go back/forward.\nOff = Use buttons only.\nAvoids conflicts with page gestures.")
                ActiveSettingRow(
                    label: "Link Preview", enabled: allowsLinkPreview,
                    info: "Preview links before opening.\nLong-press or 3D Touch.\nSee page without leaving.")
                ActiveSettingRow(
                    label: "Text Interaction", enabled: textInteractionEnabled,
                    info: "Select and copy text.\nOff = No text selection.\nDisable for game-like pages.")
                ActiveSettingRow(
                    label: "Find Interaction", enabled: findInteractionEnabled,
                    info: "System find panel.\nCmd+F on iPad with keyboard.\nSearch text in page.")
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)
                    Text(verbatim: "Live Settings")
                }
            }

            Section {
                InfoRow(
                    label: "Page Zoom", value: "\(Int(pageZoom * 100))%",
                    info: "Scale of page content.\n100% = Default size.\nUseful for small text.")
                InfoRow(
                    label: "Under Page Background",
                    value: underPageBackgroundColorHex.isEmpty ? "Default" : underPageBackgroundColorHex,
                    info: "Background color shown when scrolling beyond page bounds.")
            } header: {
                Text("Display")
            }

            Section {
                if customUserAgent.isEmpty {
                    InfoRow(label: "Status", value: "Default")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom")
                            .foregroundStyle(.secondary)
                        Text(customUserAgent)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(verbatim: "Identity")
            }

            Section {
                InfoRow(
                    label: "Width", value: "\(Int(webViewWidthRatio * 100))%",
                    info: "WebView width ratio.\n100% = Full screen width.")
                InfoRow(
                    label: "Height", value: "\(Int(webViewHeightRatio * 100))%",
                    info: "WebView height ratio.\n100% = Full screen height.")
                InfoRow(
                    label: "Dimensions", value: webViewSizeText,
                    info: "Current WebView size in points.")
            } header: {
                Text("WebView Size")
            }

            // MARK: - Configuration Settings
            Section {
                ActiveSettingRow(
                    label: "JavaScript", enabled: enableJavaScript,
                    info: "Enable/disable all JavaScript.\nOff = No scripts run at all.\nMost websites won't work.")
                ActiveSettingRow(
                    label: "Content JavaScript", enabled: allowsContentJavaScript,
                    info: "Scripts from web pages.\nOff = Block page scripts only.\nApp features still work.")
                InfoRow(
                    label: "Minimum Font Size",
                    value: minimumFontSize == 0 ? "Default" : "\(Int(minimumFontSize)) pt",
                    info: "Minimum text size.\nMakes small text readable.\n0 = Use page's font sizes.")
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.orange)
                    Text("Configuration")
                }
            }

            Section {
                ActiveSettingRow(
                    label: "Auto-play Media", enabled: mediaAutoplay,
                    info: "Videos play automatically.\nOff = Tap to play videos.\nSaves battery and data.")
                ActiveSettingRow(
                    label: "Inline Playback", enabled: inlineMediaPlayback,
                    info: "Play videos in page.\nOff = Always fullscreen.\nNeeded for background videos.")
                ActiveSettingRow(
                    label: "AirPlay", enabled: allowsAirPlay,
                    info: "Stream to Apple TV.\nOff = Hide AirPlay button.\nFor local-only playback.")
                ActiveSettingRow(
                    label: "Picture in Picture", enabled: allowsPictureInPicture,
                    info: "Floating video window.\nWatch while using other apps.\nSwipe up or tap button.")
            } header: {
                Text("Media")
            }

            Section {
                InfoRow(
                    label: "Mode", value: contentModeText,
                    info: "Mobile or desktop sites.\nRecommended: Auto-detect.\nDesktop useful on iPad.")
            } header: {
                Text(verbatim: "Content Mode")
            }

            Section {
                ActiveSettingRow(
                    label: "Ignore Viewport Scale Limits", enabled: allowZoom,
                    info: "Force pinch-to-zoom.\nOverrides pages that disable zoom.\nBetter accessibility.")
                ActiveSettingRow(
                    label: "JS Can Open Windows", enabled: javaScriptCanOpenWindows,
                    info: "Allow popup windows.\nOff = Block popups.\nSome sites need this on.")
                ActiveSettingRow(
                    label: "Fraudulent Website Warning", enabled: fraudulentWebsiteWarning,
                    info: "Warn about dangerous sites.\nPhishing and malware alerts.\nKeep on for safety.")
                ActiveSettingRow(
                    label: "Element Fullscreen API", enabled: elementFullscreenEnabled,
                    info: isIPad
                        ? "iPad: Full fullscreen support.\nAny element can go fullscreen.\nVideos, games, presentations."
                        : "iPhone: Video fullscreen only.\nFull API on iPad only.\nVideos still work normally.",
                    unavailable: !isIPad)
                ActiveSettingRow(
                    label: "Suppress Incremental Rendering", enabled: suppressesIncrementalRendering,
                    info: "Wait for full page load.\nCleaner appearance.\nFeels slower to load.")
            } header: {
                Text("Behavior")
            }

            Section {
                InfoRow(
                    label: "Active", value: activeDataDetectors,
                    info: "Auto-link special content.\nPhone numbers, addresses, dates.\nTap to call, map, or add event.")
            } header: {
                Text("Data Detectors")
            }

            Section {
                ActiveSettingRow(
                    label: "Private Browsing", enabled: privateBrowsing,
                    info: "No history saved.\nCookies cleared on exit.\nLike incognito mode.")
                ActiveSettingRow(
                    label: "Upgrade to HTTPS", enabled: upgradeToHTTPS,
                    info: "Auto-secure connections.\nHTTP → HTTPS upgrade.\nProtects your data.")
            } header: {
                Text("Privacy & Security")
            }

            Section {
                PermissionStatusRow(
                    label: "Camera",
                    status: cameraStatus,
                    info: "Required for Media Devices API.\nWebRTC video calls.\nQR code scanning."
                )
                PermissionStatusRow(
                    label: "Microphone",
                    status: microphoneStatus,
                    info: "Required for Media Devices API.\nWebRTC audio calls.\nVoice recording."
                )
                PermissionStatusRow(
                    label: "Location",
                    status: locationStatus,
                    info: "Required for Geolocation API.\nMaps and navigation.\nLocation-based services."
                )
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.blue)
                    Text("Permissions")
                }
            }
        }
        .navigationTitle(Text(verbatim: "Active Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updatePermissionStatuses()
        }
    }

    private func updatePermissionStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        locationStatus = CLLocationManager().authorizationStatus
    }
}
