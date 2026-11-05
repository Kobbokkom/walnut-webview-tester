//
//  DisplayFeaturesView.swift
//  wina
//

import SwiftUI

// MARK: - Display Features View

struct DisplayFeaturesView: View {
    @State private var displayInfo: DisplayInfo?
    @State private var loadingStatus = "Launching WebView process..."

    var body: some View {
        List {
            if let info = displayInfo {
                Section("Screen") {
                    InfoRow(label: "Width", value: info.screenWidth)
                    InfoRow(label: "Height", value: info.screenHeight)
                    InfoRow(
                        label: "Aspect Ratio", value: info.aspectRatio,
                        info: "Width to height ratio.\nCalculated using GCD for clean display.")
                    InfoRow(
                        label: "Available Width", value: info.availWidth,
                        info: "Screen width minus system UI elements.")
                    InfoRow(
                        label: "Available Height", value: info.availHeight,
                        info: "Screen height minus system UI elements.")
                    InfoRow(
                        label: "Device Pixel Ratio", value: info.devicePixelRatio,
                        info: "CSS pixels to device pixels ratio.")
                    InfoRow(label: "Orientation", value: info.orientation)
                }

                Section("Color") {
                    InfoRow(
                        label: "Color Depth", value: info.colorDepth,
                        info: "Bits per pixel for color.\n24-bit = 16.7M colors\n30-bit = 1B colors (HDR)")
                    InfoRow(
                        label: "Pixel Depth", value: info.pixelDepth,
                        info: "Bits per pixel including alpha.\nUsually equals Color Depth.")
                    CapabilityRow(
                        label: "sRGB", supported: info.supportsSRGB,
                        info: "Standard color space.\nCovers ~35% of visible colors.\nUsed by most web content.")
                    CapabilityRow(
                        label: "Display-P3", supported: info.supportsP3,
                        info: "Wide gamut (~25% more than sRGB).\nAll iPhones since iPhone 7.\nVivid reds, greens, oranges.")
                    CapabilityRow(
                        label: "Rec. 2020", supported: info.supportsRec2020,
                        info: "Ultra-wide gamut (~75% of visible).\nPro Display XDR, some iPad Pro.\niPhone: Not supported yet.")
                }

                Section("HDR") {
                    CapabilityRow(
                        label: "HDR Display", supported: info.supportsHDR,
                        info:
                            "High Dynamic Range display.\nBrighter highlights, deeper blacks.\niPhone 12+ supports HDR10/Dolby Vision.",
                        icon: "sparkles", iconColor: .yellow)
                    InfoRow(label: "Dynamic Range", value: info.dynamicRange)
                }

                Section("Media Queries") {
                    CapabilityRow(
                        label: "Inverted Colors", supported: info.invertedColors,
                        info: "Settings > Accessibility > Display.\nInverts all screen colors.\nCSS: prefers-color-scheme alternative."
                    )
                    CapabilityRow(
                        label: "Forced Colors", supported: info.forcedColors,
                        info: "High contrast mode.\niOS: Not used (Windows feature).\nCSS: forced-colors media query.")
                }
            }
        }
        .overlay {
            if displayInfo == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Display"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            displayInfo = await DisplayInfo.load { status in
                loadingStatus = status
            }
        }
    }
}

// MARK: - Display Info Model

struct DisplayInfo: Sendable {
    // Screen
    let screenWidth: String
    let screenHeight: String
    let aspectRatio: String
    let availWidth: String
    let availHeight: String
    let devicePixelRatio: String
    let orientation: String

    // Color
    let colorDepth: String
    let pixelDepth: String
    let supportsSRGB: Bool
    let supportsP3: Bool
    let supportsRec2020: Bool

    // HDR
    let supportsHDR: Bool
    let dynamicRange: String

    // Media Queries
    let colorScheme: String
    let invertedColors: Bool
    let forcedColors: Bool

    static let empty = DisplayInfo(
        screenWidth: "N/A", screenHeight: "N/A", aspectRatio: "N/A",
        availWidth: "N/A", availHeight: "N/A", devicePixelRatio: "N/A", orientation: "N/A",
        colorDepth: "N/A", pixelDepth: "N/A",
        supportsSRGB: false, supportsP3: false, supportsRec2020: false,
        supportsHDR: false, dynamicRange: "N/A",
        colorScheme: "N/A", invertedColors: false, forcedColors: false
    )

