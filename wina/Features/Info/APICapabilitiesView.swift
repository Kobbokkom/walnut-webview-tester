//
//  APICapabilitiesView.swift
//  wina
//

import SwiftUI

// MARK: - API Capabilities View

struct APICapabilitiesView: View {
    @State private var webViewInfo: WebViewInfo?
    @State private var loadingStatus: LocalizedStringKey = "Launching WebView process..."

    private var isIPad: Bool {
        UIDevice.current.isIPad
    }

    private var capabilities: [CapabilitySection] {
        guard let info = webViewInfo else { return [] }
        return [
            CapabilitySection(name: "Core APIs", items: [
                CapabilityItem(label: "JavaScript", supported: info.supportsJavaScript),
                CapabilityItem(label: "WebAssembly", supported: info.supportsWebAssembly),
                CapabilityItem(label: "Web Workers", supported: info.supportsWebWorkers),
                CapabilityItem(
                    label: "Service Workers", supported: info.supportsServiceWorkers,
                    info: "Background scripts for offline.\nOnly in Safari or home screen apps.\nNot available in embedded browsers.",
                    unavailable: true),
                CapabilityItem(label: "Shared Workers", supported: info.supportsSharedWorkers)
            ]),
            CapabilitySection(name: "Graphics & Media", items: [
                CapabilityItem(label: "WebGL", supported: info.supportsWebGL),
                CapabilityItem(label: "WebGL 2", supported: info.supportsWebGL2),
                CapabilityItem(label: "Web Audio", supported: info.supportsWebAudio),
                CapabilityItem(
                    label: "Media Devices", supported: info.supportsMediaDevices,
                    info: "Camera and microphone access.\nRequires user permission.\nUsed for video calls, recording."),
                CapabilityItem(
                    label: "Media Recorder", supported: info.supportsMediaRecorder,
                    info: "Record audio/video streams.\niOS: MP4/H.264 only.\nWebM/VP8 not supported."),
                CapabilityItem(
                    label: "Media Source", supported: info.supportsMediaSource,
                    info: "MSE for adaptive streaming.\niOS 17+: ManagedMediaSource.\nOlder iOS: Not supported."),
                CapabilityItem(
                    label: "Picture in Picture", supported: info.supportsPictureInPicture,
                    info: "Video plays in floating window.\nWorks on video elements.\nUser must initiate."),
                CapabilityItem(
                    label: "Fullscreen", supported: info.supportsFullscreen,
                    info: isIPad
                        ? "iPad: Full support.\nAny element can go fullscreen.\nVideos, games, presentations."
                        : "iPhone: Not supported.\nOnly videos can go fullscreen.\niPad has full API support.",
                    unavailable: !isIPad)
            ]),
            CapabilitySection(name: "Storage", items: [
                CapabilityItem(
                    label: "Cookies", supported: info.cookiesEnabled,
                    info: "Website cookies enabled.\nStores login sessions, preferences.\nPrivate mode clears on exit."),
                CapabilityItem(
                    label: "LocalStorage", supported: info.supportsLocalStorage,
                    info: "Persistent key-value storage.\n~5MB limit per website.\nSurvives browser restart."),
                CapabilityItem(
                    label: "SessionStorage", supported: info.supportsSessionStorage,
                    info: "Tab-scoped storage.\nCleared when tab closes.\nSame origin policy applies."),
                CapabilityItem(
                    label: "IndexedDB", supported: info.supportsIndexedDB,
                    info: "Client-side database.\nData may clear after 7 days idle.\nLarger storage than LocalStorage."),
                CapabilityItem(
                    label: "Cache API", supported: info.supportsCacheAPI,
                    info: "Service Worker cache storage.\nData may clear after 7 days idle.\nGood for offline resources.")
            ]),
            CapabilitySection(name: "Network", items: [
                CapabilityItem(
                    label: "Online", supported: info.isOnline,
                    info: "navigator.onLine status.\nDevice network connectivity.\nMay not reflect actual internet.",
                    icon: "wifi", iconColor: .blue),
                CapabilityItem(
                    label: "WebSocket", supported: info.supportsWebSocket,
                    info: "Full-duplex communication.\nPersistent connection to server.\nGood for real-time apps."),
                CapabilityItem(
                    label: "WebRTC", supported: info.supportsWebRTC,
                    info: "Peer-to-peer communication.\nNeeds camera/mic permissions.\nVideo calls, screen sharing."),
                CapabilityItem(
                    label: "Fetch", supported: info.supportsFetch,
                    info: "Modern HTTP requests API.\nPromise-based, replaces XHR.\nSupports streaming."),
                CapabilityItem(
                    label: "Beacon", supported: info.supportsBeacon,
                    info: "Send data on page unload.\nGuaranteed delivery attempt.\nGood for analytics."),
                CapabilityItem(
                    label: "Event Source", supported: info.supportsEventSource,
                    info: "Server-Sent Events (SSE).\nOne-way server → client.\nAuto-reconnection built-in.")
            ]),
            CapabilitySection(name: "Device APIs", items: [
                CapabilityItem(
                    label: "Geolocation", supported: info.supportsGeolocation,
                    info: "GPS/network location access.\nRequires user permission.\nUsed for maps, local search."),
                CapabilityItem(
                    label: "Device Orientation", supported: info.supportsDeviceOrientation,
                    info: "Gyroscope data access.\nalpha/beta/gamma rotation.\niOS 13+: User permission needed."),
                CapabilityItem(
                    label: "Device Motion", supported: info.supportsDeviceMotion,
                    info: "Accelerometer data access.\naccelerationIncludingGravity.\niOS 13+: User permission needed."),
                CapabilityItem(
                    label: "Vibration", supported: info.supportsVibration,
                    info: "Haptic feedback from websites.\niOS: Not supported for privacy.\nNative apps can use haptics.",
                    unavailable: true),
                CapabilityItem(
                    label: "Battery", supported: info.supportsBattery,
                    info: "Battery level info for websites.\niOS: Not supported for privacy.\nPrevents device fingerprinting.",
                    unavailable: true),
                CapabilityItem(
                    label: "Bluetooth", supported: info.supportsBluetooth,
                    info: "Connect Bluetooth devices.\niOS: Not supported in browsers.\nUse native apps instead.",
                    unavailable: true),
                CapabilityItem(
                    label: "USB", supported: info.supportsUSB,
                    info: "Connect USB devices.\niOS: Not supported in browsers.\nUse native apps instead.",
                    unavailable: true),
                CapabilityItem(
                    label: "NFC", supported: info.supportsNFC,
                    info: "Read/write NFC tags.\niOS: Not supported in browsers.\nUse native apps instead.",
                    unavailable: true)
            ]),
            CapabilitySection(name: "UI & Interaction", items: [
                CapabilityItem(
                    label: "Clipboard", supported: info.supportsClipboard,
                    info: "Async clipboard API.\nNeeds user gesture to write.\nRead may need permission."),
                CapabilityItem(
                    label: "Web Share", supported: info.supportsWebShare,
                    info: "Native iOS share sheet.\nOnly in Safari browser.\nShare links, text, files.",
                    unavailable: true),
                CapabilityItem(
                    label: "Notifications", supported: info.supportsNotifications,
                    info: "Push notifications from websites.\nOnly in Safari or home screen apps.\niOS 16.4+ required.",
                    unavailable: true),
                CapabilityItem(
                    label: "Pointer Events", supported: info.supportsPointerEvents,
                    info: "Unified input events.\nMouse, touch, pen combined.\nModern event handling."),
                CapabilityItem(
                    label: "Touch Events", supported: info.supportsTouchEvents,
                    info: "Multi-touch support.\ntouchstart/move/end events.\niOS native touch handling."),
                CapabilityItem(
                    label: "Gamepad", supported: info.supportsGamepad,
                    info: "Game controller input.\nMFi controllers supported.\nPS/Xbox may work too."),
                CapabilityItem(
                    label: "Drag and Drop", supported: info.supportsDragDrop,
                    info: isIPad
                        ? "iPad: Full drag/drop support.\nBetween apps, within app.\nSplit View compatible."
                        : "iPhone: Limited support.\nGesture conflicts with scroll.\niPad recommended.",
                    unavailable: !isIPad)
            ]),
            CapabilitySection(name: "Observers", items: [
                CapabilityItem(
                    label: "Intersection Observer", supported: info.supportsIntersectionObserver,
                    info: "Element visibility detection.\nLazy loading, infinite scroll.\nPerformant scroll handling."),
                CapabilityItem(
                    label: "Resize Observer", supported: info.supportsResizeObserver,
                    info: "Element size changes.\nResponsive components.\nBetter than window.resize."),
                CapabilityItem(
                    label: "Mutation Observer", supported: info.supportsMutationObserver,
                    info: "DOM change detection.\nReplaces Mutation Events.\nAttribute, child, subtree."),
                CapabilityItem(
                    label: "Performance Observer", supported: info.supportsPerformanceObserver,
                    info: "Performance metrics.\nLCP, FID, CLS measurement.\nReal user monitoring.")
            ]),
            CapabilitySection(name: "Security & Payments", items: [
                CapabilityItem(
                    label: "Secure Context", supported: info.isSecureContext,
                    info: "HTTPS or localhost origin.\nRequired for many modern APIs.\nProtects sensitive operations.",
                    icon: "lock.fill", iconColor: .green),
                CapabilityItem(
                    label: "Crypto", supported: info.supportsCrypto,
                    info: "Web Cryptography API.\nHashing, encryption, signing.\nHTTPS required for full API."),
                CapabilityItem(
                    label: "Credentials", supported: info.supportsCredentials,
                    info: "Credential Management API.\nPasswords, federated login.\nLimited iOS support."),
                CapabilityItem(
                    label: "Payment Request", supported: info.supportsPaymentRequest,
                    info: "Standardized checkout API.\nApple Pay integration.\nHTTPS + merchant setup needed.")
            ])
        ]
    }

    var body: some View {
        List {
            ForEach(capabilities) { section in
                Section(section.name) {
                    ForEach(section.items) { item in
                        CapabilityRow(
                            label: item.label, supported: item.supported, info: item.info,
                            unavailable: item.unavailable, icon: item.icon, iconColor: item.iconColor)
                    }
                }
            }
        }
        .overlay {
            if webViewInfo == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "API Capabilities"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            webViewInfo = await WebViewInfo.load { status in
                loadingStatus = status
            }
        }
    }
}
