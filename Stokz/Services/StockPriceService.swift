import Foundation

/// StockPriceService fetches live stock prices
/// Uses Yahoo Finance (no API key required)
@MainActor
class StockPriceService: ObservableObject {
    
    static let shared = StockPriceService()
    
    @Published var prices: [String: Double] = [:]
    @Published var stocks: [String: Stock] = [:]
    @Published var isLoading = false
    @Published var error: String?
    
    private var priceCache: [String: PriceCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 60 // 1 minute
    
    // MARK: - Fetch Quote (Yahoo Finance - no API key needed)
    func fetchQuote(symbol: String) async throws -> Stock {
        // Check cache first
        if let cached = priceCache[symbol], !cached.isStale {
            logDebug("Using cached price for \(symbol): $\(String(format: "%.2f", cached.price))", category: .stocks)
            return Stock(
                symbol: symbol,
                currentPrice: cached.price,
                previousClose: cached.previousClose,
                lastUpdated: cached.timestamp
            )
        }
        
        logDebug("Fetching quote for \(symbol) from Yahoo Finance", category: .stocks)
        
        // Yahoo Finance quote endpoint
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d")!
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        Logger.shared.net("GET", "Yahoo/\(symbol)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid response for \(symbol)", category: .stocks)
            throw StockPriceError.requestFailed
        }
        
        Logger.shared.netOK(httpResponse.statusCode, "Yahoo/\(symbol)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            logError("Request failed for \(symbol): HTTP \(httpResponse.statusCode)", category: .stocks)
            throw StockPriceError.requestFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Debug logging for response parsing
        if let chart = json?["chart"] as? [String: Any] {
            if let error = chart["error"] as? [String: Any] {
                let errorCode = error["code"] as? String ?? "unknown"
                let errorDesc = error["description"] as? String ?? "no description"
                logError("Yahoo Finance API error for \(symbol): \(errorCode) - \(errorDesc)", category: .stocks)
                throw StockPriceError.invalidResponse
            }
        }
        
        guard let chart = json?["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let regularMarketPrice = meta["regularMarketPrice"] as? Double else {
            // Log what we actually received for debugging
            if let jsonStr = String(data: data.prefix(500), encoding: .utf8) {
                logError("Parse failed for \(symbol). Response preview: \(jsonStr)", category: .stocks)
            }
            logError("Failed to parse response for \(symbol)", category: .stocks)
            throw StockPriceError.invalidResponse
        }
        
        // Try multiple fields for previous close - Yahoo Finance API varies
        let previousClose = meta["chartPreviousClose"] as? Double
            ?? meta["previousClose"] as? Double 
            ?? meta["regularMarketPreviousClose"] as? Double
            ?? regularMarketPrice // fallback to current price if not available
        
        // Calculate change for logging
        let dayChange = previousClose > 0 ? ((regularMarketPrice - previousClose) / previousClose) * 100 : 0
        
        let stock = Stock(
            symbol: symbol,
            currentPrice: regularMarketPrice,
            previousClose: previousClose,
            lastUpdated: Date()
        )
        
        logSuccess("\(symbol): $\(String(format: "%.2f", regularMarketPrice)) prev:$\(String(format: "%.2f", previousClose)) (\(String(format: "%+.1f", dayChange))%)", category: .stocks)
        
        // Update cache
        priceCache[symbol] = PriceCacheEntry(
            symbol: symbol,
            price: regularMarketPrice,
            previousClose: previousClose,
            timestamp: Date()
        )
        
        prices[symbol] = regularMarketPrice
        stocks[symbol] = stock
        
        return stock
    }
    
    // MARK: - Fetch Multiple Quotes
    func fetchQuotes(symbols: [String]) async throws -> [Stock] {
        logInfo("Fetching quotes for \(symbols.count) symbols: \(symbols.joined(separator: ", "))", category: .stocks)
        var results: [Stock] = []
        
        for symbol in symbols {
            do {
                let stock = try await fetchQuote(symbol: symbol)
                results.append(stock)
                
                // Small delay to avoid rate limits
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            } catch {
                logWarning("Failed to fetch quote for \(symbol): \(error.localizedDescription)", category: .stocks)
            }
        }
        
        logSuccess("Fetched \(results.count)/\(symbols.count) quotes", category: .stocks)
        return results
    }
    
    // MARK: - Search Stocks (Yahoo Finance)
    func searchStocks(query: String) async throws -> [StockSearchResult] {
        guard !query.isEmpty else { return [] }
        
        logDebug("Searching stocks for: '\(query)'", category: .stocks)
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encodedQuery)&quotesCount=10&newsCount=0")!
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        Logger.shared.net("GET", "Yahoo/search/\(query)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid response for search", category: .stocks)
            throw StockPriceError.requestFailed
        }
        
