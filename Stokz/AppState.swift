import SwiftUI

/// AppState manages global app state and coordinates between services
@MainActor
class AppState: ObservableObject {
    
    static let shared = AppState()
    
    // MARK: - Services
    let authService = AuthenticationService.shared
    let sheetsService = GoogleSheetsService.shared
    let priceService = StockPriceService.shared
    let portfolioManager = PortfolioManager.shared
    
    // MARK: - State
    @Published var isInitialized = false
    @Published var isLoading = false
    @Published var error: String?
    
    @Published var currentUserPortfolio: Portfolio?
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var allStocksWithOwners: [StockWithOwners] = []
    
    // Timer for price updates
    private var priceUpdateTimer: Timer?
    // Timer for full data refresh (users, portfolios)
    private var dataRefreshTimer: Timer?
    
    // MARK: - Initialization
    func initialize() async {
        logInfo("🚀 App initialization starting", category: .app)
        isLoading = true
        
        // Pre-load stock data bundle (this parses the 770KB JSON once at startup)
        // Accessing the singleton triggers lazy init - do this early to avoid UI lag later
        let _ = StockDataService.shared
        logInfo("📦 Stock data service initialized: \(StockDataService.shared.stockCount) stocks", category: .app)
        
        // Load saved credentials
        logDebug("Loading saved credentials", category: .app)
        authService.loadCredentials()
        
        // Try to restore session if we have tokens
        if authService.getAccessToken() != nil {
            logInfo("Found existing access token, attempting to refresh", category: .auth)
            // Try to refresh and verify the token
            do {
                try await authService.refreshAccessToken()
                // Fetch user info to restore currentUser
                await authService.fetchUserInfo()
                authService.isAuthenticated = true
                logSuccess("Session restored successfully", category: .auth)
                await loadAllData()
            } catch {
                // Token expired or invalid, user needs to sign in again
                logWarning("Token refresh failed, signing out: \(error.localizedDescription)", category: .auth)
                authService.signOut()
            }
        } else {
            logInfo("No existing credentials found - user needs to sign in", category: .auth)
        }
        
        isInitialized = true
        isLoading = false
        logSuccess("🚀 App initialization complete", category: .app)
        
        // Start price update timer
        startPriceUpdates()
    }
    
    // MARK: - Handle Return to Foreground
    /// Called when app returns from background - refreshes stale data and validates session
    func handleReturnToForeground() async {
        print("🔄 [App] handleReturnToForeground - checking session and refreshing data")
        
        guard authService.isAuthenticated else {
            print("🔄 [App] Not authenticated, skipping refresh")
            return
        }
        
        // 1. Validate/refresh the auth token (may have expired while in background)
        do {
            print("🔄 [App] Refreshing access token...")
            try await authService.refreshAccessToken()
            print("🔄 [App] Token refresh successful")
        } catch {
            print("🔄 [App] ❌ Token refresh failed: \(error.localizedDescription)")
            // Token is invalid/expired - sign out and let user re-auth
            logWarning("Session expired while in background, signing out", category: .auth)
            authService.signOut()
            return
        }
        
        // 2. Reload all data (portfolios, prices, etc.)
        print("🔄 [App] Reloading all data...")
        await loadAllData()
        
        // 3. Restart timers (iOS may have invalidated them)
        print("🔄 [App] Restarting price update timers")
        startPriceUpdates()
        
        print("🔄 [App] ✅ Foreground refresh complete")
    }
    
