import Foundation
import SwiftUI
import OSLog

/// On-device LLM service for generating fun emojis based on portfolio sentiment
/// Uses OpenAI API for now (can swap to local llama.cpp later)
@MainActor
class EmojiLLMService: ObservableObject {
    static let shared = EmojiLLMService()
    
    private let log = OSLog(subsystem: "com.stokz.app", category: "EmojiLLM")
    
    // Cache generated emojis to avoid repeated calls
    @Published var emojiCache: [String: String] = [:] // userId -> emoji
    @Published var isGenerating: [String: Bool] = [:] // userId -> isLoading
    
    // Generation queue to prevent hammering the API
    private var pendingRequests: Set<String> = []
    private let maxConcurrentRequests = 2
    private var activeRequests = 0
    
    private init() {}
    
    // MARK: - Public API
    
    /// Generate an emoji for a leaderboard entry
    func generateEmoji(for entry: LeaderboardEntry, totalPlayers: Int) async -> String {
        let cacheKey = "\(entry.user.id)_\(Int(entry.profitLossPercent))"
        
        // Return cached if available
        if let cached = emojiCache[cacheKey] {
            return cached
        }
        
        // Check if already generating
        if isGenerating[entry.user.id] == true {
            return "🔮" // Placeholder while generating
        }
        
        // Rate limit
        if activeRequests >= maxConcurrentRequests {
            return getDefaultEmoji(for: entry, totalPlayers: totalPlayers)
        }
        
        isGenerating[entry.user.id] = true
        activeRequests += 1
        
        defer {
            isGenerating[entry.user.id] = false
            activeRequests -= 1
        }
        
        let prompt = buildPrompt(for: entry, totalPlayers: totalPlayers)
        
        do {
            let emoji = try await callLLM(prompt: prompt)
            emojiCache[cacheKey] = emoji
            os_log("Generated emoji for %{public}@: %{public}@", log: log, type: .info, entry.user.displayName, emoji)
            return emoji
        } catch {
            os_log("Failed to generate emoji: %{public}@", log: log, type: .error, error.localizedDescription)
            let fallback = getDefaultEmoji(for: entry, totalPlayers: totalPlayers)
            emojiCache[cacheKey] = fallback
            return fallback
        }
    }
    
    /// Generate emojis for stock price action
    func generateStockEmoji(symbol: String, priceChangePercent: Double) async -> String {
        let cacheKey = "stock_\(symbol)_\(Int(priceChangePercent))"
        
        if let cached = emojiCache[cacheKey] {
            return cached
        }
        
        let sentiment: String
        if priceChangePercent > 10 {
            sentiment = "extremely bullish, massive gains, to the moon"
        } else if priceChangePercent > 5 {
            sentiment = "very bullish, strong gains"
        } else if priceChangePercent > 2 {
            sentiment = "moderately bullish, steady climb"
        } else if priceChangePercent > 0 {
            sentiment = "slightly positive, small gains"
        } else if priceChangePercent > -2 {
            sentiment = "slightly negative, small dip"
        } else if priceChangePercent > -5 {
            sentiment = "bearish, notable decline"
        } else if priceChangePercent > -10 {
            sentiment = "very bearish, significant losses"
        } else {
            sentiment = "catastrophic dump, bloodbath"
        }
        
        let prompt = """
        Generate exactly ONE emoji that captures this stock sentiment: \(symbol) is \(sentiment) (\(String(format: "%.1f", priceChangePercent))% change).
        Be creative and fun. Reply with ONLY the emoji, nothing else.
        """
        
        do {
            let emoji = try await callLLM(prompt: prompt)
            emojiCache[cacheKey] = emoji
            return emoji
        } catch {
            return priceChangePercent >= 0 ? "📈" : "📉"
        }
    }
    
    // MARK: - Private
    