        Logger.shared.netOK(httpResponse.statusCode, "Yahoo/search")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            logError("Search request failed: HTTP \(httpResponse.statusCode)", category: .stocks)
            throw StockPriceError.requestFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let quotes = json?["quotes"] as? [[String: Any]] else {
            logWarning("No quotes found in search results", category: .stocks)
            return []
        }
        
        let results = quotes.compactMap { quote -> StockSearchResult? in
            guard let symbol = quote["symbol"] as? String,
                  let shortname = quote["shortname"] as? String ?? quote["longname"] as? String,
                  let quoteType = quote["quoteType"] as? String,
                  quoteType == "EQUITY" else {
                return nil
            }
            return StockSearchResult(symbol: symbol, description: shortname, type: quoteType)
        }
        
        logInfo("Found \(results.count) search results for '\(query)'", category: .stocks)
        return results
    }
    
    // MARK: - Refresh All Prices
    func refreshAllPrices(for symbols: [String]) async {
        logInfo("Refreshing all prices for \(symbols.count) symbols", category: .stocks)
        isLoading = true
        error = nil
        
        do {
            _ = try await fetchQuotes(symbols: symbols)
            logSuccess("All prices refreshed", category: .stocks)
        } catch {
            logError("Failed to refresh prices: \(error.localizedDescription)", category: .stocks)
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Get Price
    func getPrice(for symbol: String) -> Double {
        return prices[symbol] ?? 0
    }
    
    // MARK: - Get Stock
    func getStock(for symbol: String) -> Stock? {
        return stocks[symbol]
    }
    
    // MARK: - Clear Cache
    func clearCache() {
        logInfo("Clearing stock price cache", category: .stocks)
        priceCache.removeAll()
        prices.removeAll()
        stocks.removeAll()
    }
}

// MARK: - Errors
enum StockPriceError: Error, LocalizedError {
    case requestFailed
    case invalidSymbol
    case invalidResponse
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Failed to fetch stock data"
        case .invalidSymbol:
            return "Invalid stock symbol"
        case .invalidResponse:
            return "Invalid response from API"
        case .rateLimited:
            return "API rate limit exceeded. Please try again later."
        }
    }
}

// MARK: - Mock Data for Development
extension StockPriceService {
    func loadMockData() {
        let mockStocks: [(String, Double, Double)] = [
            ("AAPL", 178.50, 176.20),
            ("GOOGL", 141.80, 140.50),
            ("MSFT", 378.90, 375.00),
            ("TSLA", 248.50, 252.30),
            ("NVDA", 495.20, 488.00),
            ("AMZN", 185.60, 183.40),
            ("META", 505.75, 498.20),
            ("NFLX", 485.30, 480.10),
            ("AMD", 145.80, 142.50),
            ("DIS", 112.40, 114.20)
        ]
        
        for (symbol, price, prevClose) in mockStocks {
            let stock = Stock(
                symbol: symbol,
                currentPrice: price,
                previousClose: prevClose,
                lastUpdated: Date()
            )
            stocks[symbol] = stock
            prices[symbol] = price
            priceCache[symbol] = PriceCacheEntry(
                symbol: symbol,
                price: price,
                previousClose: prevClose,
                timestamp: Date()
            )
        }
    }
    
    // Simulate price updates for demo
    func simulatePriceUpdate() {
        for symbol in stocks.keys {
            guard var stock = stocks[symbol] else { continue }
            
            // Random price movement within 2%
            let change = stock.currentPrice * Double.random(in: -0.02...0.02)
            stock = Stock(
                symbol: symbol,
                currentPrice: stock.currentPrice + change,
                previousClose: stock.previousClose,
                lastUpdated: Date()
            )
            
            stocks[symbol] = stock
            prices[symbol] = stock.currentPrice
        }
    }
}
