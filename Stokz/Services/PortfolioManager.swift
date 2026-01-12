import Foundation

/// PortfolioManager handles all portfolio calculations and rebalancing logic
/// Key rules:
/// - Portfolios are always 100% invested (no cash)
/// - Holdings are market-value based (not fixed weights)
/// - Allocation percentages float automatically as prices move
@MainActor
class PortfolioManager: ObservableObject {
    
    static let shared = PortfolioManager()
    static let initialCash: Double = 100_000
    
    // MARK: - Add Stock to Portfolio
    /// When adding a new stock:
    /// 1. If cash available, use cash to buy the new stock
    /// 2. If no cash, sell $5000 evenly from existing stocks to fund the purchase
    /// - Parameters:
    ///   - symbol: Stock symbol to add
    ///   - portfolio: Current portfolio
    ///   - prices: Current market prices
    /// - Returns: Updated portfolio with new stock (existing positions preserved)
    func addStock(symbol: String, to portfolio: Portfolio, prices: [String: Double]) -> Portfolio {
        logInfo("PortfolioManager.addStock called for \(symbol)", category: .portfolio)
        logDebug("Portfolio has \(portfolio.holdings.count) holdings, cash: $\(String(format: "%.2f", portfolio.cashBalance)), prices dict has \(prices.count) entries", category: .portfolio)
        
        var updatedPortfolio = portfolio
        
        // Check if stock already exists
        guard !portfolio.holdings.contains(where: { $0.symbol == symbol }) else {
            logWarning("Stock \(symbol) already exists in portfolio", category: .portfolio)
            return portfolio
        }
        
        // Get current price for new stock
        guard let currentPrice = prices[symbol], currentPrice > 0 else {
            logError("No valid price for \(symbol) in prices dict. Available: \(Array(prices.keys).joined(separator: ", "))", category: .portfolio)
            return portfolio
        }
        
        logDebug("Price for \(symbol): $\(String(format: "%.2f", currentPrice))", category: .portfolio)
        
        let purchaseAmount: Double = 5000.0
        var amountToBuy: Double = 0
        
        // CASE 1: Use cash if available
        if portfolio.cashBalance >= purchaseAmount {
            amountToBuy = purchaseAmount
            updatedPortfolio.cashBalance -= purchaseAmount
            logInfo("Using $\(String(format: "%.2f", purchaseAmount)) cash to buy \(symbol). Remaining cash: $\(String(format: "%.2f", updatedPortfolio.cashBalance))", category: .portfolio)
        } else if portfolio.cashBalance > 0 {
            // Use all available cash + sell from stocks for the rest
            let cashPortion = portfolio.cashBalance
            let sellPortion = purchaseAmount - cashPortion
            amountToBuy = purchaseAmount
            updatedPortfolio.cashBalance = 0
            
            // Sell evenly from existing holdings
            if !portfolio.holdings.isEmpty {
                let sellPerStock = sellPortion / Double(portfolio.holdings.count)
                var newHoldings: [PortfolioHolding] = []
                
                for holding in portfolio.holdings {
                    let price = prices[holding.symbol] ?? holding.entryPrice
                    let currentValue = holding.currentValue(at: price)
                    let newValue = max(0, currentValue - sellPerStock)
                    
                    if newValue > 0 {
                        let newShares = newValue / price
                        let updatedHolding = PortfolioHolding(
                            id: holding.id,
                            symbol: holding.symbol,
                            shares: newShares,
                            entryPrice: holding.entryPrice, // Preserve original entry price
                            entryDate: holding.entryDate
                        )
                        newHoldings.append(updatedHolding)
                        logDebug("Reduced \(holding.symbol) by $\(String(format: "%.2f", sellPerStock))", category: .portfolio)
                    } else {
                        logDebug("Sold all of \(holding.symbol)", category: .portfolio)
                    }
                }
                updatedPortfolio.holdings = newHoldings
            }
            logInfo("Used $\(String(format: "%.2f", cashPortion)) cash + sold $\(String(format: "%.2f", sellPortion)) from stocks to buy \(symbol)", category: .portfolio)
        } else {
            // CASE 2: No cash - sell $5000 evenly from existing stocks
            if portfolio.holdings.isEmpty {
                logError("Cannot add stock: no cash and no existing holdings", category: .portfolio)
                return portfolio
            }
            
            let sellPerStock = purchaseAmount / Double(portfolio.holdings.count)
            var newHoldings: [PortfolioHolding] = []
            var actualSellTotal: Double = 0
            
            for holding in portfolio.holdings {
                let price = prices[holding.symbol] ?? holding.entryPrice
                let currentValue = holding.currentValue(at: price)
                let actualSell = min(sellPerStock, currentValue) // Can't sell more than we have
                let newValue = currentValue - actualSell
                actualSellTotal += actualSell
                
                if newValue > 0 {
                    let newShares = newValue / price
                    let updatedHolding = PortfolioHolding(
                        id: holding.id,
                        symbol: holding.symbol,
                        shares: newShares,
                        entryPrice: holding.entryPrice, // Preserve original entry price
                        entryDate: holding.entryDate
                    )
                    newHoldings.append(updatedHolding)
                    logDebug("Reduced \(holding.symbol) by $\(String(format: "%.2f", actualSell))", category: .portfolio)
                } else {
                    logDebug("Sold all of \(holding.symbol)", category: .portfolio)
                }
            }
            
            updatedPortfolio.holdings = newHoldings
            amountToBuy = actualSellTotal
            logInfo("Sold $\(String(format: "%.2f", actualSellTotal)) evenly from \(portfolio.holdings.count) stocks to buy \(symbol)", category: .portfolio)
        }
        
        // Add new stock
        let newShares = amountToBuy / currentPrice
        let newHolding = PortfolioHolding(
            id: UUID().uuidString,
            symbol: symbol,
            shares: newShares,
            entryPrice: currentPrice,
            entryDate: Date()
        )
        updatedPortfolio.holdings.append(newHolding)
        updatedPortfolio.lastUpdated = Date()
        
        logSuccess("Added \(symbol) to portfolio: \(String(format: "%.4f", newShares)) shares @ $\(String(format: "%.2f", currentPrice)) = $\(String(format: "%.2f", amountToBuy)). Now has \(updatedPortfolio.holdings.count) holdings", category: .portfolio)
        
        return updatedPortfolio
    }
    
