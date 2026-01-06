// EmojiPrompts.swift
// Editable prompt templates for AI emoji generation
// Edit these directly to tune emoji outputs!

import Foundation

/// Prompt templates for emoji generation
/// Each returns a prompt string that should generate exactly ONE emoji
struct EmojiPrompts {
    
    // MARK: - Stock Search (Adding new stocks)
    
    /// Emoji for a stock in the search/add list
    /// Context: symbol, company name
    static func stockSearch(symbol: String, companyName: String) -> String {
        """
        Stock ticker: \(symbol)
        Company: \(companyName)
        
        Generate ONE emoji that represents this company's industry, brand, or vibe.
        Examples: 🍎 Apple, 🚗 Tesla, 💻 Microsoft, ☕️ Starbucks, 🎮 Nvidia, 🛒 Amazon
        
        Reply with just the emoji:
        """
    }
    
    // MARK: - Stocks Tab (All stocks being held)
    
    /// Emoji for a stock on the main stocks list
    /// Context: symbol, price change, number of holders
    static func stocksTab(symbol: String, priceChangePercent: Double, holderCount: Int) -> String {
        let sentiment = priceSentiment(priceChangePercent)
        let popularity = holderCount > 3 ? "very popular" : holderCount > 1 ? "moderately held" : "single holder"
        
        return """
        Stock: \(symbol)
        Today: \(sentiment) (\(String(format: "%+.1f", priceChangePercent))%)
        Popularity: \(popularity) (\(holderCount) players holding)
        
        Generate ONE emoji capturing the stock's current vibe.
        Consider: price momentum, holder interest, market sentiment
        
        Reply with just the emoji:
        """
    }
    
    // MARK: - Portfolio View (User's holdings)
    
    /// Emoji for a stock in the user's portfolio
    /// Context: symbol, P&L, allocation size
    static func portfolio(symbol: String, profitLossPercent: Double, allocationPercent: Double) -> String {
        let plSentiment = priceSentiment(profitLossPercent)
        let size = allocationPercent > 30 ? "major position" : allocationPercent > 15 ? "moderate position" : "small position"
        
        return """
        Portfolio holding: \(symbol)
        P&L: \(plSentiment) (\(String(format: "%+.1f", profitLossPercent))%)
        Size: \(size) (\(String(format: "%.0f", allocationPercent))% of portfolio)
        
        Generate ONE emoji for how this position is doing.
        Winners get celebration, losers get pain, big positions get attention.
        
        Reply with just the emoji:
        """
    }
    
    // MARK: - Leaderboard (Player rankings)
    
    /// Emoji for a player on the leaderboard
    /// Context: rank, total players, P&L percent
    static func leaderboard(rank: Int, totalPlayers: Int, profitLossPercent: Double, displayName: String) -> String {
        let position: String
        if rank == 1 {
            position = "🏆 IN FIRST PLACE - WINNING"
        } else if rank == totalPlayers {
            position = "💀 DEAD LAST - LOSING TO EVERYONE"  
        } else if rank <= 3 {
            position = "🥈 On the podium (top 3)"
        } else if rank <= totalPlayers / 2 {
            position = "Upper half of rankings"
        } else {
            position = "Bottom half, struggling"
        }
        
        let performance = priceSentiment(profitLossPercent)
        
        return """
        Player: \(displayName)
        Rank: #\(rank) of \(totalPlayers) - \(position)
        Performance: \(performance) (\(String(format: "%+.1f", profitLossPercent))%)
        
        Generate ONE emoji capturing their situation in the game.
        Winners get glory, losers get roasted, middle gets meh.
        Be expressive! 🔥👑💀🚀😤🥶🤑😭📉🎰💎🧊😎🤡⚰️
        
        Reply with just the emoji:
        """
    }
    
    // MARK: - Helpers
    
    private static func priceSentiment(_ percent: Double) -> String {
        switch percent {
        case 50...: return "INSANE GAINS 🚀"
        case 20..<50: return "crushing it"
        case 10..<20: return "doing great"
        case 5..<10: return "solid gains"
        case 0..<5: return "slightly up"
        case -5..<0: return "slightly down"
        case -10..<(-5): return "losing money"
        case -20..<(-10): return "getting hurt"
        case -50..<(-20): return "bleeding out"
        default: return percent < -50 ? "CATASTROPHIC LOSS 💀" : "neutral"
        }
    }
}
