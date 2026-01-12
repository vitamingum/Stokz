import Foundation

// MARK: - User Model
struct User: Identifiable, Codable, Equatable {
    let id: String
    let email: String
    let displayName: String
    let photoURL: String?
    let createdAt: Date
    var isAI: Bool  // True if this is an AI-controlled player
    var aiThesis: String?  // Investment thesis for AI players (multi-sentence)
    var aiProvider: String?  // LLM provider for AI players (gemini, openai, anthropic, grok)
    
    // Custom decoder to handle missing isAI field in existing data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isAI = try container.decodeIfPresent(Bool.self, forKey: .isAI) ?? false
        aiThesis = try container.decodeIfPresent(String.self, forKey: .aiThesis)
        aiProvider = try container.decodeIfPresent(String.self, forKey: .aiProvider)
    }
    
    init(id: String, email: String, displayName: String, photoURL: String?, createdAt: Date, isAI: Bool = false, aiThesis: String? = nil, aiProvider: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.isAI = isAI
        self.aiThesis = aiThesis
        self.aiProvider = aiProvider
    }
    
    /// Get the LLM provider enum for this AI player
    var llmProvider: LLMProvider? {
        guard isAI, let providerStr = aiProvider else { return nil }
        return LLMProvider(rawValue: providerStr)
    }
    
    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Stock Model
struct Stock: Identifiable, Codable, Hashable {
    let symbol: String
    var currentPrice: Double
    var previousClose: Double
    var lastUpdated: Date
    
    var id: String { symbol }
    
    var priceChange: Double {
        currentPrice - previousClose
    }
    
    var priceChangePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (priceChange / previousClose) * 100
    }
    
    var isPositive: Bool {
        priceChange >= 0
    }
}

// MARK: - Portfolio Holding
struct PortfolioHolding: Identifiable, Codable {
    let id: String
    let symbol: String
    var shares: Double // Implied shares based on entry
    var entryPrice: Double // Price at which shares were calculated
    var entryDate: Date
    var costBasis: Double // Total $ invested in this position (survives rebalances)
    
    // Initialize with costBasis defaulting to shares * entryPrice for backwards compatibility
    init(id: String = UUID().uuidString, symbol: String, shares: Double, entryPrice: Double, entryDate: Date = Date(), costBasis: Double? = nil) {
        self.id = id
        self.symbol = symbol
        self.shares = shares
        self.entryPrice = entryPrice
        self.entryDate = entryDate
        self.costBasis = costBasis ?? (shares * entryPrice)
    }
    
    // Custom decoder to handle missing costBasis in existing data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        shares = try container.decode(Double.self, forKey: .shares)
        entryPrice = try container.decode(Double.self, forKey: .entryPrice)
        entryDate = try container.decode(Date.self, forKey: .entryDate)
        // Default costBasis to shares * entryPrice if not present
        costBasis = try container.decodeIfPresent(Double.self, forKey: .costBasis) ?? (shares * entryPrice)
    }
    
    // Calculated properties using current prices
    func currentValue(at price: Double) -> Double {
        shares * price
    }
    
    func allocationPercent(totalValue: Double, currentPrice: Double) -> Double {
        guard totalValue > 0 else { return 0 }
        return (currentValue(at: currentPrice) / totalValue) * 100
    }
    
    // P/L based on cost basis (accurate across rebalances)
    func profitLoss(at currentPrice: Double) -> Double {
        currentValue(at: currentPrice) - costBasis
    }
    
    func profitLossPercent(at currentPrice: Double) -> Double {
        guard costBasis > 0 else { return 0 }
        return ((currentValue(at: currentPrice) - costBasis) / costBasis) * 100
    }
}

// MARK: - Portfolio
struct Portfolio: Identifiable, Codable {
    let id: String
    let userId: String
    var holdings: [PortfolioHolding]
    var cashBalance: Double // Cash available for new investments
    let initialValue: Double // Starting amount ($100,000)
    var lastUpdated: Date
    
    init(id: String = UUID().uuidString, userId: String, holdings: [PortfolioHolding] = [], cashBalance: Double? = nil, initialValue: Double = 100_000) {
        self.id = id
        self.userId = userId
        self.holdings = holdings
        // Default cash: if no holdings, start with full initial value as cash
        self.cashBalance = cashBalance ?? (holdings.isEmpty ? initialValue : 0)
        self.initialValue = initialValue
        self.lastUpdated = Date()
    }
    
