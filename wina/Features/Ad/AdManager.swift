import GoogleMobileAds
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.walnut.wina", category: "AdManager")

// MARK: - Banner Ad View

struct BannerAdView: UIViewControllerRepresentable {
    let adUnitId: String
    let availableWidth: CGFloat

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let banner = BannerView()
        banner.adUnitID = adUnitId
        banner.delegate = context.coordinator
        banner.rootViewController = controller
        controller.view = banner
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard availableWidth > 0, let banner = controller.view as? BannerView else { return }
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: availableWidth)
        guard context.coordinator.requestedSize != adSize.size else { return }
        context.coordinator.requestedSize = adSize.size
        banner.adSize = adSize
        banner.load(Request())
    }

    func makeCoordinator() -> BannerCoordinator {
        BannerCoordinator()
    }

    class BannerCoordinator: NSObject, BannerViewDelegate {
        var requestedSize: CGSize?

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            logger.info("Banner ad loaded successfully")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            logger.error("Banner ad failed to load: \(error.localizedDescription)")
        }
    }
}

// MARK: - Ad Options

struct AdOptions {
    /// Unique identifier for tracking shown ads in memory.
    /// If an ad with this id has been shown once, it won't be shown again during the session.
    let id: String

    /// Probability of showing the ad (0.0 to 1.0). Default is 0.3 (30%).
    let probability: Double

    init(id: String, probability: Double = 0.3) {
        self.id = id
        self.probability = max(0.0, min(1.0, probability))
    }
}

// MARK: - Ad Manager

@MainActor
@Observable
final class AdManager: NSObject {
    static let shared = AdManager()

    // MARK: - Ad Unit IDs

    /// Interstitial ad unit ID (Production)
    static let interstitialAdUnitId = "ca-app-pub-6737616702687889/5962304852"

    /// Banner ad unit ID (Production) - Home screen bottom
    static let bannerAdUnitId = "ca-app-pub-6737616702687889/6596869296"

    /// Google's official test interstitial ad unit ID (always shows test ads)
    static let testInterstitialAdUnitId = "ca-app-pub-3940256099942544/4411468910"

    /// Google's official test banner ad unit ID (always shows test ads)
    static let testBannerAdUnitId = "ca-app-pub-3940256099942544/2435281174"

    private var interstitialAd: InterstitialAd?
    private var shownAdIds: Set<String> = []
    private var isLoading = false

    override private init() {
        super.init()
    }

    // MARK: - SDK Initialization

    func initialize() {
        MobileAds.shared.start()
    }

    // MARK: - Interstitial Ad

    /// Loads an interstitial ad with the given ad unit ID.
    /// - Parameter adUnitId: The AdMob ad unit ID for interstitial ads.
    /// - Note: Skips loading if user has purchased ad removal (no network request made).
    func loadInterstitialAd(adUnitId: String) async {
        // Skip loading if user purchased ad removal - no network request
        guard !StoreManager.shared.isAdRemoved else {
            logger.info("Ad loading skipped - user has premium")
            return
        }

        guard !isLoading else { return }
        isLoading = true

        do {
            interstitialAd = try await InterstitialAd.load(
                with: adUnitId,
                request: Request()
            )
            interstitialAd?.fullScreenContentDelegate = self
            logger.info("Interstitial ad loaded successfully")
        } catch {
            logger.error("Failed to load interstitial ad: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Shows an interstitial ad based on probability, if not already shown for the given options.id.
    /// - Parameters:
    ///   - options: Ad options containing the unique id and probability (default 30%).
    ///   - adUnitId: The AdMob ad unit ID. If ad is not loaded, it will be loaded first.
    /// - Returns: `true` if ad was shown, `false` if skipped (already shown, probability check failed) or failed.
    @discardableResult
    func showInterstitialAd(options: AdOptions, adUnitId: String) async -> Bool {
        logger.debug("showInterstitialAd called for id: \(options.id)")

        // Skip if user purchased ad removal
        guard !StoreManager.shared.isAdRemoved else {
            logger.debug("Ad skipped - user has premium")
            return false
        }

        // Skip if already shown for this id
        guard !shownAdIds.contains(options.id) else {
            logger.info("Ad already shown for id: \(options.id), skipping")
            return false
        }

        // Random probability check
        guard Double.random(in: 0.0..<1.0) < options.probability else {
            logger.info("Ad skipped by probability check (\(Int(options.probability * 100))%) for id: \(options.id)")
            return false
        }

        logger.debug("Ad passed probability check for id: \(options.id)")

        // Load ad if not available
        if interstitialAd == nil {
            logger.debug("No cached ad, loading new ad...")
            await loadInterstitialAd(adUnitId: adUnitId)
        }

        guard let ad = interstitialAd else {
            logger.warning("No ad available to show for id: \(options.id)")
            return false
        }

        // Find the topmost view controller (works with sheets)
        guard let viewController = Self.topMostViewController() else {
            logger.error("Could not find topmost view controller")
            return false
        }

        logger.info("Presenting ad for id: \(options.id) on \(type(of: viewController))")

        // Mark as shown and present
        shownAdIds.insert(options.id)
        ad.present(from: viewController)
        return true
    }

    /// Finds the topmost presented view controller (handles sheets and modals)
    private static func topMostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              var topController = window.rootViewController
        else {
            return nil
        }

        // Traverse up the presentation chain to find the topmost VC
        while let presented = topController.presentedViewController {
            topController = presented
        }

        return topController
    }

    /// Checks if an ad has been shown for the given id.
    /// - Parameter id: The unique identifier to check.
    /// - Returns: `true` if ad was already shown for this id.
    func hasShownAd(for id: String) -> Bool {
        shownAdIds.contains(id)
    }

    /// Resets the shown state for a specific id.
    /// - Parameter id: The unique identifier to reset.
    func resetShownState(for id: String) {
        shownAdIds.remove(id)
    }

    /// Resets all shown states.
    func resetAllShownStates() {
        shownAdIds.removeAll()
    }
}

// MARK: - FullScreenContentDelegate

extension AdManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            interstitialAd = nil
        }
    }

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        let errorMessage = error.localizedDescription
        Task { @MainActor in
            logger.error("Ad failed to present: \(errorMessage)")
            interstitialAd = nil
        }
    }

    nonisolated func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            logger.info("Ad will present")
        }
    }
}