    // MARK: - Remove Stock from Portfolio
    /// Remove a stock and convert its value to cash
    func removeStock(symbol: String, from portfolio: Portfolio, prices: [String: Double]) -> Portfolio {
        var updatedPortfolio = portfolio
        
        // Find the stock to remove
        guard let index = portfolio.holdings.firstIndex(where: { $0.symbol == symbol }) else {
            return portfolio
        }
        
        // Calculate value of stock being removed
        let holding = portfolio.holdings[index]
        let price = prices[holding.symbol] ?? holding.entryPrice
        let stockValue = holding.currentValue(at: price)
        
        // Remove the stock and add value to cash
        var remainingHoldings = portfolio.holdings
        remainingHoldings.remove(at: index)
        
        updatedPortfolio.holdings = remainingHoldings
        updatedPortfolio.cashBalance += stockValue
        updatedPortfolio.lastUpdated = Date()
        
        logInfo("Removed \(symbol), added $\(String(format: "%.2f", stockValue)) to cash. New cash balance: $\(String(format: "%.2f", updatedPortfolio.cashBalance))", category: .portfolio)
        
        return updatedPortfolio
    }
    
    // MARK: - Adjust Single Stock Allocation
    /// Setting one stock to X% triggers an instant rebalance
    /// Remaining stocks are scaled proportionally to their current market values
    func adjustAllocation(symbol: String, targetPercent: Double, in portfolio: Portfolio, prices: [String: Double]) -> Portfolio {
        var updatedPortfolio = portfolio
        
        // Validate target percent (0-100)
        let clampedTarget = min(max(targetPercent, 0), 100)
        
        // Find the stock to adjust
        guard portfolio.holdings.contains(where: { $0.symbol == symbol }) else {
            return portfolio
        }
        
        // Calculate total portfolio value
        let totalValue = portfolio.totalValue(prices: prices)
        guard totalValue > 0 else { return portfolio }
        
        // Calculate the value for the target stock
        let targetValue = totalValue * (clampedTarget / 100.0)
        
        // Calculate remaining value to distribute
        let remainingValue = totalValue - targetValue
        
        // Get current values of other stocks (for proportional scaling)
        var otherStocksValue: Double = 0
        for holding in portfolio.holdings where holding.symbol != symbol {
            let price = prices[holding.symbol] ?? holding.entryPrice
            otherStocksValue += holding.currentValue(at: price)
        }
        
        var newHoldings: [PortfolioHolding] = []
        
        for holding in portfolio.holdings {
            let price = prices[holding.symbol] ?? holding.entryPrice
            
            if holding.symbol == symbol {
                // Set target allocation
                let newShares = targetValue / price
                let updatedHolding = PortfolioHolding(
                    id: holding.id,
                    symbol: holding.symbol,
                    shares: newShares,
                    entryPrice: price,
                    entryDate: Date()
                )
                newHoldings.append(updatedHolding)
            } else {
                // Scale proportionally based on current market value
                let currentValue = holding.currentValue(at: price)
                let proportion = otherStocksValue > 0 ? currentValue / otherStocksValue : 1.0 / Double(portfolio.holdings.count - 1)
                let newValue = remainingValue * proportion
                let newShares = newValue / price
                
                let updatedHolding = PortfolioHolding(
                    id: holding.id,
                    symbol: holding.symbol,
                    shares: newShares,
                    entryPrice: price,
                    entryDate: Date()
                )
                newHoldings.append(updatedHolding)
            }
        }
        
        updatedPortfolio.holdings = newHoldings
        updatedPortfolio.lastUpdated = Date()
        
        return updatedPortfolio
    }
    