    // Calculate total portfolio value at current prices
    func totalValue(prices: [String: Double]) -> Double {
        let holdingsValue = holdings.reduce(0.0) { total, holding in
            let price = prices[holding.symbol] ?? holding.entryPrice
            return total + holding.currentValue(at: price)
        }
        let total = holdingsValue + cashBalance
        
        // If completely empty (no holdings, no cash), return initial value
        if holdings.isEmpty && cashBalance == 0 {
            return initialValue
        }
        return total
    }
    
    // Calculate allocation percentages for all holdings
    func allocations(prices: [String: Double]) -> [String: Double] {
        let total = totalValue(prices: prices)
        guard total > 0 else { return [:] }
        
        var result: [String: Double] = [:]
        for holding in holdings {
            let price = prices[holding.symbol] ?? holding.entryPrice
            result[holding.symbol] = holding.allocationPercent(totalValue: total, currentPrice: price)
        }
        return result
    }
    
    // Calculate total profit/loss
    func totalProfitLoss(prices: [String: Double]) -> Double {
        return totalValue(prices: prices) - initialValue
    }
    
    func totalProfitLossPercent(prices: [String: Double]) -> Double {
        guard initialValue > 0 else { return 0 }
        return (totalProfitLoss(prices: prices) / initialValue) * 100
    }
}

// MARK: - Net Worth Snapshot (for historical tracking)
struct NetWorthSnapshot: Identifiable, Codable {
    let id: String
    let userId: String
    let netWorth: Double
    let timestamp: Date
    
    init(id: String = UUID().uuidString, userId: String, netWorth: Double, timestamp: Date = Date()) {
        self.id = id
        self.userId = userId
        self.netWorth = netWorth
        self.timestamp = timestamp
    }
}

// MARK: - Transaction (for audit trail)
struct Transaction: Identifiable, Codable {
    let id: String
    let userId: String
    let type: TransactionType
    let symbol: String?
    let shares: Double?
    let price: Double?
    let timestamp: Date
    let description: String
    
    enum TransactionType: String, Codable {
        case addStock
        case removeStock
        case rebalance
        case adjustAllocation
    }
    
    init(id: String = UUID().uuidString, userId: String, type: TransactionType, symbol: String? = nil, shares: Double? = nil, price: Double? = nil, description: String) {
        self.id = id
        self.userId = userId
        self.type = type
        self.symbol = symbol
        self.shares = shares
        self.price = price
        self.timestamp = Date()
        self.description = description
    }
}

// MARK: - Leaderboard Entry
struct LeaderboardEntry: Identifiable, Equatable {
    let id: String
    let user: User
    let netWorth: Double
    let rank: Int
    let profitLossPercent: Double
    
    var isPositive: Bool {
        profitLossPercent >= 0
    }
    
    static func == (lhs: LeaderboardEntry, rhs: LeaderboardEntry) -> Bool {
        lhs.id == rhs.id && lhs.rank == rhs.rank && lhs.netWorth == rhs.netWorth
    }
}

// MARK: - Stock with Owners (for Stocks View)
struct StockWithOwners: Identifiable {
    let stock: Stock
    let owners: [User]
    
    var id: String { stock.symbol }
}

// MARK: - Time Range for Charts
enum TimeRange: String, CaseIterable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case all = "All"
    
    var displayName: String { rawValue }
    
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .oneDay:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .oneWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .all:
            return calendar.date(byAdding: .year, value: -10, to: now) ?? now
        }
    }
}

// MARK: - Chart Data Point
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - API Response Models
struct FinnhubQuoteResponse: Codable {
    let c: Double  // Current price
    let d: Double? // Change
    let dp: Double? // Percent change
    let h: Double  // High price of the day
    let l: Double  // Low price of the day
    let o: Double  // Open price of the day
    let pc: Double // Previous close price
    let t: Int     // Timestamp
}

struct StockSearchResult: Identifiable, Codable {
    let symbol: String
    let description: String
    let type: String
    
    var id: String { symbol }
}

struct FinnhubSearchResponse: Codable {
    let count: Int
    let result: [FinnhubSearchResult]
}

struct FinnhubSearchResult: Codable {
    let description: String
    let displaySymbol: String
    let symbol: String
    let type: String
}

// MARK: - Price Cache Entry
struct PriceCacheEntry: Codable {
    let symbol: String
    let price: Double
    let previousClose: Double
    let timestamp: Date
    
    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 60 // 1 minute cache
    }
}
