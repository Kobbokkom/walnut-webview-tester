//
//  BrowserInfoView.swift
//  wina
//

import os
import SwiftUI
import WebKit

// MARK: - Browser Information View

struct BrowserInfoView: View {
    @State private var webViewInfo: WebViewInfo?
    @State private var loadingStatus = "Launching WebView process..."

    private func flagEmoji(for languageCode: String) -> String? {
        let components = languageCode.split(separator: "-")
        guard components.count >= 2,
              let region = components.last,
              region.count == 2 else { return nil }
        let base: UInt32 = 127397
        var flag = ""
        for scalar in String(region).uppercased().unicodeScalars {
            guard let unicode = UnicodeScalar(base + scalar.value) else { return nil }
            flag.append(Character(unicode))
        }
        return flag
    }

    var body: some View {
        List {
            if let info = webViewInfo {
                Section("Browser") {
                    InfoRow(label: "Type", value: info.browserType)
                    InfoRow(label: "Vendor", value: info.vendor)
                    InfoRow(label: "Platform", value: info.platform)
                    HStack {
                        Text("Language")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let flag = flagEmoji(for: info.language) {
                            Text(flag)
                        }
                        Text(info.language)
                            .textSelection(.enabled)
                    }
                    InfoRow(label: "Languages", value: info.languages)
                }

                Section("Engine") {
                    InfoRow(
                        label: "WebKit Version", value: info.webKitVersion,
                        info: "Safari's rendering engine.\nShared across all iOS browsers.\nUpdated with iOS releases.")
                    InfoRow(
                        label: "JavaScript Core", value: info.jsCoreVersion,
                        info: "Apple's JS engine (Nitro).\nJIT compilation for speed.\nSame engine as Safari.")
                }

                Section("User Agent") {
                    UserAgentText(userAgent: info.userAgent)
                }

                Section("WebGL") {
                    InfoRow(label: "Renderer", value: info.webGLRenderer)
                    InfoRow(label: "Vendor", value: info.webGLVendor)
                    InfoRow(label: "Version", value: info.webGLVersion)
                }

                Section("Input") {
                    InfoRow(
                        label: "Max Touch Points", value: info.maxTouchPoints,
                        info: "Max simultaneous touches.\niPhone/iPad: Usually 5.\nAffects multi-touch gestures.")
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
        .navigationTitle(Text(verbatim: "Browser"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            webViewInfo = await WebViewInfo.load { status in
                loadingStatus = status
            }
        }
    }
}

// MARK: - WebView Info Model

struct WebViewInfo: Sendable, Encodable {
    // Browser
    let browserType: String
    let vendor: String
    let platform: String
    let language: String
    let languages: String

    // Engine
    let userAgent: String
    let webKitVersion: String
    let jsCoreVersion: String

    // Display
    let colorDepth: String

    // WebGL
    let webGLRenderer: String
    let webGLVendor: String
    let webGLVersion: String

    // Core APIs
    let supportsJavaScript: Bool
    let supportsWebAssembly: Bool
    let supportsWebWorkers: Bool
    let supportsServiceWorkers: Bool
    let supportsSharedWorkers: Bool

    // Graphics & Media
    let supportsWebGL: Bool
    let supportsWebGL2: Bool
    let supportsWebAudio: Bool
    let supportsMediaDevices: Bool
    let supportsMediaRecorder: Bool
    let supportsMediaSource: Bool
    let supportsPictureInPicture: Bool
    let supportsFullscreen: Bool

    // Storage
    let cookiesEnabled: Bool
    let supportsLocalStorage: Bool
    let supportsSessionStorage: Bool
    let supportsIndexedDB: Bool
    let supportsCacheAPI: Bool

    // Network
    let isOnline: Bool
    let supportsWebSocket: Bool
    let supportsWebRTC: Bool
    let supportsFetch: Bool
    let supportsBeacon: Bool
    let supportsEventSource: Bool

    // Device APIs
    let supportsGeolocation: Bool
    let supportsDeviceOrientation: Bool
    let supportsDeviceMotion: Bool
    let supportsVibration: Bool
    let supportsBattery: Bool
    let supportsBluetooth: Bool
    let supportsUSB: Bool
    let supportsNFC: Bool

    // UI & Interaction
    let supportsClipboard: Bool
    let supportsWebShare: Bool
    let supportsNotifications: Bool
    let supportsPointerEvents: Bool
    let supportsTouchEvents: Bool
    let supportsGamepad: Bool
    let supportsDragDrop: Bool

    // Observers
    let supportsIntersectionObserver: Bool
    let supportsResizeObserver: Bool
    let supportsMutationObserver: Bool
    let supportsPerformanceObserver: Bool

    // Security & Payments
    let isSecureContext: Bool
    let supportsCrypto: Bool
    let supportsCredentials: Bool
    let supportsPaymentRequest: Bool

    // Input
    let maxTouchPoints: String

    static let empty = WebViewInfo(
        browserType: "N/A", vendor: "N/A", platform: "N/A", language: "N/A", languages: "N/A",
        userAgent: "N/A", webKitVersion: "N/A", jsCoreVersion: "N/A", colorDepth: "N/A",
        webGLRenderer: "N/A", webGLVendor: "N/A", webGLVersion: "N/A",
        supportsJavaScript: false, supportsWebAssembly: false, supportsWebWorkers: false,
        supportsServiceWorkers: false, supportsSharedWorkers: false,
        supportsWebGL: false, supportsWebGL2: false, supportsWebAudio: false,
        supportsMediaDevices: false, supportsMediaRecorder: false, supportsMediaSource: false,
        supportsPictureInPicture: false, supportsFullscreen: false,
        cookiesEnabled: false, supportsLocalStorage: false, supportsSessionStorage: false,
        supportsIndexedDB: false, supportsCacheAPI: false,
        isOnline: false, supportsWebSocket: false, supportsWebRTC: false,
        supportsFetch: false, supportsBeacon: false, supportsEventSource: false,
        supportsGeolocation: false, supportsDeviceOrientation: false, supportsDeviceMotion: false,
        supportsVibration: false, supportsBattery: false, supportsBluetooth: false,
        supportsUSB: false, supportsNFC: false,
        supportsClipboard: false, supportsWebShare: false, supportsNotifications: false,
        supportsPointerEvents: false, supportsTouchEvents: false, supportsGamepad: false,
        supportsDragDrop: false,
        supportsIntersectionObserver: false, supportsResizeObserver: false,
        supportsMutationObserver: false, supportsPerformanceObserver: false,
        isSecureContext: false, supportsCrypto: false, supportsCredentials: false, supportsPaymentRequest: false,
        maxTouchPoints: "0"
    )

    // MARK: - Load Function

    @MainActor
    static func load(
        using webView: SharedInfoWebView? = nil,
        onStatusUpdate: @escaping (String) -> Void
    ) async -> WebViewInfo {
        let shared = webView ?? .shared
        if let cached = shared.cachedWebViewInfo {
            onStatusUpdate("Using cached data...")
            return cached
        }

        // Initialize shared WebView (or use live WebView if available)
        let generation = shared.cacheGeneration
        await shared.initialize(onStatusUpdate: onStatusUpdate)

        onStatusUpdate("Detecting capabilities...")
        let allData = await shared.evaluateJavaScript(detectionScript) as? [String: Any] ?? [:]

        let result = parseResult(from: allData)
        if shared.cacheGeneration == generation {
            shared.cachedWebViewInfo = result
        }
        return result
    }

    // MARK: - JavaScript Detection Script

    private static let detectionScript = """
    (function() {
        var isSecure = window.isSecureContext;
        var webGLInfo = { renderer: 'N/A', vendor: 'N/A', version: 'N/A' };
        try {
            var canvas = document.createElement('canvas');
            var gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
            if (gl) {
                var debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
                webGLInfo = {
                    renderer: debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
                    vendor: debugInfo ? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR),
                    version: gl.getParameter(gl.VERSION)
                };
            }
        } catch(e) {}

        function supportsWritableStorage(getStorage) {
            try {
                var storage = getStorage();
                var key = '__walnut_storage_probe_' + Date.now() + '_' + Math.random();
                if (storage.getItem(key) !== null) return false;
                storage.setItem(key, '1');
                storage.removeItem(key);
                return true;
            } catch(e) { return false; }
        }

        return {
            browser: {
                userAgent: navigator.userAgent,
                vendor: navigator.vendor || 'Unknown',
                platform: navigator.platform || 'Unknown',
                language: navigator.language || 'Unknown',
                languages: (navigator.languages || []).join(', ') || 'Unknown',
                colorDepth: screen.colorDepth + ' bit',
                isOnline: navigator.onLine,
                maxTouchPoints: navigator.maxTouchPoints || 0
            },
            webGL: webGLInfo,
            caps: {
                javaScript: true,
                webAssembly: typeof WebAssembly !== 'undefined',
                webWorkers: (function() {
                    try { var b = new Blob([''], { type: 'application/javascript' }); var u = URL.createObjectURL(b); var w = new Worker(u); w.terminate(); URL.revokeObjectURL(u); return true; } catch(e) { return false; }
                })(),
                serviceWorkers: 'serviceWorker' in navigator,
                sharedWorkers: typeof SharedWorker !== 'undefined',
                webGL: typeof WebGLRenderingContext !== 'undefined',
                webGL2: typeof WebGL2RenderingContext !== 'undefined',
                webAudio: typeof AudioContext !== 'undefined' || typeof webkitAudioContext !== 'undefined',
                mediaDevices: !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia),
                mediaRecorder: typeof MediaRecorder !== 'undefined',
                mediaSource: typeof ManagedMediaSource !== 'undefined' || typeof MediaSource !== 'undefined',
                pictureInPicture: 'pictureInPictureEnabled' in document,
                fullscreen: !!document.documentElement.requestFullscreen || !!document.documentElement.webkitRequestFullscreen,
                cookies: navigator.cookieEnabled,
                localStorage: supportsWritableStorage(function() { return window.localStorage; }),
                sessionStorage: supportsWritableStorage(function() { return window.sessionStorage; }),
                indexedDB: (function() { try { return typeof indexedDB !== 'undefined' && indexedDB !== null; } catch(e) { return false; } })(),
                cacheAPI: (function() { try { return 'caches' in window && typeof caches.open === 'function'; } catch(e) { return false; } })(),
                webSocket: typeof WebSocket !== 'undefined',
                webRTC: typeof RTCPeerConnection !== 'undefined',
                fetch: typeof fetch !== 'undefined',
                beacon: 'sendBeacon' in navigator,
                eventSource: typeof EventSource !== 'undefined',
                geolocation: 'geolocation' in navigator,
                deviceOrientation: 'DeviceOrientationEvent' in window,
                deviceMotion: 'DeviceMotionEvent' in window,
                vibration: 'vibrate' in navigator,
                battery: 'getBattery' in navigator,
                bluetooth: 'bluetooth' in navigator,
                usb: 'usb' in navigator,
                nfc: 'NDEFReader' in window,
                clipboard: (function() { if (navigator.clipboard && navigator.clipboard.writeText) return true; return document.queryCommandSupported && document.queryCommandSupported('copy'); })(),
                webShare: 'share' in navigator,
                notifications: 'Notification' in window && Notification.permission !== 'denied',
                pointerEvents: 'PointerEvent' in window,
                touchEvents: 'ontouchstart' in window,
                gamepad: 'getGamepads' in navigator,
                dragDrop: 'draggable' in document.createElement('div'),
                intersectionObserver: typeof IntersectionObserver !== 'undefined',
                resizeObserver: typeof ResizeObserver !== 'undefined',
                mutationObserver: typeof MutationObserver !== 'undefined',
                performanceObserver: typeof PerformanceObserver !== 'undefined',
                isSecureContext: isSecure,
                crypto: isSecure && !!(window.crypto && window.crypto.subtle),
                credentials: isSecure && 'credentials' in navigator,
                paymentRequest: isSecure && typeof PaymentRequest !== 'undefined'
            }
        };
    })()
    """

    // MARK: - Result Parsing

    private static func parseResult(from allData: [String: Any]) -> WebViewInfo {
        let browserInfo = parseBrowserInfo(from: allData)
        let webGLInfo = parseWebGLInfo(from: allData)
        let caps = allData["caps"] as? [String: Bool] ?? [:]

        return WebViewInfo(
            browserType: "WKWebView",
            vendor: browserInfo.vendor,
            platform: browserInfo.platform,
            language: browserInfo.language,
            languages: browserInfo.languages,
            userAgent: browserInfo.userAgent,
            webKitVersion: browserInfo.webKitVersion,
            jsCoreVersion: "JavaScriptCore \(UIDevice.current.systemVersion)",
            colorDepth: browserInfo.colorDepth,
            webGLRenderer: webGLInfo.renderer,
            webGLVendor: webGLInfo.vendor,
            webGLVersion: webGLInfo.version,
            supportsJavaScript: caps["javaScript"] ?? false,
            supportsWebAssembly: caps["webAssembly"] ?? false,
            supportsWebWorkers: caps["webWorkers"] ?? false,
            supportsServiceWorkers: caps["serviceWorkers"] ?? false,
            supportsSharedWorkers: caps["sharedWorkers"] ?? false,
            supportsWebGL: caps["webGL"] ?? false,
            supportsWebGL2: caps["webGL2"] ?? false,
            supportsWebAudio: caps["webAudio"] ?? false,
            supportsMediaDevices: caps["mediaDevices"] ?? false,
            supportsMediaRecorder: caps["mediaRecorder"] ?? false,
            supportsMediaSource: caps["mediaSource"] ?? false,
            supportsPictureInPicture: caps["pictureInPicture"] ?? false,
            supportsFullscreen: caps["fullscreen"] ?? false,
            cookiesEnabled: caps["cookies"] ?? false,
            supportsLocalStorage: caps["localStorage"] ?? false,
            supportsSessionStorage: caps["sessionStorage"] ?? false,
            supportsIndexedDB: caps["indexedDB"] ?? false,
            supportsCacheAPI: caps["cacheAPI"] ?? false,
            isOnline: browserInfo.isOnline,
            supportsWebSocket: caps["webSocket"] ?? false,
            supportsWebRTC: caps["webRTC"] ?? false,
            supportsFetch: caps["fetch"] ?? false,
            supportsBeacon: caps["beacon"] ?? false,
            supportsEventSource: caps["eventSource"] ?? false,
            supportsGeolocation: caps["geolocation"] ?? false,
            supportsDeviceOrientation: caps["deviceOrientation"] ?? false,
            supportsDeviceMotion: caps["deviceMotion"] ?? false,
            supportsVibration: caps["vibration"] ?? false,
            supportsBattery: caps["battery"] ?? false,
            supportsBluetooth: caps["bluetooth"] ?? false,
            supportsUSB: caps["usb"] ?? false,
            supportsNFC: caps["nfc"] ?? false,
            supportsClipboard: caps["clipboard"] ?? false,
            supportsWebShare: caps["webShare"] ?? false,
            supportsNotifications: caps["notifications"] ?? false,
            supportsPointerEvents: caps["pointerEvents"] ?? false,
            supportsTouchEvents: caps["touchEvents"] ?? false,
            supportsGamepad: caps["gamepad"] ?? false,
            supportsDragDrop: caps["dragDrop"] ?? false,
            supportsIntersectionObserver: caps["intersectionObserver"] ?? false,
            supportsResizeObserver: caps["resizeObserver"] ?? false,
            supportsMutationObserver: caps["mutationObserver"] ?? false,
            supportsPerformanceObserver: caps["performanceObserver"] ?? false,
            isSecureContext: caps["isSecureContext"] ?? false,
            supportsCrypto: caps["crypto"] ?? false,
            supportsCredentials: caps["credentials"] ?? false,
            supportsPaymentRequest: caps["paymentRequest"] ?? false,
            maxTouchPoints: browserInfo.maxTouchPoints
        )
    }

    private struct ParsedBrowserInfo {
        let userAgent: String
        let vendor: String
        let platform: String
        let language: String
        let languages: String
        let colorDepth: String
        let isOnline: Bool
        let maxTouchPoints: String
        let webKitVersion: String
    }

    private static func parseBrowserInfo(from allData: [String: Any]) -> ParsedBrowserInfo {
        let browser = allData["browser"] as? [String: Any] ?? [:]
        let userAgent = browser["userAgent"] as? String ?? "Unknown"
        let maxTouchPoints = browser["maxTouchPoints"] as? Int ?? 0

        var webKitVersion = "Unknown"
        if let range = userAgent.range(of: "AppleWebKit/") {
            let start = range.upperBound
            if let end = userAgent[start...].firstIndex(of: " ") {
                webKitVersion = String(userAgent[start..<end])
            }
        }

        return ParsedBrowserInfo(
            userAgent: userAgent,
            vendor: browser["vendor"] as? String ?? "Unknown",
            platform: browser["platform"] as? String ?? "Unknown",
            language: browser["language"] as? String ?? "Unknown",
            languages: browser["languages"] as? String ?? "Unknown",
            colorDepth: browser["colorDepth"] as? String ?? "Unknown",
            isOnline: browser["isOnline"] as? Bool ?? false,
            maxTouchPoints: "\(maxTouchPoints)",
            webKitVersion: webKitVersion
        )
    }

    private static func parseWebGLInfo(from allData: [String: Any]) -> (renderer: String, vendor: String, version: String) {
        let webGL = allData["webGL"] as? [String: String] ?? [:]
        return (
            renderer: webGL["renderer"] ?? "N/A",
            vendor: webGL["vendor"] ?? "N/A",
            version: webGL["version"] ?? "N/A"
        )
    }
}
