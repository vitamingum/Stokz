import Foundation
import SwiftUI

/// Local LLM Service - Emoji generation with persistent caching
/// Shows skull placeholder until emoji is ready
@MainActor
class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()
    
    // MARK: - Model Config (for future LLM integration)
    private let modelURL = URL(string: "https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_k_m.gguf")!
    private let modelFileName = "qwen2-0.5b-instruct-q4_k_m.gguf"
    private let modelSize: Int64 = 397_000_000
    
    // MARK: - State
    @Published var isModelDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var lastError: String?
    
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
        Logger.shared.info("Cache: s\(stockSearchCache.count) t\(stocksTabCache.count) p\(portfolioCache.count) l\(leaderboardCache.count)", category: .llm)
    }
    
    // MARK: - Model Management
    
    func checkModelExists() {
        isModelDownloaded = FileManager.default.fileExists(atPath: modelPath.path)
        Logger.shared.debug("Model: \(isModelDownloaded ? "ready" : "none")", category: .llm)
    }
    
    func downloadModel() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        lastError = nil
        
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
            Logger.shared.success("Download complete", category: .llm)
        } catch {
            lastError = error.localizedDescription
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
    }
    
    var modelSizeString: String {
        ByteCountFormatter.string(fromByteCount: modelSize, countStyle: .file)
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
    
    // MARK: - Stocks Tab Emoji
    
    func getStocksTabEmoji(symbol: String, priceChangePercent: Double, holderCount: Int) -> String {
        let priceHash = Int(priceChangePercent * 10)
        let key = "\(symbol)_\(priceHash)_\(holderCount)"
        
        if let cached = stocksTabCache[key] { return cached }
        
        if !pendingGenerations.contains("t_\(key)") {
            pendingGenerations.insert("t_\(key)")
            Task {
                let emoji = generateTabEmoji(symbol: symbol, change: priceChangePercent, holders: holderCount)
                stocksTabCache[key] = emoji
                pendingGenerations.remove("t_\(key)")
                saveCachesToDisk()
                objectWillChange.send()
                Logger.shared.debug("\(emoji) \(symbol) tab", category: .llm)
            }
        }
        return Self.placeholder
    }
    
    private func generateTabEmoji(symbol: String, change: Double, holders: Int) -> String {
        let hash = abs("\(symbol)\(holders)".hashValue)
        
        // rocket, fire, boom, lightning, moon
        if change > 10 { return ["\u{1F680}", "\u{1F525}", "\u{1F4A5}", "\u{26A1}", "\u{1F319}"][hash % 5] }
        // skull, chart down, scream, skull crossbones, red triangle
        if change < -10 { return ["\u{1F480}", "\u{1F4C9}", "\u{1F631}", "\u{2620}", "\u{1F53B}"][hash % 5] }
        // chart up, green heart, check, up, green circle
        if change > 3 { return ["\u{1F4C8}", "\u{1F49A}", "\u{2705}", "\u{1F446}", "\u{1F7E2}"][hash % 5] }
        // chart down, red circle, down, anxious, money fly
        if change < -3 { return ["\u{1F4C9}", "\u{1F534}", "\u{1F447}", "\u{1F630}", "\u{1F4B8}"][hash % 5] }
        // fire, eyes, gem, gorilla, star
        if holders >= 3 { return ["\u{1F525}", "\u{1F440}", "\u{1F48E}", "\u{1F98D}", "\u{2B50}"][hash % 5] }
        // bar chart, arrow right, neutral, refresh, zzz
        return ["\u{1F4CA}", "\u{27A1}", "\u{1F610}", "\u{1F504}", "\u{1F4A4}"][hash % 5]
    }
    
    // MARK: - Portfolio Emoji (with deduplication)
    
    /// Call this at the start of rendering portfolio to reset used emojis
    func resetPortfolioEmojis() {
        usedPortfolioEmojis.removeAll()
    }
    
    func getPortfolioEmoji(symbol: String, dayChangePercent: Double) -> String {
        // Only show emoji when something WSB-worthy happens, otherwise blank
        let emoji = generatePortfolioEmoji(symbol: symbol, dayChange: dayChangePercent)
        if !emoji.isEmpty {
            usedPortfolioEmojis.insert(emoji)
        }
        return emoji
    }
    
    private func generatePortfolioEmoji(symbol: String, dayChange: Double) -> String {
        let hash = abs(symbol.hashValue)
        
        // WSB-style: Only show emojis when noteworthy moves happen!
        // Otherwise return empty string for clean look
        
        let pool: [String]
        
        if dayChange >= 10 {
            // TO THE MOON - massive day (+10%+)
            pool = ["🚀", "💎", "🦍", "🌙", "🍗", "🤑", "👑", "🐂"]
        } else if dayChange >= 5 {
            // Diamond hands paying off (+5-10%)
            pool = ["💪", "🔥", "📈", "💰", "🎰", "🦧"]
        } else if dayChange <= -10 {
            // LOSS PORN - GUH moment (-10%+)
            pool = ["💀", "☠️", "🤡", "🗑️", "⚰️", "😵", "🪦"]
        } else if dayChange <= -5 {
            // Behind Wendy's territory (-5-10%)
            pool = ["📉", "🐻", "💸", "😰", "🥶", "😬"]
        } else {
            // Boring day - no emoji needed
            return ""
        }
        
        // Find first emoji not already used this render
        for i in 0..<pool.count {
            let idx = (hash + i) % pool.count
            let emoji = pool[idx]
            if !usedPortfolioEmojis.contains(emoji) {
                return emoji
            }
        }
        
        // All used? Still return one (duplicates better than nothing for big moves)
        return pool[hash % pool.count]
    }
    
    // MARK: - Leaderboard Emoji (with deduplication)
    
    /// Call this at the start of rendering leaderboard to reset used emojis
    func resetLeaderboardEmojis() {
        usedLeaderboardEmojis.removeAll()
    }
    
    func getLeaderboardEmoji(userId: String, rank: Int, totalPlayers: Int, profitLossPercent: Double) -> String {
        // WSB emoji based purely on rank position - instant
        return generateLeaderboardEmoji(rank: rank, total: totalPlayers)
    }
    
    private func generateLeaderboardEmoji(rank: Int, total: Int) -> String {
        // WSB-style ranking: 💎 diamond hands at top, 🤡 clown at bottom
        
        let wsbScale: [String] = [
            "💎",  // 1st - Diamond hands
            "🦍",  // 2nd - Ape
            "🚀",  // 3rd - Rocket
            "🐂",  // 4th - Bull
            "💪",  // 5th - Gains
            "📈",  // 6th - Up
            "👍",  // 7th - Good
            "😐",  // 8th - Flat
            "📉",  // 9th - Down
            "🐻",  // 10th - Bear
            "💸",  // 11th - Money gone
            "😰",  // 12th - Sweating
            "☠️",  // 13th - Dead
            "💀",  // 14th - Skull
            "🤡"   // Last - Clown
        ]
        
        guard total > 0 else { return "🤷" }
        
        let scaleSize = wsbScale.count
        let normalizedPosition: Int
        
        if total == 1 {
            normalizedPosition = 0
        } else {
            let ratio = Double(rank - 1) / Double(total - 1)
            normalizedPosition = min(Int(ratio * Double(scaleSize - 1)), scaleSize - 1)
        }
        
        return wsbScale[normalizedPosition]
    }
    
    // MARK: - Cash Emoji (Portfolio View)
    
    func getCashEmoji(cashBalance: Double, totalValue: Double) -> String {
        return "💵"  // Hard-coded cash emoji
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
