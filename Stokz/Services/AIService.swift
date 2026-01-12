import Foundation

// MARK: - LLM Provider Configuration

enum LLMProvider: String, CaseIterable, Codable {
    case gemini = "Gemini"
    case openai = "ChatGPT"
    case anthropic = "Claude"
    case grok = "Grok"
    
    var displayName: String { rawValue }
    
    var requiresAPIKey: Bool { true }
    
    var apiKeyPlaceholder: String {
        switch self {
        case .gemini: return "AIza..."
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .grok: return "xai-..."
        }
    }
    
    var helpURL: String {
        switch self {
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .openai: return "https://platform.openai.com/api-keys"
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .grok: return "https://console.x.ai/"
        }
    }
}

// MARK: - AI Service (Multi-Provider)

@MainActor
class AIService: ObservableObject {
    static let shared = AIService()
    
    // User settings stored in UserDefaults
    @Published var selectedProvider: LLMProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "ai_provider")
            // Auto-enable free tier when switching to Gemini
            if selectedProvider == .gemini {
                isFreeTier = true
            } else {
                isFreeTier = false
            }
            clearCache()
        }
    }
    
    @Published var apiKey: String {
        didSet {
            saveAPIKey(apiKey, for: selectedProvider)
            clearCache()
        }
    }
    
    @Published var isLoading = false
    @Published var lastError: String?
    
    // Free tier rate limiting (user can toggle off if they have paid)
    @Published var isFreeTier: Bool {
        didSet {
            UserDefaults.standard.set(isFreeTier, forKey: "ai_free_tier")
        }
    }
    
    // Cache for style taglines - persisted to UserDefaults
    private var styleCache: [String: String] = [:] {
        didSet {
            // Persist to UserDefaults (limit to 50 entries to avoid bloat)
            let limitedCache = Dictionary(uniqueKeysWithValues: styleCache.suffix(50))
            UserDefaults.standard.set(limitedCache, forKey: "ai_style_cache")
        }
    }
    
    // Track in-flight requests to avoid duplicates
    private var pendingStyleRequests: Set<String> = []
    
    // Rate limiting for free tier (15 RPM = 4 sec between requests)
    private var lastRequestTime: Date?
    private let freeTierMinRequestInterval: TimeInterval = 4.0
    
    private init() {
        // Load saved provider first
        let provider: LLMProvider
        if let savedProvider = UserDefaults.standard.string(forKey: "ai_provider"),
           let p = LLMProvider(rawValue: savedProvider) {
            provider = p
        } else {
            provider = .gemini
        }
        
        // Load free tier setting (default to true for Gemini)
        let savedFreeTier = UserDefaults.standard.object(forKey: "ai_free_tier") as? Bool
        self.isFreeTier = savedFreeTier ?? (provider == .gemini)
        
        // Load cached styles from UserDefaults
        if let cachedStyles = UserDefaults.standard.dictionary(forKey: "ai_style_cache") as? [String: String] {
            self.styleCache = cachedStyles
            print("✅ [AI] Loaded \(cachedStyles.count) cached styles")
        }
        
        // Initialize all stored properties before using self
        self.selectedProvider = provider
        self.apiKey = AIService.loadAPIKey(for: provider)
    }
    
    // MARK: - API Key Management
    
    private static func keychainKey(for provider: LLMProvider) -> String {
        "stokz_ai_key_\(provider.rawValue)"
    }
    
    private static func loadAPIKey(for provider: LLMProvider) -> String {
        // Try UserDefaults (simpler than Keychain for now)
        UserDefaults.standard.string(forKey: keychainKey(for: provider)) ?? ""
    }
    
    private func saveAPIKey(_ key: String, for provider: LLMProvider) {
        UserDefaults.standard.set(key, forKey: AIService.keychainKey(for: provider))
    }
    
    func loadKeyForCurrentProvider() {
        apiKey = AIService.loadAPIKey(for: selectedProvider)
    }
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    @Published var isKeyValid: Bool = true
    @Published var validationMessage: String?
    
    // MARK: - API Key Validation
    
    /// Validate the current API key by making a simple request
    func validateAPIKey() async -> Bool {
        guard isConfigured else { return false }
        
        do {
            // Make a minimal request to test the key
            let _ = try await chat(system: "Respond with OK", user: "Test")
            await MainActor.run {
                isKeyValid = true
                validationMessage = nil
            }
            print("✅ [AI] API key validated successfully")
            return true
        } catch {
            await MainActor.run {
                isKeyValid = false
                validationMessage = parseValidationError(error)
            }
            print("❌ [AI] API key validation failed: \(error)")
            return false
        }
    }
    
    /// Validate a specific key for a provider (used during setup)
    func validateKey(_ key: String, for provider: LLMProvider) async -> (valid: Bool, error: String?) {
        guard !key.isEmpty else {
            return (false, "API key is required")
        }
        
        // Temporarily set the key to test it
        let oldProvider = selectedProvider
        let oldKey = apiKey
        
        // Test without saving
        do {
            let testResult = try await testKey(key, for: provider)
            return (testResult, nil)
        } catch {
            return (false, parseValidationError(error))
        }
    }
    
    private func testKey(_ key: String, for provider: LLMProvider) async throws -> Bool {
        switch provider {
        case .gemini:
            return try await testGeminiKey(key)
        case .openai:
            return try await testOpenAIKey(key)
        case .anthropic:
            return try await testAnthropicKey(key)
        case .grok:
            return try await testGrokKey(key)
        }
    }
    
    private func testGeminiKey(_ key: String) async throws -> Bool {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=\(key)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": "Say OK"]]]],
            "generationConfig": ["maxOutputTokens": 10]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        
        if httpResponse.statusCode == 200 { return true }
        
        let errorBody = String(data: data, encoding: .utf8) ?? ""
        throw AIError.httpError(httpResponse.statusCode, errorBody)
    }
    
    private func testOpenAIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": "Say OK"]],
            "max_tokens": 10
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        
        if httpResponse.statusCode == 200 { return true }
        
        let errorBody = String(data: data, encoding: .utf8) ?? ""
        throw AIError.httpError(httpResponse.statusCode, errorBody)
    }
    
    private func testAnthropicKey(_ key: String) async throws -> Bool {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 10,
            "messages": [["role": "user", "content": "Say OK"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        
        if httpResponse.statusCode == 200 { return true }
        
        let errorBody = String(data: data, encoding: .utf8) ?? ""
        throw AIError.httpError(httpResponse.statusCode, errorBody)
    }
    
    private func testGrokKey(_ key: String) async throws -> Bool {
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "grok-beta",
            "messages": [["role": "user", "content": "Say OK"]],
            "max_tokens": 10
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        
        if httpResponse.statusCode == 200 { return true }
        
        let errorBody = String(data: data, encoding: .utf8) ?? ""
        throw AIError.httpError(httpResponse.statusCode, errorBody)
    }
    
    private func parseValidationError(_ error: Error) -> String {
        if let aiError = error as? AIError {
            switch aiError {
            case .httpError(let code, let body):
                if code == 400 && body.contains("API_KEY_INVALID") {
                    return "Invalid API key"
                } else if code == 401 {
                    return "Invalid API key"
                } else if code == 403 {
                    return "API key doesn't have permission"
                } else if code == 429 {
                    return "Rate limited - try again later"
                } else {
                    return "API error (\(code))"
                }
            default:
                return aiError.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    // MARK: - Chat API
    
    func chat(system: String, user: String) async throws -> String {
        guard isConfigured else {
            throw AIError.notConfigured
        }
        
        // Rate limit if on free tier (user can toggle off in Settings)
        if isFreeTier {
            if let lastTime = lastRequestTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed < freeTierMinRequestInterval {
                    try? await Task.sleep(nanoseconds: UInt64((freeTierMinRequestInterval - elapsed) * 1_000_000_000))
                }
            }
            lastRequestTime = Date()
        }
        
        // Retry with exponential backoff for rate limits
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await makeRequest(provider: selectedProvider, system: system, user: user)
            } catch let error as AIError {
                if case .httpError(let code, _) = error, code == 429 {
                    // Rate limited - wait and retry
                    let delay = Double(pow(2.0, Double(attempt))) * 2.0  // 2s, 4s, 8s
                    print("⚠️ [AI] Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/3)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = error
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        
        // All retries failed
        throw lastError ?? AIError.invalidResponse
    }
    
    private func makeRequest(provider: LLMProvider, system: String, user: String) async throws -> String {
        switch provider {
        case .gemini:
            return try await callGemini(system: system, user: user)
        case .openai:
            return try await callOpenAI(system: system, user: user)
        case .anthropic:
            return try await callAnthropic(system: system, user: user)
        case .grok:
            return try await callGrok(system: system, user: user)
        }
    }
    
    // MARK: - Investment Style Generator
    
    func getInvestmentStyle(holdings: [String]) async -> String? {
        guard !holdings.isEmpty, isConfigured else { return nil }
        
        let cacheKey = holdings.sorted().joined(separator: ",")
        
        // Return cached value if available
        if let cached = styleCache[cacheKey] {
            print("✅ [AI] Cache hit for \(holdings.count) holdings")
            return cached
        }
        
        // Check if request already in flight (avoid duplicates from multiple onAppear)
        if pendingStyleRequests.contains(cacheKey) {
            print("⏳ [AI] Request already pending for these holdings, skipping")
            return nil
        }
        
        // Mark as pending
        await MainActor.run { pendingStyleRequests.insert(cacheKey) }
        defer { Task { @MainActor in pendingStyleRequests.remove(cacheKey) } }
        
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        
        let prompt = """
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
        
        do {
            let style = try await chat(system: "You are a witty financial analyst.", user: prompt)
            let cleaned = style.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            styleCache[cacheKey] = cleaned
            print("✅ [AI] Generated style: \"\(cleaned)\"")
            return cleaned
        } catch {
            print("❌ [AI] Error: \(error.localizedDescription)")
            await MainActor.run { lastError = error.localizedDescription }
            return nil
        }
    }
    
    /// Batch generate styles for multiple users in ONE API call
    /// Returns dictionary of cacheKey -> style
    func getInvestmentStylesBatch(portfolios: [(userId: String, holdings: [String])]) async -> [String: String] {
        guard isConfigured, !portfolios.isEmpty else { return [:] }
        
        // Filter out users we already have cached
        var uncached: [(userId: String, holdings: [String], cacheKey: String)] = []
        var results: [String: String] = [:]
        
        for portfolio in portfolios {
            let cacheKey = portfolio.holdings.sorted().joined(separator: ",")
            if let cached = styleCache[cacheKey] {
                results[cacheKey] = cached
            } else if !portfolio.holdings.isEmpty {
                uncached.append((portfolio.userId, portfolio.holdings, cacheKey))
            }
        }
        
        // If everything was cached, return early
        if uncached.isEmpty {
            print("✅ [AI] All \(portfolios.count) styles from cache")
            return results
        }
        
        print("🤖 [AI] Generating \(uncached.count) styles in batch (cached: \(results.count))")
        
        // Build batch prompt
        var promptLines: [String] = []
        promptLines.append("Generate witty, sarcastic 4-6 word investment style taglines for these portfolios:")
        promptLines.append("")
        
        for (index, item) in uncached.enumerated() {
            promptLines.append("\(index + 1). Holdings: \(item.holdings.joined(separator: ", "))")
        }
        
        promptLines.append("")
        promptLines.append("Rules:")
        promptLines.append("- Be funny and slightly roast-y")
        promptLines.append("- Reference specific stocks or sectors when possible")
        promptLines.append("- No emojis")
        promptLines.append("")
        promptLines.append("Output format - just numbered taglines, one per line:")
        promptLines.append("1. [tagline]")
        promptLines.append("2. [tagline]")
        promptLines.append("etc.")
        
        let prompt = promptLines.joined(separator: "\n")
        
        do {
            let response = try await chat(system: "You are a witty financial analyst.", user: prompt)
            
            // Parse numbered responses
            let lines = response.components(separatedBy: .newlines)
            for line in lines {
                // Match "1. tagline" or "1: tagline" format
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let match = trimmed.range(of: #"^(\d+)[.\):\s]+(.+)$"#, options: .regularExpression) {
                    let fullMatch = String(trimmed[match])
                    if let numMatch = fullMatch.range(of: #"^\d+"#, options: .regularExpression),
                       let index = Int(fullMatch[numMatch]),
                       index >= 1, index <= uncached.count {
                        
                        let taglineStart = fullMatch.index(after: numMatch.upperBound)
                        var tagline = String(fullMatch[taglineStart...])
                            .trimmingCharacters(in: CharacterSet(charactersIn: ".:) "))
                            .replacingOccurrences(of: "\"", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        
                        let cacheKey = uncached[index - 1].cacheKey
                        styleCache[cacheKey] = tagline
                        results[cacheKey] = tagline
                        print("✅ [AI] Batch style \(index): \"\(tagline)\"")
                    }
                }
            }
        } catch {
            print("❌ [AI] Batch error: \(error.localizedDescription)")
        }
        
        return results
    }
    
    func clearCache() {
        styleCache.removeAll()
    }
    
    // MARK: - Provider Implementations
    
    private func callGemini(system: String, user: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=\(apiKey)")!
        
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
        
        print("🤖 [Gemini] Calling API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIError.parseError
        }
        
        return text
    }
    
    private func callOpenAI(system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.7,
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 [OpenAI] Calling API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }
        
        return content
    }
    
    private func callAnthropic(system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 [Claude] Calling API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.parseError
        }
        
        return text
    }
    
    private func callGrok(system: String, user: String) async throws -> String {
        // Grok uses OpenAI-compatible API
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "grok-beta",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.7,
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 [Grok] Calling API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }
        
        return content
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int, String)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI not configured. Add your API key in Settings."
        case .invalidResponse:
            return "Invalid response from AI"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .parseError:
            return "Failed to parse AI response"
        }
    }
}