    // MARK: - Load All Data
    func loadAllData() async {
        logInfo("Loading all data from backend", category: .app)
        isLoading = true
        error = nil
        
        do {
            try await sheetsService.fetchAllData()
            
            // Get all unique stock symbols
            let symbols = getAllStockSymbols()
            logInfo("Found \(symbols.count) unique stock symbols in portfolios", category: .app)
            await priceService.refreshAllPrices(for: symbols)
            
            updateDerivedState()
            
            // Record snapshots for all users (throttled to once per hour)
            await recordSnapshotsForAllUsers()
            
            logSuccess("All data loaded successfully", category: .app)
        } catch GoogleSheetsError.notAuthenticated {
            // 403 error - token doesn't have proper scopes, force re-auth
            logError("Sheets access denied - forcing re-authentication", category: .app)
            authService.signOut()
            self.error = "Session expired. Please sign in again."
        } catch {
            logError("Failed to load data: \(error.localizedDescription)", category: .app)
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Update Derived State
    private func updateDerivedState() {
        guard let userId = authService.currentUser?.id else {
            logDebug("No current user, skipping derived state update", category: .app)
            return
        }
        
        logDebug("Updating derived state for user: \(userId)", category: .app)
        print("🔄 updateDerivedState for user: \(userId)")
        
        // DON'T overwrite currentUserPortfolio here - it may have optimistic updates
        // Only update if we don't have one yet
        if currentUserPortfolio == nil {
            currentUserPortfolio = sheetsService.getPortfolio(for: userId)
            print("🔄 Set currentUserPortfolio from sheets")
        } else {
            print("🔄 Keeping existing currentUserPortfolio (optimistic)")
        }
        
        // Log current portfolio state for debugging
        if let portfolio = currentUserPortfolio {
            print("📦 Portfolio: \(portfolio.holdings.count) holdings, cash=$\(portfolio.cashBalance)")
            for h in portfolio.holdings {
                print("   📈 \(h.symbol): \(h.shares) shares @ entry $\(h.entryPrice)")
            }
            let netWorth = portfolioManager.calculateNetWorth(portfolio: portfolio, prices: priceService.prices)
            print("💰 CALCULATED NET WORTH: $\(netWorth)")
            logInfo("💰 Portfolio state: \(portfolio.holdings.count) holdings, cash: $\(String(format: "%.2f", portfolio.cashBalance)), NET WORTH: $\(String(format: "%.2f", netWorth))", category: .portfolio)
            for holding in portfolio.holdings {
                let price = priceService.prices[holding.symbol] ?? 0
                let value = holding.shares * price
                logDebug("  📊 \(holding.symbol): \(String(format: "%.4f", holding.shares)) shares @ $\(String(format: "%.2f", price)) = $\(String(format: "%.2f", value))", category: .portfolio)
            }
        }
        
        // Update leaderboard
        leaderboard = portfolioManager.generateLeaderboard(
            users: sheetsService.users,
            portfolios: sheetsService.portfolios,
            prices: priceService.prices
        )
        logDebug("Leaderboard updated with \(leaderboard.count) entries", category: .app)
        
        // Update all stocks with owners
        // Merge sheetsService.portfolios with current user's optimistic portfolio
        var portfoliosWithOptimistic = sheetsService.portfolios
        if let userId = authService.currentUser?.id, let optimisticPortfolio = currentUserPortfolio {
            portfoliosWithOptimistic[userId] = optimisticPortfolio
        }
        allStocksWithOwners = portfolioManager.getStocksWithOwners(
            users: sheetsService.users,
            portfolios: portfoliosWithOptimistic,
            prices: priceService.prices,
            stocks: priceService.stocks
        )
    }
    
    // MARK: - Get All Stock Symbols
    private func getAllStockSymbols() -> [String] {
        var symbols = Set<String>()
        
        for portfolio in sheetsService.portfolios.values {
            for holding in portfolio.holdings {
                symbols.insert(holding.symbol)
            }
        }
        
        return Array(symbols)
    }
    
    // MARK: - Portfolio Actions
    func addStock(symbol: String) async {
        logInfo("📱 [UI] addStock called for: \(symbol)", category: .portfolio)
        let startTime = Date()
        
        guard var portfolio = currentUserPortfolio else {
            logError("📱 [UI] No current portfolio to add stock to", category: .portfolio)
            return
        }
        
        logDebug("📱 [UI] Current portfolio has \(portfolio.holdings.count) holdings, cash: $\(String(format: "%.2f", portfolio.cashBalance))", category: .portfolio)
        
        // Check if stock already exists
        if portfolio.holdings.contains(where: { $0.symbol == symbol }) {
            logWarning("📱 [UI] Stock \(symbol) already in portfolio - skipping", category: .portfolio)
            return
        }
        
        // Get price - fetch if not cached (this is the only blocking call we need)
        var stockPrice = priceService.prices[symbol]
        if stockPrice == nil {
            logInfo("📱 [UI] Fetching price for \(symbol)...", category: .portfolio)
            do {
                _ = try await priceService.fetchQuote(symbol: symbol)
                stockPrice = priceService.prices[symbol]
            } catch {
                logError("📱 [UI] Failed to fetch price for \(symbol): \(error.localizedDescription)", category: .portfolio)
                self.error = "Failed to fetch price for \(symbol)"
                return
            }
        }
        
        guard let price = stockPrice, price > 0 else {
            logError("📱 [UI] No valid price for \(symbol)", category: .portfolio)
            return
        }
        
        logInfo("📱 [UI] Got price for \(symbol): $\(String(format: "%.2f", price))", category: .portfolio)
        
        // Now add stock with correct price
        portfolio = portfolioManager.addStock(
            symbol: symbol,
            to: portfolio,
            prices: priceService.prices
        )
        
        // IMMEDIATE UI UPDATE
        currentUserPortfolio = portfolio
        updateDerivedState()
        let uiUpdateTime = Date().timeIntervalSince(startTime)
        logSuccess("📱 [UI] Stock \(symbol) added to UI after \(String(format: "%.0f", uiUpdateTime * 1000))ms", category: .portfolio)
        
        // BACKGROUND: Save to Google Sheets (fire and forget)
        logInfo("🌐 [NET] Starting background save to Sheets", category: .portfolio)
        Task.detached { [weak self, portfolio] in
            let saveStart = Date()
            do {
                try await self?.sheetsService.savePortfolio(portfolio)
                let saveTime = Date().timeIntervalSince(saveStart)
                await MainActor.run { logSuccess("🌐 Sheets saved in \(String(format: "%.0f", saveTime * 1000))ms", category: .portfolio) }
            } catch {
                await MainActor.run { logError("🌐 Save failed: \(error.localizedDescription)", category: .portfolio) }
                await MainActor.run {
                    self?.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func removeStock(symbol: String) async {
        logInfo("📱 [UI] removeStock called for: \(symbol)", category: .portfolio)
        let startTime = Date()
        
        guard var portfolio = currentUserPortfolio else {
            logError("📱 [UI] No current portfolio to remove stock from", category: .portfolio)
            return
        }
        
        portfolio = portfolioManager.removeStock(
            symbol: symbol,
            from: portfolio,
            prices: priceService.prices
        )
        
        // IMMEDIATE UI UPDATE
        currentUserPortfolio = portfolio
        updateDerivedState()
        let uiUpdateTime = Date().timeIntervalSince(startTime)
        logSuccess("📱 [UI] Stock \(symbol) removed from UI after \(String(format: "%.0f", uiUpdateTime * 1000))ms", category: .portfolio)
        
        // BACKGROUND: Save to Google Sheets (fire and forget)
        logInfo("🌐 [NET] Starting background save to Sheets", category: .portfolio)
        Task.detached { [weak self, portfolio] in
            let saveStart = Date()
            do {
                try await self?.sheetsService.savePortfolio(portfolio)
                let saveTime = Date().timeIntervalSince(saveStart)
                await MainActor.run { logSuccess("🌐 Sheets saved in \(String(format: "%.0f", saveTime * 1000))ms", category: .portfolio) }
            } catch {
                await MainActor.run { logError("🌐 Save failed: \(error.localizedDescription)", category: .portfolio) }
                await MainActor.run {
                    self?.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        logInfo("📱 [UI] removeStock function returned after \(String(format: "%.0f", totalTime * 1000))ms", category: .portfolio)
    }
    
    /// Adjust allocation by a dollar amount (+/- $5000) using cash
    func adjustAllocation(symbol: String, amountDelta: Double) async {
        logInfo("📱 [UI] adjustAllocation called: \(symbol) by \(amountDelta.asSignedCurrency)", category: .portfolio)
        let startTime = Date()
        
        guard var portfolio = currentUserPortfolio else {
            logError("📱 [UI] No current portfolio to adjust", category: .portfolio)
            return
        }
        
        // Use the new cash-based adjustment method
        portfolio = portfolioManager.adjustAllocationByAmount(
            symbol: symbol,
            amountDelta: amountDelta,
            in: portfolio,
            prices: priceService.prices
        )
        
        // IMMEDIATE UI UPDATE
        currentUserPortfolio = portfolio
        updateDerivedState()
        let uiUpdateTime = Date().timeIntervalSince(startTime)
        logSuccess("📱 [UI] Allocation adjusted in UI after \(String(format: "%.0f", uiUpdateTime * 1000))ms", category: .portfolio)
        
        // BACKGROUND: Save to Google Sheets (fire and forget)
        logInfo("🌐 [NET] Starting background save to Sheets", category: .portfolio)
        Task.detached { [weak self, portfolio] in
            let saveStart = Date()
            do {
                try await self?.sheetsService.savePortfolio(portfolio)
                let saveTime = Date().timeIntervalSince(saveStart)
                await MainActor.run { logSuccess("🌐 Sheets saved in \(String(format: "%.0f", saveTime * 1000))ms", category: .portfolio) }
            } catch {
                await MainActor.run { logError("🌐 Save failed: \(error.localizedDescription)", category: .portfolio) }
                await MainActor.run {
                    self?.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        logInfo("📱 [UI] adjustAllocation function returned after \(String(format: "%.0f", totalTime * 1000))ms", category: .portfolio)
    }
    
    func adjustAllocation(symbol: String, targetPercent: Double) async {
        logInfo("📱 [UI] adjustAllocation (percent) called: \(symbol) to \(String(format: "%.1f", targetPercent))%", category: .portfolio)
        let startTime = Date()
        
        guard var portfolio = currentUserPortfolio else {
            logError("📱 [UI] No current portfolio to adjust", category: .portfolio)
            return
        }
        
        portfolio = portfolioManager.adjustAllocation(
            symbol: symbol,
            targetPercent: targetPercent,
            in: portfolio,
            prices: priceService.prices
        )
        
        // IMMEDIATE UI UPDATE
        currentUserPortfolio = portfolio
        updateDerivedState()
        let uiUpdateTime = Date().timeIntervalSince(startTime)
        logSuccess("📱 [UI] Allocation adjusted in UI after \(String(format: "%.0f", uiUpdateTime * 1000))ms", category: .portfolio)
        
        // BACKGROUND: Save to Google Sheets (fire and forget)
        Task.detached { [weak self, portfolio] in
            let saveStart = Date()
            do {
                try await self?.sheetsService.savePortfolio(portfolio)
                let saveTime = Date().timeIntervalSince(saveStart)
                await MainActor.run { logSuccess("🌐 Sheets saved in \(String(format: "%.0f", saveTime * 1000))ms", category: .portfolio) }
            } catch {
                await MainActor.run { logError("🌐 Save failed: \(error.localizedDescription)", category: .portfolio) }
                await MainActor.run {
                    self?.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func rebalanceEqually() async {
        logInfo("📱 [UI] rebalanceEqually called", category: .portfolio)
        let startTime = Date()
        
        guard var portfolio = currentUserPortfolio else {
            logError("📱 [UI] No current portfolio to rebalance", category: .portfolio)
            return
        }
        
        portfolio = portfolioManager.rebalanceEqually(
            portfolio: portfolio,
            prices: priceService.prices
        )
        
        // IMMEDIATE UI UPDATE
        currentUserPortfolio = portfolio
        updateDerivedState()
        let uiUpdateTime = Date().timeIntervalSince(startTime)
        logSuccess("📱 [UI] Portfolio rebalanced in UI after \(String(format: "%.0f", uiUpdateTime * 1000))ms", category: .portfolio)
        
        // BACKGROUND: Save to Google Sheets (fire and forget)
        Task.detached { [weak self, portfolio] in
            let saveStart = Date()
            do {
                try await self?.sheetsService.savePortfolio(portfolio)
                let saveTime = Date().timeIntervalSince(saveStart)
                await MainActor.run { logSuccess("🌐 Sheets saved in \(String(format: "%.0f", saveTime * 1000))ms", category: .portfolio) }
            } catch {
                await MainActor.run { logError("🌐 Save failed: \(error.localizedDescription)", category: .portfolio) }
                await MainActor.run {
                    self?.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Price Updates
    func startPriceUpdates() {
        logInfo("Starting price update timer (30s interval)", category: .app)
        // Update prices every 30 seconds in production
        // For demo, we'll simulate price changes
        priceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                logDebug("Price update timer fired", category: .stocks)
                #if DEBUG
                self?.priceService.simulatePriceUpdate()
                self?.updateDerivedState()
                #else
                let symbols = self?.getAllStockSymbols() ?? []
                await self?.priceService.refreshAllPrices(for: symbols)
                self?.updateDerivedState()
                #endif
            }
        }
        
        // Also start a data refresh timer to pick up new users/portfolios
        logInfo("Starting data refresh timer (60s interval)", category: .app)
        dataRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                logDebug("Data refresh timer fired - checking for new users/portfolios", category: .app)
                await self?.refreshDataFromBackend()
            }
        }
    }
    
    func stopPriceUpdates() {
        logInfo("Stopping price update timer", category: .app)
        priceUpdateTimer?.invalidate()
        priceUpdateTimer = nil
        dataRefreshTimer?.invalidate()
        dataRefreshTimer = nil
    }
    
    /// Refresh data from backend without clearing optimistic local state
    func refreshDataFromBackend() async {
        logDebug("Refreshing data from backend (live update)", category: .app)
        
        do {
            // Fetch fresh data from sheets
            try await sheetsService.fetchAllData()
            
            // Refresh prices for any new symbols
            let symbols = getAllStockSymbols()
            await priceService.refreshAllPrices(for: symbols)
            
            // Update derived state (leaderboard, stocks list, etc.)
            // But preserve optimistic portfolio updates
            updateDerivedStatePreservingPortfolio()
            
            logDebug("Live refresh complete", category: .app)
        } catch {
            logWarning("Live refresh failed: \(error.localizedDescription)", category: .app)
        }
    }
    
    /// Update derived state but keep current portfolio if it has optimistic updates
    private func updateDerivedStatePreservingPortfolio() {
        guard let userId = authService.currentUser?.id else { return }
        
        // Update leaderboard with all users (including new users)
        leaderboard = portfolioManager.generateLeaderboard(
            users: sheetsService.users,
            portfolios: sheetsService.portfolios,
            prices: priceService.prices
        )
        
        // Update all stocks with owners
        allStocksWithOwners = portfolioManager.getStocksWithOwners(
            users: sheetsService.users,
            portfolios: sheetsService.portfolios,
            prices: priceService.prices,
            stocks: priceService.stocks
        )
        
        // Update current user portfolio from server (source of truth)
        let serverPortfolio = sheetsService.getPortfolio(for: userId)
        currentUserPortfolio = serverPortfolio
        
        logDebug("Live refresh: \(sheetsService.users.count) users, \(leaderboard.count) leaderboard entries", category: .app)
    }
    
    // MARK: - Record Snapshot
    func recordSnapshot() async {
        guard let userId = authService.currentUser?.id else {
            logWarning("Cannot record snapshot - no current user", category: .app)
            return
        }
        
        logDebug("Recording net worth snapshot for user: \(userId)", category: .app)
        
        do {
            try await sheetsService.recordNetWorthSnapshot(
                userId: userId,
                prices: priceService.prices
            )
        } catch {
            logError("Failed to record snapshot: \(error.localizedDescription)", category: .app)
        }
    }
    
    // MARK: - Record Snapshots for All Users
    /// Records net worth snapshots for all users (throttled to once per hour)
    private var lastSnapshotTime: Date?
    
    func recordSnapshotsForAllUsers() async {
        // Throttle: Only record once per hour
        if let lastTime = lastSnapshotTime, Date().timeIntervalSince(lastTime) < 3600 {
            logDebug("Skipping snapshot recording - last recorded \(Int(Date().timeIntervalSince(lastTime)))s ago", category: .app)
            return
        }
        
        logInfo("📸 Recording net worth snapshots for all users", category: .app)
        
        for user in sheetsService.users {
            do {
                try await sheetsService.recordNetWorthSnapshot(
                    userId: user.id,
                    prices: priceService.prices
                )
                logDebug("📸 Recorded snapshot for \(user.displayName)", category: .app)
            } catch {
                logError("Failed to record snapshot for \(user.displayName): \(error.localizedDescription)", category: .app)
            }
        }
        
        lastSnapshotTime = Date()
        logSuccess("📸 All snapshots recorded", category: .app)
    }
    
    // MARK: - Get User's Net Worth
    func getNetWorth(for userId: String? = nil) -> Double {
        // For current user, use the local (optimistically updated) portfolio
        if userId == nil || userId == authService.currentUser?.id {
            if let portfolio = currentUserPortfolio {
                return portfolioManager.calculateNetWorth(portfolio: portfolio, prices: priceService.prices)
            }
        }
        // For other users, fetch from sheets service
        let targetUserId = userId ?? authService.currentUser?.id ?? ""
        let portfolio = sheetsService.getPortfolio(for: targetUserId)
        return portfolioManager.calculateNetWorth(portfolio: portfolio, prices: priceService.prices)
    }
    
    // MARK: - Get User's Allocations
    func getAllocations(for userId: String? = nil) -> [(symbol: String, percent: Double, value: Double)] {
        // For current user, use the local (optimistically updated) portfolio
        if userId == nil || userId == authService.currentUser?.id {
            if let portfolio = currentUserPortfolio {
                return portfolioManager.getAllocations(portfolio: portfolio, prices: priceService.prices)
            }
        }
        // For other users, fetch from sheets service
        let targetUserId = userId ?? authService.currentUser?.id ?? ""
        let portfolio = sheetsService.getPortfolio(for: targetUserId)
        return portfolioManager.getAllocations(portfolio: portfolio, prices: priceService.prices)
    }
    
    // MARK: - Get Chart Data
    func getChartData(for userId: String, range: TimeRange) -> [ChartDataPoint] {
        return sheetsService.getSnapshots(for: userId, in: range)
    }
    
    // MARK: - Sign In
    func signIn() async {
        logInfo("User initiated sign in", category: .auth)
        await authService.signIn()
        
        if authService.isAuthenticated {
            logSuccess("Sign in successful", category: .auth)
            
            // IMPORTANT: Load data FIRST so we can check if portfolio exists
            await loadAllData()
            
            // Save user to backend if new
            if let user = authService.currentUser {
                logInfo("User: \(user.displayName) (\(user.email))", category: .auth)
                do {
                    try await sheetsService.saveUser(user)
                    
                    // Create initial portfolio ONLY if user has no existing portfolio
                    if sheetsService.portfolios[user.id] == nil {
                        logInfo("Creating initial portfolio for new user", category: .portfolio)
                        let portfolio = portfolioManager.createInitialPortfolio(for: user.id)
                        try await sheetsService.savePortfolio(portfolio)
                        // Refresh to pick up the new portfolio
                        await loadAllData()
                    } else {
                        logInfo("Found existing portfolio for user", category: .portfolio)
                    }
                } catch {
                    logError("Failed to save user/portfolio: \(error.localizedDescription)", category: .app)
                    self.error = error.localizedDescription
                }
            }
        } else {
            logWarning("Sign in was not successful", category: .auth)
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        logInfo("User signing out", category: .auth)
        stopPriceUpdates()
        authService.signOut()
        currentUserPortfolio = nil
        leaderboard = []
        allStocksWithOwners = []
        logSuccess("Sign out complete", category: .auth)
    }
}