    // MARK: - Rebalance Equally
    /// Rebalance all holdings to equal weights
    func rebalanceEqually(portfolio: Portfolio, prices: [String: Double]) -> Portfolio {
        var updatedPortfolio = portfolio
        
        guard !portfolio.holdings.isEmpty else { return portfolio }
        
        let totalValue = portfolio.totalValue(prices: prices)
        let equalAllocation = totalValue / Double(portfolio.holdings.count)
        
        var newHoldings: [PortfolioHolding] = []
        
        for holding in portfolio.holdings {
            let price = prices[holding.symbol] ?? holding.entryPrice
            let newShares = equalAllocation / price
            
            let updatedHolding = PortfolioHolding(
                id: holding.id,
                symbol: holding.symbol,
                shares: newShares,
                entryPrice: price,
                entryDate: Date()
            )
            newHoldings.append(updatedHolding)
        }
        
        updatedPortfolio.holdings = newHoldings
        updatedPortfolio.lastUpdated = Date()
        
        return updatedPortfolio
    }
    
    // MARK: - Adjust Allocation by Dollar Amount (with Cash)
    /// Adjust a stock's allocation by a dollar amount, using/adding cash as needed
    /// - positive amountDelta: buy more (use cash first, then sell others)
    /// - negative amountDelta: sell shares, add to cash
    func adjustAllocationByAmount(symbol: String, amountDelta: Double, in portfolio: Portfolio, prices: [String: Double]) -> Portfolio {
        var updatedPortfolio = portfolio
        
        guard let holdingIndex = portfolio.holdings.firstIndex(where: { $0.symbol == symbol }) else {
            logError("Stock \(symbol) not found in portfolio", category: .portfolio)
            return portfolio
        }
        
        let holding = portfolio.holdings[holdingIndex]
        let price = prices[symbol] ?? holding.entryPrice
        guard price > 0 else { return portfolio }
        
        let currentValue = holding.currentValue(at: price)
        let newValue = currentValue + amountDelta
        
        logDebug("adjustAllocationByAmount: \(symbol) current=$\(String(format: "%.2f", currentValue)) delta=$\(String(format: "%.2f", amountDelta)) new=$\(String(format: "%.2f", newValue))", category: .portfolio)
        
        // CASE 1: Selling (negative delta) - convert to cash
        if amountDelta < 0 {
            if newValue <= 0 {
                // Sell entire position
                updatedPortfolio.cashBalance += currentValue
                updatedPortfolio.holdings.remove(at: holdingIndex)
                logInfo("Sold all \(symbol) for $\(String(format: "%.2f", currentValue)), cash now $\(String(format: "%.2f", updatedPortfolio.cashBalance))", category: .portfolio)
            } else {
                // Partial sell
                let newShares = newValue / price
                updatedPortfolio.holdings[holdingIndex] = PortfolioHolding(
                    id: holding.id,
                    symbol: symbol,
                    shares: newShares,
                    entryPrice: price,
                    entryDate: Date()
                )
                updatedPortfolio.cashBalance += abs(amountDelta)
                logInfo("Sold $\(String(format: "%.2f", abs(amountDelta))) of \(symbol), cash now $\(String(format: "%.2f", updatedPortfolio.cashBalance))", category: .portfolio)
            }
        }
        // CASE 2: Buying (positive delta) - use cash
        else if amountDelta > 0 {
            let cashAvailable = portfolio.cashBalance
            let amountToBuy = min(amountDelta, cashAvailable) // Can only buy with available cash
            
            if amountToBuy > 0 {
                let additionalShares = amountToBuy / price
                let newShares = holding.shares + additionalShares
                updatedPortfolio.holdings[holdingIndex] = PortfolioHolding(
                    id: holding.id,
                    symbol: symbol,
                    shares: newShares,
                    entryPrice: price,
                    entryDate: Date()
                )
                updatedPortfolio.cashBalance -= amountToBuy
                logInfo("Bought $\(String(format: "%.2f", amountToBuy)) of \(symbol), cash now $\(String(format: "%.2f", updatedPortfolio.cashBalance))", category: .portfolio)
            } else {
                logWarning("No cash available to buy more \(symbol)", category: .portfolio)
            }
        }
        
        updatedPortfolio.lastUpdated = Date()
        return updatedPortfolio
    }
    
