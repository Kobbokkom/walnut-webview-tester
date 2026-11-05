//
//  InfoView+SearchItems.swift
//  wina
//
//  Search item builders for InfoView.
//

import SwiftUI

// MARK: - Search Item Builders

extension InfoView {
    var activeSettingsItems: [InfoSearchItem] {
        [
            InfoSearchItem(category: "Active Settings", label: "Content JavaScript", value: allowsContentJavaScript ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Ignore Viewport Scale Limits", value: allowZoom ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Minimum Font Size", value: SettingsFormatter.minimumFontSizeText(minimumFontSize)),
            InfoSearchItem(category: "Active Settings", label: "Auto-play Media", value: mediaAutoplay ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Inline Playback", value: inlineMediaPlayback ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "AirPlay", value: allowsAirPlay ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Picture in Picture", value: allowsPictureInPicture ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Back/Forward Gestures", value: allowsBackForwardGestures ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Link Preview", value: allowsLinkPreview ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Content Mode", value: contentModeText),
            InfoSearchItem(category: "Active Settings", label: "JS Can Open Windows", value: javaScriptCanOpenWindows ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Fraudulent Website Warning", value: fraudulentWebsiteWarning ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Text Interaction", value: textInteractionEnabled ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Element Fullscreen API", value: elementFullscreenEnabled ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Suppress Incremental Rendering", value: suppressesIncrementalRendering ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Data Detectors", value: activeDataDetectors),
            InfoSearchItem(category: "Active Settings", label: "Private Browsing", value: privateBrowsing ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Upgrade to HTTPS", value: upgradeToHTTPS ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Custom User-Agent", value: customUserAgent.isEmpty ? "Default" : "Custom"),
            InfoSearchItem(category: "Active Settings", label: "Find Interaction", value: findInteractionEnabled ? "Enabled" : "Disabled"),
            InfoSearchItem(category: "Active Settings", label: "Page Zoom", value: "\(Int(pageZoom * 100))%"),
            InfoSearchItem(category: "Active Settings", label: "Under Page Background", value: underPageBackgroundColorHex.isEmpty ? "Default" : underPageBackgroundColorHex),
            InfoSearchItem(category: "Active Settings", label: "WebView Width", value: "\(Int(webViewWidthRatio * 100))%"),
            InfoSearchItem(category: "Active Settings", label: "WebView Height", value: "\(Int(webViewHeightRatio * 100))%")
        ]
    }

    func deviceItems(from info: DeviceInfo) -> [InfoSearchItem] {
        [
            InfoSearchItem(category: "Device", label: "Model", value: info.model),
            InfoSearchItem(category: "Device", label: "Model Identifier", value: info.modelIdentifier),
            InfoSearchItem(category: "Device", label: "System", value: "\(info.systemName) \(info.systemVersion)"),
            InfoSearchItem(category: "Device", label: "OS Build", value: info.osBuild),
            InfoSearchItem(category: "Device", label: "CPU Cores", value: info.cpuCores),
            InfoSearchItem(category: "Device", label: "Active Cores", value: info.activeCores),
            InfoSearchItem(category: "Device", label: "Physical Memory", value: info.physicalMemory),
            InfoSearchItem(category: "Device", label: "Thermal State", value: info.thermalState),
            InfoSearchItem(category: "Device", label: "GPU", value: info.gpuName),
            InfoSearchItem(category: "Device", label: "Screen Size", value: info.screenSize),
            InfoSearchItem(category: "Device", label: "Screen Scale", value: info.screenScale),
            InfoSearchItem(category: "Device", label: "Native Scale", value: info.nativeScale),
            InfoSearchItem(category: "Device", label: "Brightness", value: info.brightness),
            InfoSearchItem(category: "Device", label: "Language", value: info.language),
            InfoSearchItem(category: "Device", label: "Region", value: info.region),
            InfoSearchItem(category: "Device", label: "Timezone", value: info.timezone)
        ]
    }

    func browserItems(from info: WebViewInfo) -> [InfoSearchItem] {
        [
            InfoSearchItem(category: "Browser", label: "User Agent", value: info.userAgent),
            InfoSearchItem(category: "Browser", label: "Language", value: info.language),
            InfoSearchItem(category: "Browser", label: "Languages", value: info.languages),
            InfoSearchItem(category: "Browser", label: "Platform", value: info.platform),
            InfoSearchItem(category: "Browser", label: "Vendor", value: info.vendor),
            InfoSearchItem(category: "Browser", label: "WebKit Version", value: info.webKitVersion),
            InfoSearchItem(category: "Browser", label: "JavaScriptCore Version", value: info.jsCoreVersion),
            InfoSearchItem(category: "Browser", label: "Color Depth", value: info.colorDepth),
            InfoSearchItem(category: "Browser", label: "WebGL Renderer", value: info.webGLRenderer),
            InfoSearchItem(category: "Browser", label: "WebGL Vendor", value: info.webGLVendor),
            InfoSearchItem(category: "Browser", label: "WebGL Version", value: info.webGLVersion)
        ]
    }

    func apiItems(from info: WebViewInfo) -> [InfoSearchItem] {
        let apis: [(String, Bool, LocalizedStringKey?)] = [
            ("JavaScript", info.supportsJavaScript, nil),
            ("WebAssembly", info.supportsWebAssembly, nil),
            ("Web Workers", info.supportsWebWorkers, nil),
            ("Service Workers", info.supportsServiceWorkers, "Only in Safari or home screen web apps."),
            ("Shared Workers", info.supportsSharedWorkers, nil),
            ("WebGL", info.supportsWebGL, nil),
            ("WebGL 2", info.supportsWebGL2, nil),
            ("Web Audio", info.supportsWebAudio, nil),
            ("Media Devices", info.supportsMediaDevices, "Requires camera & microphone permission."),
            ("Media Recorder", info.supportsMediaRecorder, "Supports MP4 format only."),
            ("Media Source", info.supportsMediaSource, "iOS 17+ only."),
            ("Picture in Picture", info.supportsPictureInPicture, nil),
            ("Fullscreen", info.supportsFullscreen, "Video only on iPhone, full support on iPad."),
            ("Cookies", info.cookiesEnabled, nil),
            ("LocalStorage", info.supportsLocalStorage, "5MB limit per website."),
            ("SessionStorage", info.supportsSessionStorage, nil),
            ("IndexedDB", info.supportsIndexedDB, "Data may be cleared after 7 days of inactivity."),
            ("Cache API", info.supportsCacheAPI, "Data may be cleared after 7 days of inactivity."),
            ("Online", info.isOnline, nil),
            ("WebSocket", info.supportsWebSocket, nil),
            ("WebRTC", info.supportsWebRTC, "Requires camera & microphone permission."),
            ("Fetch", info.supportsFetch, nil),
            ("Beacon", info.supportsBeacon, nil),
            ("Event Source", info.supportsEventSource, "Real-time server updates."),
            ("Geolocation", info.supportsGeolocation, "Requires location permission."),
            ("Device Orientation", info.supportsDeviceOrientation, nil),
            ("Device Motion", info.supportsDeviceMotion, nil),
            ("Vibration", info.supportsVibration, "Not supported on iOS."),
            ("Battery", info.supportsBattery, "Not supported for privacy."),
            ("Bluetooth", info.supportsBluetooth, "Use native app instead."),
            ("USB", info.supportsUSB, "Use native app instead."),
            ("NFC", info.supportsNFC, "Use native app instead."),
            ("Clipboard", info.supportsClipboard, "Requires user interaction."),
            ("Web Share", info.supportsWebShare, "Requires HTTPS and user gesture. Safari only."),
            ("Notifications", info.supportsNotifications, "Only in Safari or home screen web apps."),
            ("Pointer Events", info.supportsPointerEvents, nil),
            ("Touch Events", info.supportsTouchEvents, nil),
            ("Gamepad", info.supportsGamepad, "Works with MFi controllers."),
            ("Drag and Drop", info.supportsDragDrop, "Full support on iPad only."),
            ("Intersection Observer", info.supportsIntersectionObserver, nil),
            ("Resize Observer", info.supportsResizeObserver, nil),
            ("Mutation Observer", info.supportsMutationObserver, nil),
            ("Performance Observer", info.supportsPerformanceObserver, nil),
            ("Crypto", info.supportsCrypto, "Requires HTTPS."),
            ("Credentials", info.supportsCredentials, nil),
            ("Payment Request", info.supportsPaymentRequest, "Apple Pay integration. Requires HTTPS.")
        ]
        return apis.map { label, supported, infoText in
            InfoSearchItem(category: "API", label: label, value: supported ? "Supported" : "Not Supported", info: infoText)
        }
    }

    func codecItems(from info: MediaCodecInfo) -> [InfoSearchItem] {
        var items: [InfoSearchItem] = []

        let videoCodecs: [(String, CodecSupport)] = [
            ("H.264 (AVC)", info.h264),
            ("H.265 (HEVC)", info.hevc),
            ("VP8", info.vp8),
            ("VP9", info.vp9),
            ("AV1", info.av1),
            ("Theora", info.theora)
        ]
        for (label, support) in videoCodecs {
            items.append(InfoSearchItem(category: "Video Codecs", label: label, value: support.displayValue))
        }

        let audioCodecs: [(String, CodecSupport)] = [
            ("AAC", info.aac),
            ("MP3", info.mp3),
            ("Opus", info.opus),
            ("Vorbis", info.vorbis),
            ("FLAC", info.flac),
            ("WAV (PCM)", info.wav)
        ]
        for (label, support) in audioCodecs {
            items.append(InfoSearchItem(category: "Audio Codecs", label: label, value: support.displayValue))
        }

        let containers: [(String, CodecSupport)] = [
            ("MP4", info.mp4),
            ("WebM", info.webm),
            ("Ogg", info.ogg),
            ("HLS", info.hls)
        ]
        for (label, support) in containers {
            items.append(InfoSearchItem(category: "Containers", label: label, value: support.displayValue))
        }

        return items
    }

    func displayItems(from info: DisplayInfo) -> [InfoSearchItem] {
        [
            InfoSearchItem(category: "Display", label: "Screen Width", value: info.screenWidth),
            InfoSearchItem(category: "Display", label: "Screen Height", value: info.screenHeight),
            InfoSearchItem(category: "Display", label: "Available Width", value: info.availWidth),
            InfoSearchItem(category: "Display", label: "Available Height", value: info.availHeight),
            InfoSearchItem(category: "Display", label: "Device Pixel Ratio", value: info.devicePixelRatio),
            InfoSearchItem(category: "Display", label: "Orientation", value: info.orientation),
            InfoSearchItem(category: "Display", label: "Color Depth", value: info.colorDepth),
            InfoSearchItem(category: "Display", label: "Pixel Depth", value: info.pixelDepth),
            InfoSearchItem(category: "Display", label: "sRGB", value: info.supportsSRGB ? "Supported" : "Not Supported"),
            InfoSearchItem(category: "Display", label: "Display P3", value: info.supportsP3 ? "Supported" : "Not Supported"),
            InfoSearchItem(category: "Display", label: "Rec.2020", value: info.supportsRec2020 ? "Supported" : "Not Supported"),
            InfoSearchItem(category: "Display", label: "HDR", value: info.supportsHDR ? "Supported" : "Not Supported"),
            InfoSearchItem(category: "Display", label: "Dynamic Range", value: info.dynamicRange),
            InfoSearchItem(category: "Display", label: "Color Scheme", value: info.colorScheme),
            InfoSearchItem(category: "Display", label: "Inverted Colors", value: info.invertedColors ? "Yes" : "No"),
            InfoSearchItem(category: "Display", label: "Forced Colors", value: info.forcedColors ? "Yes" : "No")
        ]
    }

    func accessibilityItems(from info: AccessibilityInfo) -> [InfoSearchItem] {
        [
            InfoSearchItem(category: "Accessibility", label: "Reduced Motion", value: info.reducedMotion),
            InfoSearchItem(category: "Accessibility", label: "Reduced Transparency", value: info.reducedTransparency),
            InfoSearchItem(category: "Accessibility", label: "Contrast", value: info.contrast),
            InfoSearchItem(category: "Accessibility", label: "Color Scheme", value: info.colorScheme),
            InfoSearchItem(category: "Accessibility", label: "Reduced Data", value: info.reducedData),
            InfoSearchItem(category: "Accessibility", label: "Prefers Reduced Data", value: info.prefersReducedData),
            InfoSearchItem(category: "Accessibility", label: "Inverted Colors", value: info.invertedColors),
            InfoSearchItem(category: "Accessibility", label: "Forced Colors", value: info.forcedColors),
            InfoSearchItem(category: "Accessibility", label: "Color Gamut", value: info.colorGamut),
            InfoSearchItem(category: "Accessibility", label: "Pointer Type", value: info.pointerType),
            InfoSearchItem(category: "Accessibility", label: "Any Pointer", value: info.anyPointer),
            InfoSearchItem(category: "Accessibility", label: "Hover", value: info.hover),
            InfoSearchItem(category: "Accessibility", label: "Any Hover", value: info.anyHover)
        ]
    }

    var performanceItems: [InfoSearchItem] {
        let perfPlaceholder = "Run benchmark"
        return [
            InfoSearchItem(category: "Performance", label: "Math", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "Array", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "String", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "Object", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "RegExp", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "DOM Create", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "DOM Query", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "DOM Modify", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "Canvas 2D", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "WebGL", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "Memory Allocation", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "Memory Operations", value: perfPlaceholder, linkToPerformance: true),
            InfoSearchItem(category: "Performance", label: "Crypto Hash", value: perfPlaceholder, linkToPerformance: true)
        ]
    }
}