    private func buildPrompt(for entry: LeaderboardEntry, totalPlayers: Int) -> String {
        var context: [String] = []
        
        // Position context
        if entry.rank == 1 {
            context.append("IN FIRST PLACE, WINNING")
        } else if entry.rank == totalPlayers {
            context.append("IN LAST PLACE, LOSING TO EVERYONE")
        } else if entry.rank <= 3 {
            context.append("on the podium, top 3")
        } else if entry.rank <= totalPlayers / 2 {
            context.append("in the upper half of rankings")
        } else {
            context.append("in the bottom half, struggling")
        }
        
        // Performance context
        let pnl = entry.profitLossPercent
        if pnl > 20 {
            context.append("CRUSHING IT with \(String(format: "%.1f", pnl))% gains")
        } else if pnl > 10 {
            context.append("doing great with \(String(format: "%.1f", pnl))% gains")
        } else if pnl > 5 {
            context.append("solid performance, up \(String(format: "%.1f", pnl))%")
        } else if pnl > 0 {
            context.append("slightly positive at +\(String(format: "%.1f", pnl))%")
        } else if pnl > -5 {
            context.append("slightly down at \(String(format: "%.1f", pnl))%")
        } else if pnl > -10 {
            context.append("having a rough time, down \(String(format: "%.1f", abs(pnl)))%")
        } else if pnl > -20 {
            context.append("getting destroyed, down \(String(format: "%.1f", abs(pnl)))%")
        } else {
            context.append("COMPLETE DISASTER, down \(String(format: "%.1f", abs(pnl)))%")
        }
        
        return """
        Generate exactly ONE creative emoji reaction for this stock trading game player:
        \(context.joined(separator: ", "))
        
        Be playful and expressive! Use emoji that captures the emotion/situation.
        Good examples: 🔥 👑 💀 😤 🥶 🤑 😭 🚀 📉 🎰 💎 🧊 😎 🤡 ⚰️
        Reply with ONLY the emoji, no text. Just one emoji.
        """
    }
    
    private func callLLM(prompt: String) async throws -> String {
        // Use OpenAI API - tiny request, fast response
        // Can swap to local llama.cpp model later
        
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? 
              UserDefaults.standard.string(forKey: "openai_api_key") else {
            throw LLMError.noAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini", // Cheapest and fastest
            "messages": [
                ["role": "system", "content": "You are an emoji generator. Reply with exactly ONE emoji that captures the sentiment. No text, no explanation, just the emoji."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 10,
            "temperature": 0.9 // Higher for creativity
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.apiError(statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }
        
        // Extract just the emoji (first emoji character)
        let emoji = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate it's actually an emoji
        if emoji.unicodeScalars.first?.properties.isEmoji == true {
            return String(emoji.prefix(2)) // Handle compound emojis
        }
        
        throw LLMError.invalidResponse
    }
    
    private func getDefaultEmoji(for entry: LeaderboardEntry, totalPlayers: Int) -> String {
        // Fallback emojis based on simple rules
        if entry.rank == 1 { return "👑" }
        if entry.rank == totalPlayers { return "💀" }
        if entry.rank <= 3 { return "🏆" }
        
        let pnl = entry.profitLossPercent
        if pnl > 20 { return "🔥" }
        if pnl > 10 { return "🚀" }
        if pnl > 5 { return "📈" }
        if pnl > 0 { return "😎" }
        if pnl > -5 { return "😐" }
        if pnl > -10 { return "😰" }
        if pnl > -20 { return "📉" }
        return "💀"
    }
    
    // MARK: - Clear Cache
    func clearCache() {
        emojiCache.removeAll()
    }
}

// MARK: - Errors
enum LLMError: Error, LocalizedError {
    case noAPIKey
    case apiError(Int)
    case parseError
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenAI API key configured"
        case .apiError(let code): return "API error: \(code)"
        case .parseError: return "Failed to parse response"
        case .invalidResponse: return "Invalid response from LLM"
        }
    }
}