    // MARK: - Calculate Net Worth
    func calculateNetWorth(portfolio: Portfolio, prices: [String: Double]) -> Double {
        // Total value = holdings value + cash
        var holdingsValue: Double = 0
        for holding in portfolio.holdings {
            let price = prices[holding.symbol] ?? holding.entryPrice
            let value = holding.currentValue(at: price)
            holdingsValue += value
        }
        let totalValue = holdingsValue + portfolio.cashBalance
        
        // If completely empty (no holdings, no cash), return initial cash
        if portfolio.holdings.isEmpty && portfolio.cashBalance == 0 {
            return PortfolioManager.initialCash
        }
        return totalValue
    }
    
    // MARK: - Get Allocations
    func getAllocations(portfolio: Portfolio, prices: [String: Double]) -> [(symbol: String, percent: Double, value: Double)] {
        let totalValue = calculateNetWorth(portfolio: portfolio, prices: prices)
        
        return portfolio.holdings.map { holding in
            let price = prices[holding.symbol] ?? holding.entryPrice
            let value = holding.currentValue(at: price)
            let percent = totalValue > 0 ? (value / totalValue) * 100 : 0
            return (symbol: holding.symbol, percent: percent, value: value)
        }.sorted { $0.percent > $1.percent }
    }
    
    // MARK: - Create Initial Portfolio
    func createInitialPortfolio(for userId: String) -> Portfolio {
        return Portfolio(
            id: UUID().uuidString,
            userId: userId,
            holdings: [],
            cashBalance: PortfolioManager.initialCash, // Start with $100k cash
            initialValue: PortfolioManager.initialCash
        )
    }
    
