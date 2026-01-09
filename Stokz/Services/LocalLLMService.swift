import Foundation
import SwiftUI

/// Local LLM Service - Emoji generation with persistent caching
/// Shows skull placeholder until emoji is ready
@MainActor
class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()
    
    // MARK: - Model Config - TinyLlama 1.1B Chat (recommended by llama.cpp)
    private let modelURL = URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q8_0.gguf?download=true")!
    private let modelFileName = "tinyllama-1.1b-chat-v1.0.Q8_0.gguf"
    private let modelSize: Int64 = 1_100_000_000  // ~1.1GB
    
    // MARK: - LLM Context
    private var llamaContext: LlamaContext?
    @Published var isLoadingModel = false
    
    // MARK: - State
    @Published var isModelDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var lastError: String?
    @Published var statusMessage: String = "Initializing..."
    
    // MARK: - Emoji Caches (Persistent - survives refreshes)
    private var stockSearchCache: [String: String] = [:]
    private var stocksTabCache: [String: String] = [:]
    private var portfolioCache: [String: String] = [:]
    private var leaderboardCache: [String: String] = [:]
    
    // Track used emojis per context to avoid duplicates within a screen
    private var usedPortfolioEmojis: Set<String> = []
    private var usedLeaderboardEmojis: Set<String> = []
    
    // Track pending generations to avoid duplicates
    private var pendingGenerations: Set<String> = []
    
    // MARK: - Constants
    static let placeholder = "\u{1F480}"  // skull emoji
    
    private var modelPath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models/\(modelFileName)")
    }
    
    // MARK: - Initialization
    
    private init() {
        Logger.shared.info("LLM init", category: .llm)
        checkModelExists()
        loadCachesFromDisk()
        migrateStyleCache()  // Clear old style entries so they regenerate with LLM
        Logger.shared.info("Cache: s\(stockSearchCache.count) t\(stocksTabCache.count) p\(portfolioCache.count) l\(leaderboardCache.count)", category: .llm)
        
        // Update status
        if isModelDownloaded {
            statusMessage = "Model ready"
        } else {
            statusMessage = "Model not downloaded"
        }
    }
    
    /// Clear ALL style caches to force regeneration with LLM
    private func migrateStyleCache() {
        // ALWAYS clear all style entries to force LLM regeneration (v10)
        let styleKeys = leaderboardCache.keys.filter { $0.hasPrefix("style") }
        Logger.shared.info("Clearing ALL \(styleKeys.count) style cache entries for LLM regeneration", category: .llm)
        for key in styleKeys {
            leaderboardCache.removeValue(forKey: key)
        }
        if !styleKeys.isEmpty {
            saveCachesToDisk()
        }
    }
    
    // MARK: - Auto Setup (call on app launch)
    
    /// Automatically download and load model - call this on app startup
    func autoSetup() async {
        Logger.shared.info("autoSetup called - downloaded:\(isModelDownloaded) downloading:\(isDownloading)", category: .llm)
        if !isModelDownloaded && !isDownloading {
            Logger.shared.info("Starting automatic model download...", category: .llm)
            statusMessage = "Downloading AI model..."
            await downloadModel()
        }
        
        if isModelDownloaded && llamaContext == nil && !isLoadingModel {
            Logger.shared.info("Starting automatic model load...", category: .llm)
            statusMessage = "Loading AI model..."
            await loadModel()
        }
    }
    
    // MARK: - Model Management
    
    func checkModelExists() {
        isModelDownloaded = FileManager.default.fileExists(atPath: modelPath.path)
        Logger.shared.debug("Model: \(isModelDownloaded ? "ready" : "none")", category: .llm)
    }
    
    private func downloadModel() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        lastError = nil
        statusMessage = "Downloading AI model..."
        
        Logger.shared.info("Download starting", category: .llm)
        
        let modelsDir = modelPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        do {
            let (tempURL, response) = try await downloadWithProgress(from: modelURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LLMError.downloadFailed("Bad status")
            }
            
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: modelPath)
            isModelDownloaded = true
            statusMessage = "Download complete, loading..."
            Logger.shared.success("Download complete", category: .llm)
            
            // Auto-load after download
            isDownloading = false
            await loadModel()
            return
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Download failed"
            Logger.shared.error("Download: \(error.localizedDescription.prefix(40))", category: .llm)
        }
        
        isDownloading = false
    }
    
    private func downloadWithProgress(from url: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let localURL = localURL, let response = response else {
                    continuation.resume(throwing: LLMError.downloadFailed("No data"))
                    return
                }
                let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: localURL, to: tempFile)
                    continuation.resume(returning: (tempFile, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] prog, _ in
                Task { @MainActor in self?.downloadProgress = prog.fractionCompleted }
            }
            task.resume()
            DispatchQueue.global().asyncAfter(deadline: .now() + 7200) { _ = observation }
        }
    }
    
    func deleteModel() {
        Logger.shared.info("Model deleted", category: .llm)
        try? FileManager.default.removeItem(at: modelPath)
        isModelDownloaded = false
        llamaContext = nil  // Release the context
    }
    
    var modelSizeString: String {
        ByteCountFormatter.string(fromByteCount: modelSize, countStyle: .file)
    }
    
    // MARK: - Model Loading
    
    /// Load the LLM model into memory for inference
    func loadModel() async {
        guard isModelDownloaded, llamaContext == nil, !isLoadingModel else { return }
        isLoadingModel = true
        statusMessage = "Loading AI model..."
        Logger.shared.info("Loading LLM model...", category: .llm)
        
        do {
            llamaContext = try await LlamaContext.create(modelPath: modelPath.path)
            statusMessage = "AI ready ✓"
            Logger.shared.success("LLM model loaded!", category: .llm)
            
            // Notify that model is ready - views can refresh
            objectWillChange.send()
        } catch {
            Logger.shared.error("Failed to load LLM: \(error.localizedDescription)", category: .llm)
            lastError = "Model load failed: \(error.localizedDescription)"
            statusMessage = "Load failed"
        }
        
        isLoadingModel = false
    }
    
    /// Check if the model is loaded and ready for inference
    var isModelLoaded: Bool {
        llamaContext != nil
    }
    
    // MARK: - Stock Search Emoji
    
    func getStockSearchEmoji(symbol: String, companyName: String) -> String {
        let key = symbol.uppercased()
        if let cached = stockSearchCache[key] { return cached }
        
        if !pendingGenerations.contains("s_\(key)") {
            pendingGenerations.insert("s_\(key)")
            Task {
                let emoji = generateSearchEmoji(symbol: symbol, name: companyName)
                stockSearchCache[key] = emoji
                pendingGenerations.remove("s_\(key)")
                saveCachesToDisk()
                objectWillChange.send()
                Logger.shared.debug("\(emoji) \(symbol)", category: .llm)
            }
        }
        return Self.placeholder
    }
    
    private func generateSearchEmoji(symbol: String, name: String) -> String {
        let n = name.lowercased()
        let s = symbol.uppercased()
        
        // Well-known companies
        if n.contains("apple") || s == "AAPL" { return "\u{1F34E}" }  // red apple
        if n.contains("microsoft") || s == "MSFT" { return "\u{1F4BB}" }  // laptop
        if n.contains("google") || n.contains("alphabet") { return "\u{1F50D}" }  // magnifier
        if n.contains("amazon") || s == "AMZN" { return "\u{1F4E6}" }  // package
        if n.contains("meta") || n.contains("facebook") { return "\u{1F464}" }  // bust
        if n.contains("nvidia") || s == "NVDA" { return "\u{1F3AE}" }  // controller
        if n.contains("tesla") || s == "TSLA" { return "\u{1F697}" }  // car
        if n.contains("netflix") { return "\u{1F3AC}" }  // clapper
        if n.contains("disney") { return "\u{1F3F0}" }  // castle
        if n.contains("spotify") { return "\u{1F3B5}" }  // musical note
        if n.contains("bank") || n.contains("financial") { return "\u{1F3E6}" }  // bank
        if n.contains("visa") || n.contains("mastercard") { return "\u{1F4B3}" }  // credit card
        if n.contains("walmart") { return "\u{1F6D2}" }  // shopping cart
        if n.contains("starbucks") { return "\u{2615}" }  // coffee
        if n.contains("mcdonald") { return "\u{1F354}" }  // burger
        if n.contains("nike") { return "\u{1F45F}" }  // shoe
        if n.contains("pharma") || n.contains("health") { return "\u{1F48A}" }  // pill
        if n.contains("oil") || n.contains("exxon") { return "\u{26FD}" }  // fuel pump
        if n.contains("airline") { return "\u{2708}" }  // airplane
        if n.contains("game") || n.contains("entertainment") { return "\u{1F3AE}" }  // controller
        if n.contains("food") || n.contains("restaurant") { return "\u{1F37D}" }  // fork and knife
        if n.contains("auto") || n.contains("motor") { return "\u{1F697}" }  // car
        
        let defaults = ["\u{1F4CA}", "\u{1F4B9}", "\u{1F4C8}", "\u{1F3E2}", "\u{1F4BC}", "\u{1F3ED}", "\u{1F310}", "\u{26A1}"]
        return defaults[abs(symbol.hashValue) % defaults.count]
    }
    
    // MARK: - Stocks Tab Emoji (Ranked WSB Style)
    
    /// Get emoji for stocks tab - only 🚀 for best performer at +7%, 🤡 for worst at -7%
    func getStocksTabEmoji(symbol: String, rank: Int, totalStocks: Int, dayChangePercent: Double) -> String {
        return getRankedEmoji(rank: rank, total: totalStocks, dayChangePercent: dayChangePercent)
    }
    
    /// Get emoji based on day change (for notable moves)
    private func getMovementEmoji(dayChange: Double) -> String {
        if dayChange >= 10 {
            return "💎"  // Diamond - massive gains
        } else if dayChange >= 5 {
            return "🚀"  // Rocket - solid gains
        } else if dayChange <= -10 {
            return "🤡"  // Clown - big loss
        } else if dayChange <= -5 {
            return "💀"  // Skull - notable loss
        }
        return ""
    }
    
    /// Get emoji based on rank position - SIMPLIFIED: only rocket and clown for extreme performers
    private func getRankedEmoji(rank: Int, total: Int, dayChangePercent: Double) -> String {
        guard total > 0 else { return "" }
        
        // Only show emoji for ±7% daily change AND must be best/worst performer
        if dayChangePercent >= 7 && rank == 1 {
            return "🚀"  // Rocket for best performer with +7%+
        } else if dayChangePercent <= -7 && rank == total {
            return "🤡"  // Clown for worst performer with -7%+
        }
        
        return ""  // No emoji for normal moves
    }
    
        // MARK: - Portfolio Emoji (with deduplication)
    
    /// Call this at the start of rendering portfolio to reset used emojis
    func resetPortfolioEmojis() {
        usedPortfolioEmojis.removeAll()
    }
    
    /// Get emoji for portfolio - only 🚀 for best performer at +7%, 🤡 for worst at -7%
    func getPortfolioEmoji(symbol: String, rank: Int, totalHoldings: Int, dayChangePercent: Double) -> String {
        return getRankedEmoji(rank: rank, total: totalHoldings, dayChangePercent: dayChangePercent)
    }
    
    // Keep old signature for backward compatibility
    func getPortfolioEmoji(symbol: String, dayChangePercent: Double) -> String {
        return ""  // No emoji without rank context
    }
    
    private func generatePortfolioEmoji(symbol: String, dayChange: Double) -> String {
        return ""  // Deprecated - no longer used
    }
    
    // MARK: - Leaderboard Emoji (with deduplication)
    
    /// Call this at the start of rendering leaderboard to reset used emojis
    func resetLeaderboardEmojis() {
        usedLeaderboardEmojis.removeAll()
    }

    /// Get emoji for leaderboard - only 💎 for 1st place, 🤡 for last place
    func getLeaderboardEmoji(userId: String, rank: Int, totalPlayers: Int, profitLossPercent: Double) -> String {
        return generateLeaderboardEmoji(rank: rank, total: totalPlayers)
    }
    
    private func generateLeaderboardEmoji(rank: Int, total: Int) -> String {
        // Only first and last place get emojis
        guard total > 1 else { return "" }
        
        if rank == 1 {
            return "💎"  // Diamond for 1st place
        } else if rank == total {
            return "🤡"  // Clown for last place
        }
        
        return ""  // No emoji for middle ranks
    }
    
    // MARK: - Cash Emoji (Portfolio View) - REMOVED
    
    func getCashEmoji(cashBalance: Double, totalValue: Double) -> String {
        return ""  // No cash emoji
    }
    
    // MARK: - Net Worth Movement Emoji (Portfolio View)
    
    func getNetWorthEmoji(profitLossPercent: Double) -> String {
        // Use the same WSB scale as leaderboard, based on P/L performance
        return generateNetWorthEmoji(pl: profitLossPercent)
    }
    
    private func generateNetWorthEmoji(pl: Double) -> String {
        // Same WSB scale as leaderboard: diamond at top, clown at bottom
        let wsbScale: [String] = [
            "💎",  // Diamond hands
            "🦍",  // Ape
            "🚀",  // Rocket
            "🐂",  // Bull
            "💪",  // Gains
            "📈",  // Up
            "👍",  // Good
            "😐",  // Flat
            "📉",  // Down
            "🐻",  // Bear
            "💸",  // Money gone
            "😰",  // Sweating
            "☠️",  // Dead
            "💀",  // Skull
            "🤡"   // Clown
        ]
        
        // Map P/L% to scale position
        // +20% or more = diamond, -20% or less = clown
        let scaleSize = wsbScale.count
        let clampedPL = max(-20.0, min(20.0, pl))  // Clamp between -20 and +20
        
        // Normalize: +20 -> 0, -20 -> 14
        let ratio = (20.0 - clampedPL) / 40.0
        let position = min(Int(ratio * Double(scaleSize)), scaleSize - 1)
        
        return wsbScale[position]
    }
    
    // MARK: - Investment Style Generator
    
    /// Generate a witty one-liner about a player's investment style based on their holdings
    func getInvestmentStyle(userId: String, holdings: [String]) async -> String {
        // If model not ready, return pending indicator (don't cache this)
        guard isModelLoaded else {
            return "..."  // Shows pending while model loads
        }
        
        guard !holdings.isEmpty else {
            return "Just getting started"
        }
        
        // Include sorted holdings in cache key so style refreshes when portfolio changes
        let holdingsKey = holdings.sorted().joined(separator: ",")
        let key = "style12_\(userId)_\(holdingsKey.hashValue)"  // v12 - improved explicit prompt with sector themes
        if let cached = leaderboardCache[key] {
            Logger.shared.debug("Style cache hit for \(userId): \(cached)", category: .llm)
            return cached
        }
        
        // Clear old style entries for this user (different holdings)
        leaderboardCache = leaderboardCache.filter { !$0.key.hasPrefix("style") || !$0.key.contains(userId) }
        
        // Generate with LLM
        let style = await generateStyleWithLLM(context: llamaContext!, tickers: holdings)
        
        Logger.shared.info("Generated style for \(userId): \(style)", category: .llm)
        leaderboardCache[key] = style
        saveCachesToDisk()
        return style
    }
    
    /// Generate investment style using actual LLM inference
    private func generateStyleWithLLM(context: LlamaContext, tickers: [String]) async -> String {
        // Figure out what sectors dominate their portfolio
        var sectorCounts: [String: Int] = [:]
        var companyNames: [String] = []
        
        for ticker in tickers.prefix(6) {
            if let fact = StockDataService.shared.getFact(ticker: ticker) {
                companyNames.append(fact.company)
                sectorCounts[fact.sector, default: 0] += 1
            }
        }
        
        // Find dominant sector
        let topSector = sectorCounts.max(by: { $0.value < $1.value })?.key ?? "mixed"
        let sectorNote = sectorCounts.count == 1 ? "all \(topSector)" : "mostly \(topSector)"
        
        let stockList = companyNames.prefix(4).joined(separator: ", ")
        
        // Very explicit few-shot prompt
        let prompt = """
Complete the investor nickname. Be creative and fun. 3-5 words max.

Stocks: Tesla, Rivian, Lucid Motors | Theme: all electric vehicles
Nickname: EV dreamer forever

Stocks: Nvidia, AMD, Intel | Theme: all semiconductors  
Nickname: Silicon chip junkie

Stocks: Apple, Microsoft, Google | Theme: all big tech
Nickname: Big tech believer

Stocks: Coca-Cola, PepsiCo, McDonald's | Theme: all consumer brands
Nickname: Consumer goods fan

Stocks: \(stockList) | Theme: \(sectorNote)
Nickname: 
"""
        
        Logger.shared.debug("LLM prompt: \(prompt.prefix(200))...", category: .llm)
        
        do {
            let result = try await context.complete(prompt: prompt, maxTokens: 20)
            Logger.shared.debug("LLM raw output: '\(result)'", category: .llm)
            
            // Clean up the result
            var cleaned = result
                .replacingOccurrences(of: "</s>", with: "")
                .replacingOccurrences(of: "<|", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Take first line only
            if let firstLine = cleaned.split(separator: "\n").first {
                cleaned = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Remove quotes if present
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            
            // If still too long, try to extract a shorter phrase
            if cleaned.count > 40 {
                // Try to get first phrase before comma, period, or "who"
                let separators = [",", ".", " who ", " that ", " is ", " - "]
                for sep in separators {
                    if let range = cleaned.lowercased().range(of: sep) {
                        let shortened = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if shortened.count >= 5 && shortened.count <= 40 {
                            cleaned = shortened
                            break
                        }
                    }
                }
            }
            
            // Capitalize first letter
            if !cleaned.isEmpty {
                cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
            }
            
            // Validate length - should be reasonable
            if cleaned.count >= 3 && cleaned.count <= 45 {
                Logger.shared.info("LLM generated style: \(cleaned)", category: .llm)
                return cleaned
            } else {
                Logger.shared.warning("LLM output too short/long (\(cleaned.count) chars): '\(cleaned)'", category: .llm)
                return "..."  // Will retry next time
            }
        } catch {
            Logger.shared.error("LLM inference failed: \(error.localizedDescription)", category: .llm)
            return "..."  // Will retry next time
        }
    }
    
    // MARK: - Emoji Generators
    
    private func pickRandom(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }


    // MARK: - Cache Management
    
    func clearAllCaches() {
        Logger.shared.info("Clear all caches", category: .llm)
        stockSearchCache.removeAll()
        stocksTabCache.removeAll()
        portfolioCache.removeAll()
        leaderboardCache.removeAll()
        saveCachesToDisk()
        objectWillChange.send()
    }
    
    func invalidatePriceCaches() {
        Logger.shared.info("Invalidate price caches", category: .llm)
        stocksTabCache.removeAll()
        portfolioCache.removeAll()
        leaderboardCache.removeAll()
        saveCachesToDisk()
        objectWillChange.send()
    }
    
    // MARK: - Persistence
    
    private var cacheFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("emoji_cache.json")
    }
    
    private func saveCachesToDisk() {
        let data: [String: [String: String]] = [
            "stockSearch": stockSearchCache,
            "stocksTab": stocksTabCache,
            "portfolio": portfolioCache,
            "leaderboard": leaderboardCache
        ]
        do {
            try JSONEncoder().encode(data).write(to: cacheFileURL)
        } catch {
            Logger.shared.error("Cache save: \(error.localizedDescription.prefix(30))", category: .llm)
        }
    }
    
    private func loadCachesFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let caches = try JSONDecoder().decode([String: [String: String]].self, from: data)
            stockSearchCache = caches["stockSearch"] ?? [:]
            stocksTabCache = caches["stocksTab"] ?? [:]
            portfolioCache = caches["portfolio"] ?? [:]
            leaderboardCache = caches["leaderboard"] ?? [:]
        } catch {
            Logger.shared.error("Cache load: \(error.localizedDescription.prefix(30))", category: .llm)
        }
    }
}

// MARK: - Errors

enum LLMError: Error, LocalizedError {
    case downloadFailed(String)
    case modelNotLoaded
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .modelNotLoaded: return "Model not loaded"
        case .inferenceError(let msg): return "Inference error: \(msg)"
        }
    }
}
