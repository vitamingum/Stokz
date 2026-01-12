import Foundation

/// StockScreenerService - AI-powered stock screening using map-reduce pattern
/// 1. Generate criteria from natural language prompt
/// 2. Batch-evaluate all stocks in parallel
/// 3. Merge results and present top picks
@MainActor
class StockScreenerService: ObservableObject {
    static let shared = StockScreenerService()
    
    // MARK: - Configuration
    private let batchSize = 25  // Stocks per API call (smaller = better quality)
    private let maxParallel = 5  // Concurrent API calls
    private let topCandidates = 30  // Stocks to pass to final round
    
    // MARK: - State
    @Published var isScreening = false
    @Published var progress: ScreeningProgress = .idle
    @Published var results: [StockPick] = []
    @Published var lastError: String?
    @Published var lastPrompt: String = ""  // Store for detail view
    
    // Live feed for UI
    @Published var liveFeed: [FeedItem] = []
    @Published var topScorers: [ScoredStock] = []  // Running top picks
    
    private init() {}
    
    /// A single item in the live feed
    struct FeedItem: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: FeedType
        let message: String
        
        enum FeedType {
            case system
            case batch
            case found
            case error
        }
    }
    
    // MARK: - Main Entry Point
    
    /// Screen stocks based on natural language prompt
    func screen(prompt: String) async {
        guard !isScreening else { return }
        
        isScreening = true
        progress = .generatingCriteria
        results = []
        lastError = nil
        liveFeed = []
        topScorers = []
        lastPrompt = prompt  // Store for detail view
        
        addFeed(.system, "Starting AI screening...")
        print("🔍 [Screener] Starting screen for: \(prompt)")
        
        do {
            // Step 1: Generate criteria from prompt
            addFeed(.system, "Analyzing your criteria...")
            let criteria = try await generateCriteria(prompt: prompt)
            addFeed(.system, "Criteria ready: scoring \(getAllStocks().count) stocks")
            print("🔍 [Screener] Criteria: \(criteria.batchPrompt)")
            
            // Step 2: Get all stocks from bundle
            let allStocks = getAllStocks()
            print("🔍 [Screener] Screening \(allStocks.count) stocks")
            
            // Step 3: Batch evaluate
            let scored = try await batchEvaluate(stocks: allStocks, criteria: criteria)
            print("🔍 [Screener] Got \(scored.count) scored stocks")
            
            // Step 4: Final analysis on top candidates
            let topN = Array(scored.prefix(topCandidates))
            progress = .finalAnalysis
            addFeed(.system, "Running final analysis on top \(topN.count) candidates...")
            let picks = try await finalAnalysis(candidates: topN, originalPrompt: prompt, criteria: criteria)
            
            results = picks
            progress = .complete(picks.count)
            addFeed(.system, "✅ Found \(picks.count) stocks matching your criteria!")
            print("🔍 [Screener] Complete! \(picks.count) picks")
            
        } catch {
            print("🔍 [Screener] Error: \(error)")
            addFeed(.error, "Error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            progress = .error(error.localizedDescription)
        }
        
        isScreening = false
    }
    
    // MARK: - Detail Thesis Generation
    
    /// Generate a detailed thesis for a single stock based on the user's criteria
    func getDetailedThesis(ticker: String, company: String) async -> String {
        guard !lastPrompt.isEmpty else {
            return "No search criteria available."
        }
        
        let prompt = """
        User's search criteria: "\(lastPrompt)"
        
        Stock: \(ticker) (\(company))
        
        Write a bullet-point analysis:
        
        • COMPANY: One line about what the company does
        
        • WHY IT MATCHES:
          - [reason 1]
          - [reason 2]
          - [reason 3]
          - [reason 4]
          - [reason 5]
        
        • WATCH OUT: One key risk or reason it might NOT match
        
        Be specific and concise. Use plain text bullets (• and -), no markdown.
        """
        
        do {
            let response = try await GeminiService.shared.chat(
                system: "You are a stock analyst. Write structured bullet-point analyses. Use • for main bullets and - for sub-bullets. No markdown formatting, no asterisks.",
                user: prompt
            )
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("❌ [Screener] Detail thesis error: \(error)")
            return "Unable to generate thesis."
        }
    }
    
    // MARK: - Step 1: Generate Criteria (simplified - just wrap user prompt)
    
    private func generateCriteria(prompt: String) async throws -> ScreeningCriteria {
        // Just pass the user's prompt directly - no LLM reinterpretation
        return ScreeningCriteria(
            batchPrompt: prompt,
            resultCount: 6
        )
    }
    
    // MARK: - Step 2: Batch Evaluate
    
    private func batchEvaluate(stocks: [(ticker: String, fact: StockFact)], criteria: ScreeningCriteria) async throws -> [ScoredStock] {
        let batches = stocks.chunked(into: batchSize)
        let totalBatches = batches.count
        
        var allScored: [ScoredStock] = []
        addFeed(.batch, "Evaluating \(stocks.count) stocks in \(totalBatches) batches...")
        
        // Process in parallel groups
        for (groupIndex, batchGroup) in batches.chunked(into: maxParallel).enumerated() {
            let groupStart = groupIndex * maxParallel
            
            // Update progress
            progress = .evaluating(completed: groupStart, total: totalBatches)
            
            // Run this group in parallel
            let groupResults = await withTaskGroup(of: (batchNum: Int, scores: [ScoredStock]).self) { group in
                for (batchIndex, batch) in batchGroup.enumerated() {
                    let batchNum = groupStart + batchIndex + 1
                    group.addTask {
                        print("🔍 [Screener] Processing batch \(batchNum)/\(totalBatches)")
                        
                        do {
                            let scores = try await self.evaluateBatch(batch, criteria: criteria)
                            return (batchNum, scores)
                        } catch {
                            print("🔍 [Screener] Batch \(batchNum) failed: \(error)")
                            return (batchNum, [])
                        }
                    }
                }
                
                var results: [ScoredStock] = []
                for await (batchNum, batchScores) in group {
                    results.append(contentsOf: batchScores)
                    
                    // Post feed updates on main thread
                    await MainActor.run {
                        // Find high scorers from this batch
                        let highScorers = batchScores.filter { $0.score >= 6 }
                        if !highScorers.isEmpty {
                            let names = highScorers.prefix(3).map { "\($0.ticker)(\($0.score))" }.joined(separator: " ")
                            self.addFeed(.found, "Batch \(batchNum): \(names)")
                        } else {
                            self.addFeed(.batch, "Batch \(batchNum)/\(totalBatches) complete")
                        }
                        self.updateTopScorers(with: batchScores)
                    }
                }
                return results
            }
            
            allScored.append(contentsOf: groupResults)
        }
        
        addFeed(.system, "Scored \(allScored.count) stocks, selecting top candidates...")
        
        // Sort by score descending
        return allScored.sorted { $0.score > $1.score }
    }
    
    private func evaluateBatch(_ batch: [(ticker: String, fact: StockFact)], criteria: ScreeningCriteria) async throws -> [ScoredStock] {
        let stockList = batch.map { ticker, fact in
            "\(ticker) (\(fact.company))"
        }.joined(separator: ", ")
        
        let prompt = """
        User's request: \(criteria.batchPrompt)
        
        Stocks: \(stockList)
        
        Score each 0-10 using ABSOLUTE scoring (not relative to this batch):
        - 0-3: Does not match
        - 4-6: Partial match  
        - 7-8: Strong match
        - 9-10: Exceptional match (rare - 1-2% of all stocks)
        
        If none match well, give all low scores. Return JSON only: [{"ticker": "X", "score": 0-10, "reason": "brief"}]
        """
        
        let response = try await GeminiService.shared.chat(
            system: "You are a stock analyst with deep knowledge of public companies. Use your training knowledge to evaluate stocks. Return only valid JSON array.",
            user: prompt
        )
        
        // Parse response
        return parseScores(response)
    }
    
    // MARK: - Step 3: Final Analysis
    
    private func finalAnalysis(candidates: [ScoredStock], originalPrompt: String, criteria: ScreeningCriteria) async throws -> [StockPick] {
        let candidateList = candidates.map { scored in
            "\(scored.ticker) (score: \(scored.score)): \(scored.reason)"
        }.joined(separator: "\n")
        
        let prompt = """
        User's request: "\(originalPrompt)"
        
        Top candidates from screening:
        \(candidateList)
        
        Pick the best \(criteria.resultCount) that match the user's request.
        
        Return JSON array only: [{"ticker": "X", "score": 85-100, "thesis": "Brief reason (max 15 words)"}]
        """
        
        let response = try await GeminiService.shared.chat(
            system: "You are a stock analyst. Respect the user's intent. Return only valid JSON array.",
            user: prompt
        )
        
        return parsePicks(response)
    }
    
    // MARK: - Feed Helpers
    
    private func addFeed(_ type: FeedItem.FeedType, _ message: String) {
        let item = FeedItem(timestamp: Date(), type: type, message: message)
        liveFeed.append(item)
        // Keep feed manageable
        if liveFeed.count > 50 {
            liveFeed.removeFirst()
        }
    }
    
    private func updateTopScorers(with newScores: [ScoredStock]) {
        // Merge new scores with existing top scorers
        var combined = topScorers + newScores
        combined.sort { $0.score > $1.score }
        topScorers = Array(combined.prefix(10))  // Keep top 10
    }
    
    // MARK: - Helpers
    
    private func getAllStocks() -> [(ticker: String, fact: StockFact)] {
        let service = StockDataService.shared
        var result: [(String, StockFact)] = []
        
        // Get all tickers and their facts
        // We need to iterate through what's available
        // StockDataService has getFact(ticker:) but we need all tickers
        // Let's access the facts directly if possible, or use a known list
        
        // For now, get tickers from the similarity keys (they should match facts)
        for ticker in getKnownTickers() {
            if let fact = service.getFact(ticker: ticker) {
                result.append((ticker, fact))
            }
        }
        
        return result
    }
    
    private func getKnownTickers() -> [String] {
        // Get all tickers from StockDataService
        return StockDataService.shared.allTickers
    }
    
    private func parseScores(_ response: String) -> [ScoredStock] {
        // Try to extract JSON from response
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("🔍 [Screener] Failed to parse scores: \(response.prefix(200))")
            return []
        }
        
        return array.compactMap { item -> ScoredStock? in
            guard let ticker = item["ticker"] as? String,
                  let score = (item["score"] as? Double) ?? (item["score"] as? Int).map({ Double($0) }) else {
                return nil
            }
            let reason = item["reason"] as? String ?? ""
            return ScoredStock(ticker: ticker, score: score, reason: reason)
        }
    }
    
    private func parsePicks(_ response: String) -> [StockPick] {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("🔍 [Screener] Failed to parse picks: \(response.prefix(200))")
            return []
        }
        
        return array.compactMap { item -> StockPick? in
            guard let ticker = item["ticker"] as? String else { return nil }
            let score = (item["score"] as? Double) ?? (item["score"] as? Int).map({ Double($0) }) ?? 0
            let thesis = item["thesis"] as? String ?? ""
            let fact = StockDataService.shared.getFact(ticker: ticker)
            return StockPick(ticker: ticker, score: score, thesis: thesis, company: fact?.company ?? ticker)
        }
    }
}

// MARK: - Models

struct ScreeningCriteria {
    let batchPrompt: String
    let resultCount: Int
}

struct ScoredStock {
    let ticker: String
    let score: Double
    let reason: String
}

struct StockPick: Identifiable {
    let id = UUID()
    let ticker: String
    let score: Double
    let thesis: String
    let company: String
}

enum ScreeningProgress: Equatable {
    case idle
    case generatingCriteria
    case evaluating(completed: Int, total: Int)
    case finalAnalysis
    case complete(Int)
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return ""
        case .generatingCriteria: return "Analyzing your request..."
        case .evaluating(let completed, let total): return "Screening stocks... \(completed)/\(total)"
        case .finalAnalysis: return "Selecting top picks..."
        case .complete(let count): return "Found \(count) matches"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
