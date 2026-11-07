//
//  winaApp.swift
//  wina
//
//  Created by 박지원 on 12/6/25.
//

import AppTrackingTransparency
import os
import SwiftUI

@main
struct winaApp: App {
    /// nil = system, "light" = light mode, "dark" = dark mode
    @AppStorage("colorSchemeOverride") private var colorSchemeOverride: String?
    @AppStorage("appLanguage") private var appLanguage: String = ""

    private var preferredScheme: ColorScheme? {
        switch colorSchemeOverride {
        case "light": .light
        case "dark": .dark
        default: nil  // System
        }
    }

    private var resolvedLocale: Locale {
        appLanguage.isEmpty ? .current : Locale(identifier: appLanguage)
    }

    init() {
        Self.migrateContentJavaScriptPreference()

        // Clear network body cache from previous session (unless preserveLog is enabled)
        NetworkBodyStorage.shared.clearOnLaunchIfNeeded()

        // One-time removal of the legacy auto-generated preload "Native Bridge Demo Copy"
        PreloadProfileStore.removeLegacyGeneratedDemoCopyIfNeeded()

        // Initialize Google Mobile Ads SDK
        AdManager.shared.initialize()

        // Initialize StoreKit (starts transaction listener, checks entitlements)
        _ = StoreManager.shared

        // Request ATT authorization after a short delay, then preload ads
        Task.detached {
            // Give the app a moment to launch and UI to settle before showing the ATT prompt
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await MainActor.run {
                Self.requestATTAuthorization()
            }

            // Wait for StoreManager to check entitlements (determines if user is premium)
            await StoreManager.shared.checkEntitlements()

            // Preload interstitial ad after ATT prompt (skips if premium user)
            // This triggers local network permission prompt early (if needed by AdMob SDK)
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds after ATT
            await AdManager.shared.loadInterstitialAd(adUnitId: AdManager.interstitialAdUnitId)
        }
    }

    static func migrateContentJavaScriptPreference(in defaults: UserDefaults = .standard) {
        let legacyKey = "enableJavaScript"
        guard defaults.object(forKey: legacyKey) != nil else { return }

        let contentKey = "allowsContentJavaScript"
        let contentEnabled = defaults.object(forKey: contentKey) == nil || defaults.bool(forKey: contentKey)
        defaults.set(defaults.bool(forKey: legacyKey) && contentEnabled, forKey: contentKey)
        defaults.removeObject(forKey: legacyKey)
    }

    static func initializeWebViewSizeIfNeeded(knownHeights: [CGFloat], in defaults: UserDefaults = .standard) {
        let initializedKey = "hasInitializedWebViewSize"
        let migrationKey = "hasMigratedWebViewAppSize"
        guard !defaults.bool(forKey: migrationKey) else { return }

        for browser in ["webView", "safari"] {
            let widthKey = browser + "WidthRatio"
            let heightKey = browser + "HeightRatio"
            if defaults.bool(forKey: initializedKey) {
                guard let height = defaults.object(forKey: heightKey) as? Double else { continue }
                let width = defaults.object(forKey: widthKey) as? Double ?? 1
                let migrated = BarConstants.migratedHeightRatio(widthRatio: width, heightRatio: height, knownHeights: knownHeights)
                defaults.set(migrated, forKey: heightKey)
            } else {
                defaults.set(1.0, forKey: widthKey)
                defaults.set(BarConstants.appHeightPreset, forKey: heightKey)
            }
        }
        defaults.set(true, forKey: initializedKey)
        defaults.set(true, forKey: migrationKey)
    }

    var body: some Scene {
        WindowGroup {
            GeometryReader { geometry in
                let containerSize = CGSize(
                    width: geometry.size.width,
                    height: geometry.size.height + geometry.safeAreaInsets.bottom
                )
                let fullSize = CGSize(
                    width: containerSize.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                    height: containerSize.height + geometry.safeAreaInsets.top
                )
                ContentView()
                    .environment(\.webViewContainerSize, containerSize)
                    .preferredColorScheme(preferredScheme)
                    .environment(\.locale, resolvedLocale)
                    .onChange(of: fullSize, initial: true) { _, size in
                        guard size.height > 0, size.width > 0 else { return }
                        Self.initializeWebViewSizeIfNeeded(knownHeights: [containerSize.height, size.height, size.width])
                    }
                    .onOpenURL { url in
                        CallbackTestManager.shared.handleIncomingURL(url)
                    }
                    .callbackResultSheet()
            }
        }
    }

    private static func requestATTAuthorization() {
        ATTrackingManager.requestTrackingAuthorization { status in
            let logger = Logger(subsystem: "com.walnut.wina", category: "ATT")
            switch status {
            case .authorized:
                logger.info("User granted tracking permission")
            case .denied:
                logger.info("User denied tracking permission")
            case .notDetermined:
                logger.debug("Tracking permission not determined")
            case .restricted:
                logger.info("Tracking permission restricted")
            @unknown default:
                logger.warning("Unknown tracking authorization status")
            }
        }
    }
}
