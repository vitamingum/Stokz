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
    
    // Cache for style taglines
    private var styleCache: [String: String] = [:]
    
    // Rate limiting
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0
    
    private init() {
        // Load saved provider first
        let provider: LLMProvider
        if let savedProvider = UserDefaults.standard.string(forKey: "ai_provider"),
           let p = LLMProvider(rawValue: savedProvider) {
            provider = p
        } else {
            provider = .gemini
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
    
    // MARK: - Chat API
    
    func chat(system: String, user: String) async throws -> String {
        guard isConfigured else {
            throw AIError.notConfigured
        }
        
        // Rate limiting
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                try? await Task.sleep(nanoseconds: UInt64((minRequestInterval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
        
        switch selectedProvider {
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
        if let cached = styleCache[cacheKey] {
            print("✅ [AI] Cache hit for \(holdings.count) holdings")
            return cached
        }
        
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
    
    func clearCache() {
        styleCache.removeAll()
    }
    
    // MARK: - Provider Implementations
    
    private func callGemini(system: String, user: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        
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
