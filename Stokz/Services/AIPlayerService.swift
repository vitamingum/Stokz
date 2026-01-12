import Foundation

/// AIPlayerService handles trading decisions for AI-controlled players
/// Each AI player has a thesis and an LLM provider that makes investment decisions
@MainActor
class AIPlayerService: ObservableObject {
    static let shared = AIPlayerService()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let stockDataService = StockDataService.shared
    
    private init() {}
    
    // MARK: - Trading Decision
    
    /// AI trading decision result
    struct TradeDecision: Codable {
        let action: TradeAction
        let symbol: String?
        let reasoning: String
        
        enum TradeAction: String, Codable {
            case buy
            case sell
            case hold
        }
    }
    
    /// Get a trading decision for an AI player based on their thesis
    /// - Parameters:
    ///   - aiPlayer: The AI user with thesis and provider
    ///   - portfolio: Current portfolio holdings
    ///   - prices: Current market prices
    /// - Returns: Trading decision with reasoning
    func getTradeDecision(
        for aiPlayer: User,
        portfolio: Portfolio,
        prices: [String: Double]
    ) async throws -> TradeDecision {
        guard aiPlayer.isAI, let thesis = aiPlayer.aiThesis else {
            throw AIPlayerError.notAnAIPlayer
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Build context about current portfolio
        let portfolioContext = buildPortfolioContext(portfolio: portfolio, prices: prices)
        
        // Get market opportunities (stocks not in portfolio)
        let opportunities = getMarketOpportunities(excluding: portfolio.holdings.map { $0.symbol })
        
        // Build the prompt
        let systemPrompt = """
        You are an AI investment manager. You make trading decisions based on your investment thesis.
        
        YOUR INVESTMENT THESIS:
        \(thesis)
        
        RULES:
        - You can BUY a new stock, SELL an existing holding, or HOLD (do nothing)
        - When buying, choose from the available opportunities list
        - When selling, choose from your current holdings
        - Base ALL decisions on your thesis
        - Be decisive - if something fits your thesis, act on it
        
        Respond with ONLY a JSON object in this exact format:
        {"action": "buy|sell|hold", "symbol": "TICKER or null", "reasoning": "brief explanation"}
        """
        
        let userPrompt = """
        CURRENT PORTFOLIO:
        \(portfolioContext)
        
        AVAILABLE TO BUY (sample of \(opportunities.count) stocks):
        \(opportunities.prefix(20).map { "\($0.ticker): \($0.fact.company) - \($0.fact.sector) - \($0.fact.summary.prefix(100))..." }.joined(separator: "\n"))
        
        Based on your thesis, what is your trading decision?
        """
        
        // Make the API call using the AI player's provider
        let response = try await makeAIRequest(
            provider: aiPlayer.llmProvider ?? .gemini,
            system: systemPrompt,
            user: userPrompt
        )
        
        // Parse the response
        return try parseTradeDecision(response)
    }
    
    // MARK: - Create AI Player
    
    /// Create a new AI player with given thesis and provider
    /// - Parameters:
    ///   - name: Display name for the AI player
    ///   - thesis: Investment thesis (must be at least 20 characters)
    ///   - provider: LLM provider to use for trading decisions
    /// - Returns: The created User object representing the AI player
    func createAIPlayer(
        name: String,
        thesis: String,
        provider: LLMProvider
    ) async throws -> User {
        guard !name.isEmpty else {
            throw AIPlayerError.invalidInput("Name cannot be empty")
        }
        guard thesis.count >= 20 else {
            throw AIPlayerError.invalidInput("Thesis must be at least 20 characters")
        }
        
        // Create AI user with unique ID
        let aiPlayer = User(
            id: "ai_\(UUID().uuidString.prefix(8).lowercased())",
            email: "\(name.lowercased().replacingOccurrences(of: " ", with: "_"))@ai.stokz.app",
            displayName: name,
            photoURL: nil,
            createdAt: Date(),
            isAI: true,
            aiThesis: thesis,
            aiProvider: provider.rawValue,
            ownerId: AppState.shared.authService.currentUser?.id
        )
        
        // Save to Google Sheets
        try await AppState.shared.sheetsService.saveUser(aiPlayer)
        
        // Create initial portfolio with starting cash
        let portfolio = Portfolio(
            id: UUID().uuidString,
            userId: aiPlayer.id,
            holdings: [],
            cashBalance: 100_000 // $100k starting balance
        )
        try await AppState.shared.sheetsService.savePortfolio(portfolio)
        
        return aiPlayer
    }
    
    /// Get multiple stock recommendations for initial portfolio build
    /// Uses TALL BOY screener with map-reduce pattern for quality picks
    func getInitialPortfolio(
        for aiPlayer: User,
        budget: Double = 100_000,
        maxStocks: Int = 10
    ) async throws -> [String] {
        guard aiPlayer.isAI, let thesis = aiPlayer.aiThesis else {
            throw AIPlayerError.notAnAIPlayer
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        print("🤖 [AIPlayer] Building portfolio for \(aiPlayer.displayName) using TALL BOY screener...")
        
        // Use TALL BOY screener to find stocks matching the AI's thesis
        let picks = try await StockScreenerService.shared.screenForBot(thesis: thesis, maxPicks: maxStocks)
        
        let tickers = picks.map { $0.ticker }
        print("🤖 [AIPlayer] TALL BOY found \(tickers.count) stocks: \(tickers.joined(separator: ", "))")
        
        return tickers
    }
    
    // MARK: - Helpers
    
    private func buildPortfolioContext(portfolio: Portfolio, prices: [String: Double]) -> String {
        if portfolio.holdings.isEmpty {
            return "Empty portfolio - $\(String(format: "%.0f", portfolio.cashBalance)) cash available"
        }
        
        var lines: [String] = []
        lines.append("Cash: $\(String(format: "%.0f", portfolio.cashBalance))")
        lines.append("Holdings:")
        
        for holding in portfolio.holdings {
            let price = prices[holding.symbol] ?? holding.entryPrice
            let value = holding.currentValue(at: price)
            let pnl = holding.profitLossPercent(at: price)
            let pnlStr = pnl >= 0 ? "+\(String(format: "%.1f", pnl))%" : "\(String(format: "%.1f", pnl))%"
            
            if let fact = stockDataService.getFact(ticker: holding.symbol) {
                lines.append("  \(holding.symbol): $\(String(format: "%.0f", value)) (\(pnlStr)) - \(fact.company), \(fact.sector)")
            } else {
                lines.append("  \(holding.symbol): $\(String(format: "%.0f", value)) (\(pnlStr))")
            }
        }
        
        let total = portfolio.totalValue(prices: prices)
        let totalPnl = portfolio.totalProfitLossPercent(prices: prices)
        lines.append("Total: $\(String(format: "%.0f", total)) (\(totalPnl >= 0 ? "+" : "")\(String(format: "%.1f", totalPnl))%)")
        
        return lines.joined(separator: "\n")
    }
    
    private func getMarketOpportunities(excluding ownedTickers: [String]) -> [(ticker: String, fact: StockFact)] {
        let owned = Set(ownedTickers)
        return stockDataService.allTickers
            .filter { !owned.contains($0) }
            .compactMap { ticker in
                guard let fact = stockDataService.getFact(ticker: ticker) else { return nil }
                return (ticker: ticker, fact: fact)
            }
            .shuffled() // Randomize to show variety
    }
    
    private func parseTradeDecision(_ response: String) throws -> TradeDecision {
        // Extract JSON from response (LLMs sometimes add extra text)
        let cleaned = extractJSON(from: response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw AIPlayerError.invalidResponse("Could not parse response")
        }
        
        do {
            return try JSONDecoder().decode(TradeDecision.self, from: data)
        } catch {
            // Try to parse manually if JSON decode fails
            if cleaned.lowercased().contains("\"hold\"") || cleaned.lowercased().contains("hold") {
                return TradeDecision(action: .hold, symbol: nil, reasoning: "AI chose to hold")
            }
            throw AIPlayerError.invalidResponse("Could not parse: \(cleaned)")
        }
    }
    
    private func parseTickerList(_ response: String) throws -> [String] {
        let cleaned = extractJSON(from: response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw AIPlayerError.invalidResponse("Could not parse response")
        }
        
        do {
            let tickers = try JSONDecoder().decode([String].self, from: data)
            // Validate tickers exist in our data
            return tickers.filter { stockDataService.getFact(ticker: $0) != nil }
        } catch {
            // Try to extract tickers with regex as fallback
            let pattern = #"[A-Z]{1,5}"#
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matches = regex?.matches(in: cleaned, range: range) ?? []
            
            let tickers = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: cleaned) else { return nil }
                return String(cleaned[range])
            }.filter { stockDataService.getFact(ticker: $0) != nil }
            
            if tickers.isEmpty {
                throw AIPlayerError.invalidResponse("No valid tickers found")
            }
            return Array(Set(tickers)).prefix(10).map { $0 }
        }
    }
    
