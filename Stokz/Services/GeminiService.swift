import Foundation

/// GeminiService - Generates witty investment style taglines using Google's Gemini API
/// Free tier: 60 requests/min, 1500 requests/day
class GeminiService: ObservableObject {
    static let shared = GeminiService()
    
    // MARK: - Configuration
    // Set your API key in Secrets.swift (gitignored) or as environment variable
    private var apiKey: String {
        // Try Secrets file first, then environment variable
        #if DEBUG
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        #endif
        // Fallback to Secrets.swift (create this file locally, it's gitignored)
        return Secrets.geminiAPIKey
    }
    
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    
    // Cache to avoid repeated API calls
    private var styleCache: [String: String] = [:] // portfolioHash -> style
    
    // Rate limiting
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0 // 1 second between requests
    
    @Published var isLoading = false
    @Published var lastError: String?
    
    private init() {}
    
    // MARK: - Generate Investment Style
    
    /// Generate a witty investment style tagline for a portfolio
    func getInvestmentStyle(holdings: [String]) async -> String? {
        guard !holdings.isEmpty else { return nil }
        guard !apiKey.isEmpty && apiKey != "YOUR_API_KEY_HERE" else {
            print("⚠️ [Gemini] API key not configured")
            return nil
        }
        
        // Check cache
        let cacheKey = holdings.sorted().joined(separator: ",")
        if let cached = styleCache[cacheKey] {
            print("✅ [Gemini] Cache hit for \(holdings.count) holdings")
            return cached
        }
        
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        
        // Rate limiting - wait if we called too recently
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                let waitTime = minRequestInterval - elapsed
                print("🤖 [Gemini] Rate limiting - waiting \(String(format: "%.1f", waitTime))s")
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
        
        let prompt = buildPrompt(holdings: holdings)
        
        do {
            let style = try await callGeminiAPI(prompt: prompt)
            
            // Cache the result
            styleCache[cacheKey] = style
            print("✅ [Gemini] Generated style: \"\(style)\" for \(holdings.count) holdings")
            
            return style
        } catch {
            print("❌ [Gemini] Error: \(error.localizedDescription)")
            await MainActor.run { lastError = error.localizedDescription }
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(holdings: [String]) -> String {
        """
        Generate a witty, sarcastic 4-6 word investment style tagline for this portfolio:

        Holdings: \(holdings.joined(separator: ", "))

        Rules:
        - Be funny and slightly roast-y
        - Reference specific stocks or sectors when possible
        - No emojis
        - Examples of good taglines:
          - "Tech bro with commitment issues"
          - "Betting the farm on chips"
          - "EV dreams, boomer backup plan"
          - "Diversified chaos coordinator"

        Just output the tagline, nothing else.
        """
    }
    
    private func callGeminiAPI(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.9,
                "maxOutputTokens": 50
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 [Gemini] Calling API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ [Gemini] HTTP \(httpResponse.statusCode): \(errorBody)")
            throw GeminiError.httpError(httpResponse.statusCode, errorBody)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError
        }
        
        // Clean up the response
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        
        return cleaned
    }
    
    /// Clear the cache (useful when portfolios change significantly)
    func clearCache() {
        styleCache.removeAll()
        print("🗑️ [Gemini] Cache cleared")
    }
    
    // MARK: - General Chat
    
    /// General purpose chat with Gemini - returns raw text response
    func chat(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty && apiKey != "YOUR_API_KEY_HERE" else {
            throw GeminiError.invalidResponse
        }
        
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "\(system)\n\n\(user)"]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 4096
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError
        }
        
        return text
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .parseError:
            return "Failed to parse Gemini response"
        }
    }
}
