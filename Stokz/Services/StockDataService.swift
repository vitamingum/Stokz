import Foundation
import OSLog

private let stockLogger = OSLog(subsystem: "com.stokz.app", category: "StockData")

// MARK: - Data Models

/// Stock fact card with company summary and metadata
struct StockFact: Codable {
    let company: String
    let sector: String
    let subIndustry: String
    let summary: String
    let industry: String?
    let tags: [String]?
    let founded: String?  // JSON has mixed types (string or int)
    let headquarters: String?
    
    enum CodingKeys: String, CodingKey {
        case company, sector, subIndustry, summary, industry, tags, founded, headquarters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        company = try container.decode(String.self, forKey: .company)
        sector = try container.decode(String.self, forKey: .sector)
        subIndustry = try container.decode(String.self, forKey: .subIndustry)
        summary = try container.decode(String.self, forKey: .summary)
        industry = try container.decodeIfPresent(String.self, forKey: .industry)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        headquarters = try container.decodeIfPresent(String.self, forKey: .headquarters)
        
        // Handle founded as either String or Int
        if let foundedString = try? container.decodeIfPresent(String.self, forKey: .founded) {
            founded = foundedString
        } else if let foundedInt = try? container.decodeIfPresent(Int.self, forKey: .founded) {
            founded = String(foundedInt)
        } else {
            founded = nil
        }
    }
}

/// Similar stock entry
struct SimilarStock: Codable {
    let ticker: String
    let score: Double
}

/// Root data bundle structure
struct StockDataBundle: Codable {
    let facts: [String: StockFact]
    let similarity: [String: [SimilarStock]]
    let version: String
    let stockCount: Int
}

/// Service for loading and querying stock data + AI similarity
class StockDataService {
    static let shared = StockDataService()
    
    private(set) var isLoaded = false
    private(set) var stockCount: Int = 0
    
    private var facts: [String: StockFact] = [:]
    private var similarity: [String: [SimilarStock]] = [:]
    
    private init() {
        print("🔮 [StockData] StockDataService init starting...")
        loadBundle()
        print("🔮 [StockData] StockDataService init complete. Loaded: \(isLoaded), count: \(stockCount)")
    }
    
    // MARK: - Load Data
    
    private func loadBundle() {
        print("🔮 [StockData] loadBundle() starting...")
        os_log("🔄 Starting to load stock data bundle...", log: stockLogger, type: .info)
        
        guard let url = Bundle.main.url(forResource: "stock_data_bundle", withExtension: "json") else {
            print("🔮 [StockData] ❌ stock_data_bundle.json NOT FOUND in bundle!")
            os_log("❌ stock_data_bundle.json not found in bundle", log: stockLogger, type: .error)
            return
        }
        
        print("🔮 [StockData] Found bundle at: \(url.path)")
        os_log("📂 Found bundle at path", log: stockLogger, type: .info)
        
        do {
            let data = try Data(contentsOf: url)
            print("🔮 [StockData] Loaded \(data.count) bytes")
            os_log("📊 Loaded %d bytes", log: stockLogger, type: .info, data.count)
            
            let bundle = try JSONDecoder().decode(StockDataBundle.self, from: data)
            print("🔮 [StockData] Decoded bundle: \(bundle.stockCount) stocks, version: \(bundle.version)")
            
            self.facts = bundle.facts
            self.similarity = bundle.similarity
            self.stockCount = bundle.stockCount
            self.isLoaded = true
            
            print("🔮 [StockData] ✅ SUCCESS! Loaded \(stockCount) stock facts")
            os_log("✅ Loaded %d stock facts", log: stockLogger, type: .info, bundle.stockCount)
        } catch {
            print("🔮 [StockData] ❌ DECODE ERROR: \(error)")
            os_log("❌ Failed to load: %{public}@", log: stockLogger, type: .error, error.localizedDescription)
        }
    }
    
    // MARK: - Fact Cards
    
    /// Get fact card for a ticker
    func getFact(ticker: String) -> StockFact? {
        let fact = facts[ticker]
        print("🔮 [StockData] getFact(\(ticker)): \(fact != nil ? "found" : "NOT FOUND")")
        return fact
    }
    
    /// Get summary text for a ticker (for display)
    func getSummary(ticker: String) -> String? {
        return facts[ticker]?.summary
    }
    
    /// Get company name for a ticker
    func getCompanyName(ticker: String) -> String? {
        return facts[ticker]?.company
    }
    
    /// Get sector for a ticker
    func getSector(ticker: String) -> String? {
        return facts[ticker]?.sector
    }
    
    // MARK: - Similarity Search
    
    /// Find stocks similar to the given ticker
    func findSimilar(to ticker: String, limit: Int = 5) -> [(ticker: String, score: Double, fact: StockFact?)] {
        guard let similar = similarity[ticker] else { return [] }
        
        return similar.prefix(limit).map { s in
            (ticker: s.ticker, score: s.score, fact: facts[s.ticker])
        }
    }
    
    /// Find stocks similar to a portfolio (union of all similar stocks)
    func findSimilarToPortfolio(tickers: [String], limit: Int = 10) -> [(ticker: String, score: Double, fact: StockFact?)] {
        var scores: [String: Double] = [:]
        let ownedSet = Set(tickers)
        
        for ticker in tickers {
            guard let similar = similarity[ticker] else { continue }
            for s in similar {
                // Skip if already owned
                if ownedSet.contains(s.ticker) { continue }
                // Accumulate scores (higher = more similar to portfolio)
                scores[s.ticker, default: 0] += s.score
            }
        }
        
        // Sort by accumulated score
        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (ticker: $0.key, score: $0.value, fact: facts[$0.key]) }
    }
    
    // MARK: - Portfolio Analysis
    
    /// Get sector breakdown for a list of tickers
    func getSectorBreakdown(tickers: [String]) -> [String: Int] {
        var sectors: [String: Int] = [:]
        for ticker in tickers {
            if let fact = facts[ticker] {
                sectors[fact.sector, default: 0] += 1
            }
        }
        return sectors
    }
    
    /// Generate investment style summary for a portfolio
    func getInvestmentStyle(tickers: [String]) -> String {
        let sectors = getSectorBreakdown(tickers: tickers)
        guard !sectors.isEmpty else { return "Diversified portfolio" }
        
        // Sort by count
        let sorted = sectors.sorted { $0.value > $1.value }
        let topSector = sorted.first!
        let total = tickers.count
        let topPct = Int(Double(topSector.value) / Double(total) * 100)
        
        if topPct >= 50 {
            return "\(topSector.key) focused (\(topPct)%)"
        } else if sorted.count >= 3 {
            return "Diversified across \(sorted.count) sectors"
        } else {
            let names = sorted.prefix(2).map { $0.key }.joined(separator: " & ")
            return "\(names) mix"
        }
    }
    
    // MARK: - Search
    
    /// Search stocks by query (ticker, company, sector, or tags)
    func searchStocks(query: String) -> [(ticker: String, fact: StockFact)] {
        let q = query.lowercased()
        return facts.compactMap { ticker, fact in
            let matches = ticker.lowercased().contains(q) ||
                fact.company.lowercased().contains(q) ||
                fact.sector.lowercased().contains(q) ||
                (fact.tags?.contains { $0.lowercased().contains(q) } ?? false)
            return matches ? (ticker: ticker, fact: fact) : nil
        }.sorted { $0.ticker < $1.ticker }
    }
    
    /// Get all available tickers
    var allTickers: [String] {
        Array(facts.keys).sorted()
    }
}