    // MARK: - Validate Portfolio
    /// Ensures portfolio math is correct (allocations sum to 100%)
    func validatePortfolio(portfolio: Portfolio, prices: [String: Double]) -> Bool {
        guard !portfolio.holdings.isEmpty else { return true }
        
        let allocations = getAllocations(portfolio: portfolio, prices: prices)
        let totalPercent = allocations.reduce(0) { $0 + $1.percent }
        
        // Allow small floating point tolerance
        return abs(totalPercent - 100.0) < 0.01
    }
    
    // MARK: - Generate Leaderboard
    func generateLeaderboard(users: [User], portfolios: [String: Portfolio], prices: [String: Double]) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []
        
        logDebug("Generating leaderboard for \(users.count) users with \(prices.count) prices", category: .portfolio)
        
        for user in users {
            let portfolio = portfolios[user.id] ?? createInitialPortfolio(for: user.id)
            let netWorth = calculateNetWorth(portfolio: portfolio, prices: prices)
            let profitLossPercent = ((netWorth - PortfolioManager.initialCash) / PortfolioManager.initialCash) * 100
            
            // Detailed logging for each user
            logDebug("User \(user.displayName): \(portfolio.holdings.count) holdings", category: .portfolio)
            for holding in portfolio.holdings {
                let price = prices[holding.symbol] ?? 0
                let value = holding.shares * price
                logDebug("  \(holding.symbol): \(String(format: "%.4f", holding.shares)) shares @ $\(String(format: "%.2f", price)) = $\(String(format: "%.2f", value))", category: .portfolio)
            }
            logDebug("  Net Worth: $\(String(format: "%.2f", netWorth)) (P/L: \(String(format: "%.2f", profitLossPercent))%)", category: .portfolio)
            
            entries.append(LeaderboardEntry(
                id: user.id,
                user: user,
                netWorth: netWorth,
                rank: 0, // Will be set after sorting
                profitLossPercent: profitLossPercent
            ))
        }
        
        // Sort by net worth descending
        entries.sort { $0.netWorth > $1.netWorth }
        
        // Assign ranks
        return entries.enumerated().map { index, entry in
            LeaderboardEntry(
                id: entry.id,
                user: entry.user,
                netWorth: entry.netWorth,
                rank: index + 1,
                profitLossPercent: entry.profitLossPercent
            )
        }
    }
    
    // MARK: - Get All Stocks with Owners
    func getStocksWithOwners(users: [User], portfolios: [String: Portfolio], prices: [String: Double], stocks: [String: Stock] = [:]) -> [StockWithOwners] {
        var stockOwners: [String: [User]] = [:]
        var stockData: [String: Stock] = [:]
        
        for user in users {
            guard let portfolio = portfolios[user.id] else { continue }
            
            for holding in portfolio.holdings {
                if stockOwners[holding.symbol] == nil {
                    stockOwners[holding.symbol] = []
                }
                stockOwners[holding.symbol]?.append(user)
                
                // Use actual Stock object from priceService if available (has correct previousClose)
                if stockData[holding.symbol] == nil {
                    if let stock = stocks[holding.symbol] {
                        stockData[holding.symbol] = stock
                    } else {
                        // Fallback: create stock with current price as both (0% change)
                        let price = prices[holding.symbol] ?? holding.entryPrice
                        stockData[holding.symbol] = Stock(
                            symbol: holding.symbol,
                            currentPrice: price,
                            previousClose: price,
                            lastUpdated: Date()
                        )
                    }
                }
            }
        }
        
        return stockOwners.compactMap { symbol, owners in
            guard let stock = stockData[symbol] else { return nil }
            return StockWithOwners(stock: stock, owners: owners)
        }.sorted { $0.stock.symbol < $1.stock.symbol }
    }
}
