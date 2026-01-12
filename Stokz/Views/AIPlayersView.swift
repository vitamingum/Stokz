import SwiftUI

/// View for creating and managing AI players
struct AIPlayersView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var aiPlayerService = AIPlayerService.shared
    
    @State private var showingCreateSheet = false
    @State private var aiPlayers: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                        
                        if isLoading {
                            ProgressView()
                                .tint(Theme.neonGreen)
                                .padding(.top, 40)
                        } else if aiPlayers.isEmpty {
                            emptyState
                        } else {
                            aiPlayersList
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("AI PLAYERS")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Theme.neonGreen)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateAIPlayerView { newPlayer in
                    aiPlayers.append(newPlayer)
                }
            }
            .task {
                await loadAIPlayers()
            }
            .refreshable {
                await loadAIPlayers()
            }
        }
    }
    
    // MARK: - Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KILLER AI AGENTS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Theme.neonGreen)
            
            Text("Create AI players with investment theses. Each AI uses its own LLM brain to make trading decisions.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 60))
                .foregroundColor(Theme.textSecondary)
            
            Text("NO AI PLAYERS YET")
                .font(.headline)
                .foregroundColor(Theme.text)
            
            Text("Create an AI player to compete against.\nGive it a thesis and watch it trade.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingCreateSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("CREATE AI PLAYER")
                }
                .font(.headline)
                .foregroundColor(Theme.background)
                .padding()
                .background(Theme.neonGreen)
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding(.top, 60)
    }
    
    private var aiPlayersList: some View {
        LazyVStack(spacing: 12) {
            ForEach(aiPlayers) { player in
                AIPlayerCard(player: player) {
                    // Trigger a trade for this AI
                    Task {
                        await triggerTrade(for: player)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadAIPlayers() async {
        isLoading = true
        defer { isLoading = false }
        
        aiPlayers = appState.sheetsService.users.filter { $0.isAI }
    }
    
    private func triggerTrade(for player: User) async {
        guard let portfolio = appState.sheetsService.portfolios[player.id] else {
            errorMessage = "No portfolio found for \(player.displayName)"
            return
        }
        
        do {
            let prices = appState.priceService.prices
            let decision = try await aiPlayerService.getTradeDecision(
                for: player,
                portfolio: portfolio,
                prices: prices
            )
            
            print("🤖 [\(player.displayName)] Decision: \(decision.action.rawValue) \(decision.symbol ?? "") - \(decision.reasoning)")
            
            // Execute the trade
            if let symbol = decision.symbol {
                switch decision.action {
                case .buy:
                    let updatedPortfolio = PortfolioManager.shared.addStock(
                        symbol: symbol,
                        to: portfolio,
                        prices: prices
                    )
                    try await appState.sheetsService.savePortfolio(updatedPortfolio)
                    
                case .sell:
                    let updatedPortfolio = PortfolioManager.shared.removeStock(
                        symbol: symbol,
                        from: portfolio,
                        prices: prices
                    )
                    try await appState.sheetsService.savePortfolio(updatedPortfolio)
                    
                case .hold:
                    break
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ AI trade error: \(error)")
        }
    }
}

// MARK: - AI Player Card

struct AIPlayerCard: View {
    let player: User
    let onTrade: () -> Void
    
    @EnvironmentObject var appState: AppState
    @State private var isTrading = false
    
    private var portfolio: Portfolio? {
        appState.sheetsService.portfolios[player.id]
    }
    
    private var netWorth: Double {
        portfolio?.totalValue(prices: appState.priceService.prices) ?? 100_000
    }
    
    private var pnlPercent: Double {
        portfolio?.totalProfitLossPercent(prices: appState.priceService.prices) ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // AI Icon
                ZStack {
                    Circle()
                        .fill(providerColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundColor(providerColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayName)
                        .font(.headline)
                        .foregroundColor(Theme.text)
                    
                    Text(player.aiProvider?.uppercased() ?? "GEMINI")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(providerColor)
                }
                
                Spacer()
                
                // Net Worth
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(netWorth, specifier: "%.0f")")
                        .font(.headline)
                        .foregroundColor(Theme.text)
                    
                    Text("\(pnlPercent >= 0 ? "+" : "")\(pnlPercent, specifier: "%.1f")%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(pnlPercent >= 0 ? Theme.positive : Theme.negative)
                }
            }
            
            // Thesis
            if let thesis = player.aiThesis {
                Text(thesis)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(3)
            }
            
            // Holdings preview
            if let portfolio = portfolio, !portfolio.holdings.isEmpty {
                HStack {
                    Text(portfolio.holdings.prefix(5).map { $0.symbol }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    
                    if portfolio.holdings.count > 5 {
                        Text("+\(portfolio.holdings.count - 5) more")
                            .font(.caption)
                            .foregroundColor(Theme.neonGreen)
                    }
                }
            }
            
            // Trade Button
            Button {
                isTrading = true
                onTrade()
                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isTrading = false
                }
            } label: {
                HStack {
                    if isTrading {
                        ProgressView()
                            .tint(Theme.background)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(isTrading ? "THINKING..." : "MAKE A TRADE")
                }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(providerColor)
                .cornerRadius(8)
            }
            .disabled(isTrading)
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
    
    private var providerColor: Color {
        switch player.aiProvider?.lowercased() {
        case "gemini": return Color.blue
        case "openai", "chatgpt": return Color.green
        case "anthropic", "claude": return Color.orange
        case "grok": return Color.purple
        default: return Theme.neonGreen
        }
    }
}

// MARK: - Create AI Player Sheet

struct CreateAIPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let onCreated: (User) -> Void
    
    @State private var name = ""
    @State private var thesis = ""
    @State private var selectedProvider: LLMProvider = .gemini
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    private var isValid: Bool {
        !name.isEmpty && thesis.count >= 20
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.neonGreen)
                            
                            TextField("e.g. Warren Bot", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundColor(Theme.text)
                                .padding()
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                        }
                        
                        // Provider Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LLM BRAIN")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.neonGreen)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(LLMProvider.allCases, id: \.self) { provider in
                                    ProviderButton(
                                        provider: provider,
                                        isSelected: selectedProvider == provider,
                                        hasKey: hasAPIKey(for: provider)
                                    ) {
                                        selectedProvider = provider
                                    }
                                }
                            }
                            
                            if !hasAPIKey(for: selectedProvider) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("No API key for \(selectedProvider.displayName). Add it in Settings first.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        // Thesis Field
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("INVESTMENT THESIS")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.neonGreen)
                                
                                Spacer()
                                
                                Text("\(thesis.count)/500")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            
                            TextEditor(text: $thesis)
                                .font(.body)
                                .foregroundColor(Theme.text)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 150)
                                .padding()
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                                .onChange(of: thesis) { _, newValue in
                                    if newValue.count > 500 {
                                        thesis = String(newValue.prefix(500))
                                    }
                                }
                            
                            Text("Describe how this AI should invest. Be specific about sectors, risk tolerance, and strategy.")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        
                        // Example Theses
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EXAMPLE THESES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            
                            ForEach(exampleTheses, id: \.name) { example in
                                Button {
                                    name = example.name
                                    thesis = example.thesis
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(example.name)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(Theme.neonGreen)
                                        Text(example.thesis)
                                            .font(.caption)
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Theme.cardBackground.opacity(0.5))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.negative)
                                .padding()
                                .background(Theme.negative.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        // Create Button
                        Button {
                            Task { await createAIPlayer() }
                        } label: {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .tint(Theme.background)
                                } else {
                                    Image(systemName: "cpu")
                                    Text("CREATE AI PLAYER")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValid ? Theme.neonGreen : Theme.textSecondary)
                            .cornerRadius(12)
                        }
                        .disabled(!isValid || isCreating)
                    }
                    .padding()
                }
            }
            .navigationTitle("NEW AI PLAYER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
    
    private func hasAPIKey(for provider: LLMProvider) -> Bool {
        let key = UserDefaults.standard.string(forKey: "stokz_ai_key_\(provider.rawValue)") ?? ""
        return !key.isEmpty
    }
    
    private func createAIPlayer() async {
        guard isValid else { return }
        
        isCreating = true
        errorMessage = nil
        
        do {
            // Create the AI user
            let aiUser = User(
                id: "ai_\(UUID().uuidString.prefix(8))",
                email: "ai@stokz.app",
                displayName: name,
                photoURL: nil,
                createdAt: Date(),
                isAI: true,
                aiThesis: thesis,
                aiProvider: selectedProvider.rawValue
            )
            
            // Save to Google Sheets
            try await appState.sheetsService.saveUser(aiUser)
            
            // Create empty portfolio for AI
            let portfolio = Portfolio(userId: aiUser.id)
            try await appState.sheetsService.savePortfolio(portfolio)
            
            // Get initial stock picks from AI
            let aiService = AIPlayerService.shared
            let initialPicks = try await aiService.getInitialPortfolio(for: aiUser)
            
            // Build the portfolio with those picks
            var updatedPortfolio = portfolio
            let priceService = StockPriceService.shared
            
            // Fetch prices for all picks
            let _ = try? await priceService.fetchQuotes(symbols: initialPicks)
            let prices = priceService.prices
            
            for symbol in initialPicks {
                updatedPortfolio = PortfolioManager.shared.addStock(
                    symbol: symbol,
                    to: updatedPortfolio,
                    prices: prices
                )
            }
            
            // Save the built portfolio
            try await appState.sheetsService.savePortfolio(updatedPortfolio)
            
            await MainActor.run {
                onCreated(aiUser)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
    
    private var exampleTheses: [(name: String, thesis: String)] {
        [
            (
                name: "Tech Bull 🚀",
                thesis: "I believe technology is the future. I focus heavily on AI, cloud computing, and semiconductor companies. I'm willing to take on higher volatility for potentially higher returns. I prefer established tech giants but will consider promising growth stocks."
            ),
            (
                name: "Dividend Hunter 💰",
                thesis: "I prioritize stable, dividend-paying companies. I look for established businesses with consistent cash flows in sectors like utilities, consumer staples, and healthcare. Capital preservation is more important than aggressive growth."
            ),
            (
                name: "Contrarian Carl 🎲",
                thesis: "I buy when others are fearful. I look for beaten-down stocks in out-of-favor sectors that have strong fundamentals. I'm patient and willing to hold positions that the market currently hates, waiting for sentiment to turn."
            )
        ]
    }
}

// MARK: - Provider Button

struct ProviderButton: View {
    let provider: LLMProvider
    let isSelected: Bool
    let hasKey: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: providerIcon)
                    .foregroundColor(isSelected ? Theme.background : providerColor)
                
                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? Theme.background : Theme.text)
                
                if !hasKey {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? providerColor : Theme.cardBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? providerColor : Color.clear, lineWidth: 2)
            )
        }
    }
    
    private var providerIcon: String {
        switch provider {
        case .gemini: return "sparkles"
        case .openai: return "bubble.left.fill"
        case .anthropic: return "brain"
        case .grok: return "bolt.fill"
        }
    }
    
    private var providerColor: Color {
        switch provider {
        case .gemini: return .blue
        case .openai: return .green
        case .anthropic: return .orange
        case .grok: return .purple
        }
    }
}

#Preview {
    AIPlayersView()
        .environmentObject(AppState())
}
