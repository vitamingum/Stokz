import Foundation
import SwiftUI

/// AIContext provides rich context about the game state for LLM prompts
/// 📊 Builds summaries of portfolios, rankings, performance for AI features
@MainActor
class AIContext: ObservableObject {
    static let shared = AIContext()
    
    private init() {}
    
    // MARK: - Leaderboard Context
    
    /// Generate a concise summary of a player's standing
    /// Returns emoji-rich context string for the LLM
    func playerSummary(entry: LeaderboardEntry, totalPlayers: Int) -> String {
        var parts: [String] = []
        
        // Position emoji and context
        switch entry.rank {
        case 1:
            parts.append("👑 #1 WINNER")
        case 2:
            parts.append("🥈 #2")
        case 3:
            parts.append("🥉 #3")
        case totalPlayers:
            parts.append("💀 LAST PLACE (#\(entry.rank)/\(totalPlayers))")
        default:
            let percentile = Int((1.0 - Double(entry.rank) / Double(totalPlayers)) * 100)
            if percentile >= 75 {
                parts.append("📈 #\(entry.rank) (top \(100-percentile)%)")
            } else if percentile >= 50 {
                parts.append("😐 #\(entry.rank) (mid)")
            } else {
                parts.append("📉 #\(entry.rank) (bottom \(100-percentile)%)")
            }
        }
        
        // P&L context
        let pnl = entry.profitLossPercent
        if pnl > 50 { parts.append("🚀 +\(Int(pnl))% INSANE") }
        else if pnl > 20 { parts.append("🔥 +\(Int(pnl))% crushing") }
        else if pnl > 10 { parts.append("💪 +\(Int(pnl))% strong") }
        else if pnl > 5 { parts.append("✅ +\(Int(pnl))%") }
        else if pnl > 0 { parts.append("📊 +\(String(format: "%.1f", pnl))%") }
        else if pnl > -5 { parts.append("😬 \(String(format: "%.1f", pnl))%") }
        else if pnl > -10 { parts.append("😰 \(Int(pnl))%") }
        else if pnl > -20 { parts.append("💸 \(Int(pnl))% ouch") }
        else if pnl > -50 { parts.append("🩸 \(Int(pnl))% bleeding") }
        else { parts.append("☠️ \(Int(pnl))% REKT") }
        
        // Net worth
        parts.append("💰 \(entry.netWorth.asCompactCurrency)")
        
        return parts.joined(separator: " | ")
    }
    
    /// Generate a prompt for the LLM to generate an emoji
    func emojiPrompt(entry: LeaderboardEntry, totalPlayers: Int) -> String {
        let context = playerSummary(entry: entry, totalPlayers: totalPlayers)
        
        return """
        Stock trading game player status: \(context)
        
        Generate ONE emoji that captures their situation. Be creative and match the vibe.
        Examples: 🔥👑💀🚀😤🥶🤑😭📉🎰💎🧊😎🤡⚰️🏆😱🦍💩🌙
        
        Reply with just the emoji:
        """
    }
    
    // MARK: - Stock Context
    
    /// Generate context for a stock's price action
    func stockSummary(symbol: String, priceChange: Double, priceChangePercent: Double) -> String {
        var parts: [String] = [symbol]
        
        if priceChangePercent > 10 { parts.append("🚀 +\(String(format: "%.1f", priceChangePercent))%") }
        else if priceChangePercent > 5 { parts.append("📈 +\(String(format: "%.1f", priceChangePercent))%") }
        else if priceChangePercent > 2 { parts.append("✅ +\(String(format: "%.1f", priceChangePercent))%") }
        else if priceChangePercent > 0 { parts.append("⬆️ +\(String(format: "%.1f", priceChangePercent))%") }
        else if priceChangePercent > -2 { parts.append("⬇️ \(String(format: "%.1f", priceChangePercent))%") }
        else if priceChangePercent > -5 { parts.append("📉 \(String(format: "%.1f", priceChangePercent))%") }
        else if priceChangePercent > -10 { parts.append("🔻 \(String(format: "%.1f", priceChangePercent))%") }
        else { parts.append("💥 \(String(format: "%.1f", priceChangePercent))%") }
        
        return parts.joined(separator: " ")
    }
    
    // MARK: - Full Game Summary
    
    /// Generate a complete game state summary
    func gameSummary(leaderboard: [LeaderboardEntry], currentUserId: String?) -> String {
        guard !leaderboard.isEmpty else {
            return "📊 No players yet"
        }
        
        var lines: [String] = ["📊 STOKZ LEADERBOARD"]
        
        // Top 3
        for (i, entry) in leaderboard.prefix(3).enumerated() {
            let medal = ["👑", "🥈", "🥉"][i]
            let isYou = entry.user.id == currentUserId ? " (YOU)" : ""
            lines.append("\(medal) \(entry.user.displayName)\(isYou): \(entry.netWorth.asCompactCurrency) (\(entry.isPositive ? "+" : "")\(String(format: "%.1f", entry.profitLossPercent))%)")
        }
        
        // Current user if not in top 3
        if let userId = currentUserId,
           let userEntry = leaderboard.first(where: { $0.user.id == userId }),
           userEntry.rank > 3 {
            lines.append("...")
            lines.append("#\(userEntry.rank) \(userEntry.user.displayName) (YOU): \(userEntry.netWorth.asCompactCurrency) (\(userEntry.isPositive ? "+" : "")\(String(format: "%.1f", userEntry.profitLossPercent))%)")
        }
        
        // Last place (if different from current user and not in top 3)
        if let last = leaderboard.last,
           last.rank > 3,
           last.user.id != currentUserId {
            lines.append("💀 #\(last.rank) \(last.user.displayName): \(last.netWorth.asCompactCurrency)")
        }
        
        return lines.joined(separator: "\n")
    }
}
