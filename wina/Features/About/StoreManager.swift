//
//  StoreManager.swift
//  wina
//

import StoreKit

@Observable
final class StoreManager {
    static let shared = StoreManager()

    private(set) var isAdRemoved = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var product: Product?

    private var updateListenerTask: Task<Void, Never>?

    private let productID = "removeAds"
    private let storeService: StoreServiceProtocol

#if DEBUG
    private let debugAdRemovalOverrideKey = "debugAdRemovalOverride"
#endif

    private init(storeService: StoreServiceProtocol = RealStoreService.shared) {
        self.storeService = storeService

        // Start listening for transaction updates (refunds, background purchases, etc.)
        updateListenerTask = listenForTransactions()

        // Process unfinished transactions and check entitlements on init
        Task {
            await processUnfinishedTransactions()
            await checkEntitlements()
            await fetchProduct()
        }
    }

#if DEBUG
    /// Test-only initializer for dependency injection
    static func createForTesting(storeService: StoreServiceProtocol) -> StoreManager {
        StoreManager(storeService: storeService)
    }
#endif

    // MARK: - Fetch Product

    /// Fetch product info to display price
    @MainActor
    func fetchProduct() async {
        do {
            let products = try await storeService.fetchProducts(for: [productID])
            product = products.first
        } catch {
            // Silently fail - price just won't be displayed
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates (refunds, Ask to Buy approvals, etc.)
    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await update in self.storeService.transactionUpdates()
                where update.productID == self.productID {
                    self.isAdRemoved = !update.isRevoked
#if DEBUG
                    if self.debugAdRemovalOverride {
                        self.isAdRemoved = true
                    }
#endif
            }
        }
    }

    // MARK: - Unfinished Transactions

    /// Process any unfinished transactions from previous sessions
    @MainActor
    private func processUnfinishedTransactions() async {
        if let result = await storeService.processUnfinishedTransactions(for: productID) {
            isAdRemoved = result.isAdRemoved
#if DEBUG
            if debugAdRemovalOverride {
                isAdRemoved = true
            }
#endif
        }
    }

    // MARK: - Entitlements Check

    /// Check current entitlements (call on app launch)
    @MainActor
    func checkEntitlements() async {
        await processUnfinishedTransactions()

        let result = await storeService.checkEntitlement(for: productID)

        if result.wasRevoked {
            isAdRemoved = false
            return
        }

        isAdRemoved = result.hasEntitlement

#if DEBUG
        if debugAdRemovalOverride {
            isAdRemoved = true
        }
#endif
    }

    // MARK: - Purchase

    @MainActor
    func purchaseAdRemoval() async {
        isLoading = true
        errorMessage = nil

        do {
            // Use cached product or fetch if not available
            let purchaseProduct: Product
            if let cached = product {
                purchaseProduct = cached
            } else {
                let products = try await storeService.fetchProducts(for: [productID])
                guard let fetched = products.first else {
                    errorMessage = String.app("Product not available")
                    isLoading = false
                    return
                }
                purchaseProduct = fetched
                product = fetched
            }

            let result = try await storeService.purchase(purchaseProduct)
            await handle(purchaseResult: result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await storeService.sync()
            await checkEntitlements()

            if !isAdRemoved {
                errorMessage = String.app("No purchases to restore")
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Handle Results

    @MainActor
    private func handle(purchaseResult: Product.PurchaseResult) async {
        switch purchaseResult {
        case .success(let verification):
            await handle(transactionResult: verification)
        case .userCancelled:
            break
        case .pending:
            errorMessage = String.app("Purchase is pending approval")
        @unknown default:
            errorMessage = String.app("Unknown error occurred")
        }
    }

    @MainActor
    private func handle(transactionResult: VerificationResult<Transaction>) async {
        switch transactionResult {
        case .verified(let transaction):
            if transaction.productID == productID {
                // Check if revoked (refunded)
                if transaction.revocationDate != nil {
                    isAdRemoved = false
                } else {
                    isAdRemoved = true
                }
            }
            // IMPORTANT: Always finish the transaction
            await transaction.finish()

#if DEBUG
            if debugAdRemovalOverride {
                isAdRemoved = true
            }
#endif
        case .unverified:
            errorMessage = String.app("Purchase could not be verified")
        }
    }

#if DEBUG
    var debugAdRemovalOverride: Bool {
        get {
            UserDefaults.standard.bool(forKey: debugAdRemovalOverrideKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: debugAdRemovalOverrideKey)
        }
    }

    @MainActor
    func enableAdRemovalForDebug() {
        debugAdRemovalOverride = true
        errorMessage = nil
        isAdRemoved = true
    }

    @MainActor
    func resetAdRemovalForDebug() async {
        debugAdRemovalOverride = false
        errorMessage = nil
        await checkEntitlements()
    }
#endif
}