    private func extractJSON(from text: String) -> String {
        // Find JSON object or array
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") {
            return String(text[start...end])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - API Calls (using specific provider)
    
    private func makeAIRequest(provider: LLMProvider, system: String, user: String) async throws -> String {
        // Get API key for this provider
        let key = UserDefaults.standard.string(forKey: "stokz_ai_key_\(provider.rawValue)") ?? ""
        
        guard !key.isEmpty else {
            throw AIPlayerError.noAPIKey(provider.displayName)
        }
        
        switch provider {
        case .gemini:
            return try await callGemini(key: key, system: system, user: user)
        case .openai:
            return try await callOpenAI(key: key, system: system, user: user)
        case .anthropic:
            return try await callAnthropic(key: key, system: system, user: user)
        case .grok:
            return try await callGrok(key: key, system: system, user: user)
        }
    }
    
    private func callGemini(key: String, system: String, user: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=\(key)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "\(system)\n\n\(user)"]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 500
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIPlayerError.networkError
        }
        
        if httpResponse.statusCode == 429 {
            throw AIPlayerError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIPlayerError.apiError(httpResponse.statusCode, errorBody)
        }
        
        // Parse Gemini response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        
        throw AIPlayerError.invalidResponse("Could not parse Gemini response")
    }
    
    private func callOpenAI(key: String, system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIPlayerError.networkError
        }
        
        if httpResponse.statusCode == 429 {
            throw AIPlayerError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIPlayerError.apiError(httpResponse.statusCode, errorBody)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        throw AIPlayerError.invalidResponse("Could not parse OpenAI response")
    }
    
    private func callAnthropic(key: String, system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "system": system,
            "messages": [["role": "user", "content": user]],
            "max_tokens": 500
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIPlayerError.networkError
        }
        
        if httpResponse.statusCode == 429 {
            throw AIPlayerError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIPlayerError.apiError(httpResponse.statusCode, errorBody)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }
        
        throw AIPlayerError.invalidResponse("Could not parse Anthropic response")
    }
    
    private func callGrok(key: String, system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "grok-beta",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIPlayerError.networkError
        }
        
        if httpResponse.statusCode == 429 {
            throw AIPlayerError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIPlayerError.apiError(httpResponse.statusCode, errorBody)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        throw AIPlayerError.invalidResponse("Could not parse Grok response")
    }
}

// MARK: - Errors

enum AIPlayerError: LocalizedError {
    case notAnAIPlayer
    case noAPIKey(String)
    case networkError
    case rateLimited
    case apiError(Int, String)
    case invalidResponse(String)
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .notAnAIPlayer:
            return "Not an AI player"
        case .noAPIKey(let provider):
            return "No API key configured for \(provider)"
        case .networkError:
            return "Network error"
        case .rateLimited:
            return "Rate limited - try again later"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        }
    }
}