    // MARK: - Load Function

    @MainActor
    static func load(onStatusUpdate: @escaping (String) -> Void) async -> DisplayInfo {
        let shared = SharedInfoWebView.shared

        if let cached = shared.cachedDisplayInfo {
            onStatusUpdate("Using cached data...")
            return cached
        }

        // Initialize shared WebView (or use live WebView if available)
        let generation = shared.cacheGeneration
        await shared.initialize(onStatusUpdate: onStatusUpdate)

        onStatusUpdate("Detecting display features...")
        let result = await shared.evaluateJavaScript(detectionScript) as? [String: Any] ?? [:]

        let displayResult = parseResult(from: result)
        if shared.cacheGeneration == generation {
            shared.cachedDisplayInfo = displayResult
        }
        return displayResult
    }

    // MARK: - Result Parsing

    private static func parseResult(from result: [String: Any]) -> DisplayInfo {
        DisplayInfo(
            screenWidth: formatPx(result["screenWidth"]),
            screenHeight: formatPx(result["screenHeight"]),
            aspectRatio: calculateAspectRatio(width: result["screenWidth"], height: result["screenHeight"]),
            availWidth: formatPx(result["availWidth"]),
            availHeight: formatPx(result["availHeight"]),
            devicePixelRatio: "\(result["devicePixelRatio"] as? Double ?? 1.0)x",
            orientation: result["orientation"] as? String ?? "Unknown",
            colorDepth: "\(result["colorDepth"] as? Int ?? 0) bit",
            pixelDepth: "\(result["pixelDepth"] as? Int ?? 0) bit",
            supportsSRGB: result["supportsSRGB"] as? Bool ?? false,
            supportsP3: result["supportsP3"] as? Bool ?? false,
            supportsRec2020: result["supportsRec2020"] as? Bool ?? false,
            supportsHDR: result["supportsHDR"] as? Bool ?? false,
            dynamicRange: result["dynamicRange"] as? String ?? "Unknown",
            colorScheme: result["colorScheme"] as? String ?? "Unknown",
            invertedColors: result["invertedColors"] as? Bool ?? false,
            forcedColors: result["forcedColors"] as? Bool ?? false
        )
    }

    private static func formatPx(_ value: Any?) -> String {
        pixelCount(value).map { "\($0) px" } ?? "N/A"
    }

    private static func pixelCount(_ value: Any?) -> Int? {
        if let count = value as? Int { return count }
        guard let number = value as? Double else { return nil }
        return Int(exactly: number.rounded(.towardZero))
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    private static func calculateAspectRatio(width: Any?, height: Any?) -> String {
        guard let w = pixelCount(width), let h = pixelCount(height), w > 0, h > 0 else { return "N/A" }
        let divisor = gcd(w, h)
        return "\(w / divisor):\(h / divisor)"
    }

    // MARK: - Detection Script
    // swiftlint:disable line_length
    private static let detectionScript = """
    (function() {
        function mq(query) { return window.matchMedia(query).matches; }
        var orientation = 'Unknown';
        if (screen.orientation) { orientation = screen.orientation.type; }
        else if (window.orientation !== undefined) { orientation = Math.abs(window.orientation) === 90 ? 'landscape' : 'portrait'; }
        return {
            screenWidth: screen.width, screenHeight: screen.height, availWidth: screen.availWidth, availHeight: screen.availHeight,
            devicePixelRatio: window.devicePixelRatio, orientation: orientation,
            colorDepth: screen.colorDepth, pixelDepth: screen.pixelDepth,
            supportsSRGB: mq('(color-gamut: srgb)'), supportsP3: mq('(color-gamut: p3)'), supportsRec2020: mq('(color-gamut: rec2020)'),
            supportsHDR: mq('(dynamic-range: high)'), dynamicRange: mq('(dynamic-range: high)') ? 'High (HDR)' : 'Standard (SDR)',
            colorScheme: mq('(prefers-color-scheme: dark)') ? 'Dark' : 'Light',
            invertedColors: mq('(inverted-colors: inverted)'), forcedColors: mq('(forced-colors: active)')
        };
    })()
    """
    // swiftlint:enable line_length
}
