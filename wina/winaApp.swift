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
        Self.initializeWebViewSizeIfNeeded()

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

    static func initializeWebViewSizeIfNeeded(in defaults: UserDefaults = .standard) {
        let initializedKey = "hasInitializedWebViewSize"
        guard !defaults.bool(forKey: initializedKey) else { return }

        // Older builds stored the same ratio for an App preset and a custom height.
        for key in ["webViewHeightRatio", "safariHeightRatio"] where defaults.object(forKey: key) == nil {
            defaults.set(BarConstants.appHeightPreset, forKey: key)
        }
        defaults.set(true, forKey: initializedKey)
    }

    var body: some Scene {
        WindowGroup {
            GeometryReader { geometry in
                let containerSize = CGSize(
                    width: geometry.size.width,
                    height: geometry.size.height + geometry.safeAreaInsets.bottom
                )
                ContentView()
                    .environment(\.webViewContainerSize, containerSize)
                    .preferredColorScheme(preferredScheme)
                    .environment(\.locale, resolvedLocale)
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
