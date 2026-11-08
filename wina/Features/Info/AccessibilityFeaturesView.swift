//
//  AccessibilityFeaturesView.swift
//  wina
//

import SwiftUI

// MARK: - Accessibility Features View

struct AccessibilityFeaturesView: View {
    @State private var a11yInfo: AccessibilityInfo?
    @State private var loadingStatus = "Launching WebView process..."

    var body: some View {
        List {
            if let info = a11yInfo {
                Section("User Preferences") {
                    InfoRow(label: "Reduced Motion", value: info.reducedMotion)
                    InfoRow(label: "Reduced Transparency", value: info.reducedTransparency)
                    InfoRow(label: "Contrast", value: info.contrast)
                    HStack {
                        Text("Color Scheme")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: info.colorScheme == "Dark" ? "moon.fill" : "sun.max.fill")
                            .foregroundStyle(info.colorScheme == "Dark" ? .indigo : .orange)
                        Text(info.colorScheme)
                    }
                }

                Section("Data & Power") {
                    InfoRow(label: "Reduced Data", value: info.reducedData)
                    InfoRow(label: "Prefers Reduced Data", value: info.prefersReducedData)
                }

                Section("Display") {
                    InfoRow(label: "Inverted Colors", value: info.invertedColors)
                    InfoRow(label: "Forced Colors", value: info.forcedColors)
                    InfoRow(label: "Color Gamut", value: info.colorGamut)
                }

                Section("Pointer & Input") {
                    InfoRow(label: "Pointer Type", value: info.pointerType)
                    InfoRow(label: "Any Pointer", value: info.anyPointer)
                    InfoRow(label: "Hover", value: info.hover)
                    InfoRow(label: "Any Hover", value: info.anyHover)
                }
            }
        }
        .overlay {
            if a11yInfo == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Accessibility"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            a11yInfo = await AccessibilityInfo.load { status in
                loadingStatus = status
            }
        }
    }
}

// MARK: - Accessibility Info Model

struct AccessibilityInfo: Sendable, Encodable {
    // User Preferences
    let reducedMotion: String
    let reducedTransparency: String
    let contrast: String
    let colorScheme: String

    // Data & Power
    let reducedData: String
    let prefersReducedData: String

    // Display
    let invertedColors: String
    let forcedColors: String
    let colorGamut: String

    // Pointer & Input
    let pointerType: String
    let anyPointer: String
    let hover: String
    let anyHover: String

    static let empty = AccessibilityInfo(
        reducedMotion: "N/A", reducedTransparency: "N/A", contrast: "N/A", colorScheme: "N/A",
        reducedData: "N/A", prefersReducedData: "N/A",
        invertedColors: "N/A", forcedColors: "N/A", colorGamut: "N/A",
        pointerType: "N/A", anyPointer: "N/A", hover: "N/A", anyHover: "N/A"
    )

    @MainActor
    static func load(
        using shared: SharedInfoWebView = .shared,
        onStatusUpdate: @escaping (String) -> Void
    ) async -> AccessibilityInfo {
        // Return cached if available
        if let cached = shared.cachedAccessibilityInfo {
            onStatusUpdate("Using cached data...")
            return cached
        }

        // Initialize shared WebView (or use live WebView if available)
        let generation = shared.cacheGeneration
        await shared.initialize(onStatusUpdate: onStatusUpdate)

        onStatusUpdate("Detecting accessibility preferences...")
        let script = """
        (function() {
            function mq(query) {
                return window.matchMedia(query).matches;
            }

            function detectValue(queries) {
                for (var i = 0; i < queries.length; i++) {
                    if (mq(queries[i].query)) return queries[i].value;
                }
                return 'no-preference';
            }

            return {
                // User Preferences
                reducedMotion: mq('(prefers-reduced-motion: reduce)') ? 'Reduce' : 'No Preference',
                reducedTransparency: mq('(prefers-reduced-transparency: reduce)') ? 'Reduce' : 'No Preference',
                contrast: detectValue([
                    { query: '(prefers-contrast: more)', value: 'More' },
                    { query: '(prefers-contrast: less)', value: 'Less' },
                    { query: '(prefers-contrast: custom)', value: 'Custom' }
                ]),
                colorScheme: mq('(prefers-color-scheme: dark)') ? 'Dark' : 'Light',

                // Data & Power
                reducedData: mq('(prefers-reduced-data: reduce)') ? 'Reduce' : 'No Preference',
                prefersReducedData: 'connection' in navigator && navigator.connection.saveData ? 'Enabled' : 'Disabled',

                // Display
                invertedColors: mq('(inverted-colors: inverted)') ? 'Inverted' : 'None',
                forcedColors: mq('(forced-colors: active)') ? 'Active' : 'None',
                colorGamut: detectValue([
                    { query: '(color-gamut: rec2020)', value: 'Rec. 2020' },
                    { query: '(color-gamut: p3)', value: 'Display-P3' },
                    { query: '(color-gamut: srgb)', value: 'sRGB' }
                ]),

                // Pointer & Input
                pointerType: detectValue([
                    { query: '(pointer: fine)', value: 'Fine (mouse/stylus)' },
                    { query: '(pointer: coarse)', value: 'Coarse (touch)' },
                    { query: '(pointer: none)', value: 'None' }
                ]),
                anyPointer: detectValue([
                    { query: '(any-pointer: fine)', value: 'Fine available' },
                    { query: '(any-pointer: coarse)', value: 'Coarse only' },
                    { query: '(any-pointer: none)', value: 'None' }
                ]),
                hover: mq('(hover: hover)') ? 'Supported' : 'Not supported',
                anyHover: mq('(any-hover: hover)') ? 'Available' : 'Not available'
            };
        })()
        """

        let result = await shared.evaluateJavaScript(script) as? [String: String] ?? [:]

        let a11yResult = AccessibilityInfo(
            reducedMotion: result["reducedMotion"] ?? "Unknown",
            reducedTransparency: result["reducedTransparency"] ?? "Unknown",
            contrast: result["contrast"] ?? "Unknown",
            colorScheme: result["colorScheme"] ?? "Unknown",
            reducedData: result["reducedData"] ?? "Unknown",
            prefersReducedData: result["prefersReducedData"] ?? "Unknown",
            invertedColors: result["invertedColors"] ?? "Unknown",
            forcedColors: result["forcedColors"] ?? "Unknown",
            colorGamut: result["colorGamut"] ?? "Unknown",
            pointerType: result["pointerType"] ?? "Unknown",
            anyPointer: result["anyPointer"] ?? "Unknown",
            hover: result["hover"] ?? "Unknown",
            anyHover: result["anyHover"] ?? "Unknown"
        )

        // Cache result
        if shared.cacheGeneration == generation {
            shared.cachedAccessibilityInfo = a11yResult
        }
        return a11yResult
    }
}
