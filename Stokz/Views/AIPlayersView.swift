import SwiftUI

/// View for creating and managing AI players
struct AIPlayersView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var aiPlayerService = AIPlayerService.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showingCreateSheet = false
    @State private var aiPlayers: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isAutoTrading = false
    @State private var lastTradeResults: [String: String] = [:]  // playerId -> result message
    
    /// Current user's AI players only (for auto-trading)
    private var myAIPlayers: [User] {
        guard let currentUser = appState.authService.currentUser else { return [] }
        return aiPlayers.filter { $0.ownerId == currentUser.id }
    }
    
    /// Check if current user owns this AI player
    private func isOwned(_ player: User) -> Bool {
        guard let currentUser = appState.authService.currentUser else { return false }
        return player.ownerId == currentUser.id
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                        
                        // Auto-trading status
                        if isAutoTrading {
                            autoTradingBanner
                        }
                        
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Auto-trade when app comes to foreground
                    Task {
                        await autoTradeAllPlayers()
                    }
                }
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
            // My AI Players section
            if !myAIPlayers.isEmpty {
                Text("MY AI PLAYERS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.neonGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(myAIPlayers) { player in
                    AIPlayerCard(
                        player: player,
                        isOwned: true,
                        lastTradeResult: lastTradeResults[player.id],
                        onTrade: { setTrading in
                            Task {
                                setTrading(true)
                                await triggerTrade(for: player)
                                setTrading(false)
                            }
                        }
                    )
                }
            }
            
            // Other players' AI Players
            let otherAIPlayers = aiPlayers.filter { !isOwned($0) }
            if !otherAIPlayers.isEmpty {
                Text("OTHER AI PLAYERS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, myAIPlayers.isEmpty ? 0 : 16)
                
                ForEach(otherAIPlayers) { player in
                    AIPlayerCard(
                        player: player,
                        isOwned: false,
                        lastTradeResult: nil,
                        onTrade: { _ in }
                    )
                }
            }
        }
    }
    
    private var autoTradingBanner: some View {
        HStack {
            ProgressView()
                .tint(Theme.neonGreen)
                .scaleEffect(0.8)
            Text("AI PLAYERS ARE TRADING...")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Theme.neonGreen)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.neonGreen.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func loadAIPlayers() async {
        isLoading = true
        defer { isLoading = false }
        
        aiPlayers = appState.sheetsService.users.filter { $0.isAI }
    }
    
    /// Liquidates entire portfolio and rebuilds from scratch using TALL BOY screener
    private func triggerTrade(for player: User) async {
        guard let portfolio = appState.sheetsService.portfolios[player.id] else {
            await MainActor.run {
                lastTradeResults[player.id] = "No portfolio found"
            }
            return
        }
        
        do {
            let prices = appState.priceService.prices
            
            print("🤖 [\(player.displayName)] LIQUIDATING portfolio to rebuild with TALL BOY...")
            
            // Step 1: Liquidate all holdings - convert to cash
            var liquidatedPortfolio = portfolio
            let totalValue = portfolio.totalValue(prices: prices)
            liquidatedPortfolio.holdings = []
            liquidatedPortfolio.cashBalance = totalValue
            
            print("🤖 [\(player.displayName)] Liquidated to $\(String(format: "%.0f", totalValue)) cash")
            
            // Step 2: Get fresh picks from TALL BOY screener
            let tickers = try await aiPlayerService.getInitialPortfolio(for: player, maxStocks: 10)
            
            guard !tickers.isEmpty else {
                print("⚠️ [\(player.displayName)] TALL BOY returned no picks, keeping cash")
                try await appState.sheetsService.savePortfolio(liquidatedPortfolio)
                await MainActor.run {
                    lastTradeResults[player.id] = "No picks found"
                }
                return
            }
            
            print("🤖 [\(player.displayName)] TALL BOY picks: \(tickers.joined(separator: ", "))")
            
            // Step 3: Build new portfolio with equal allocation to each pick
            var newPortfolio = liquidatedPortfolio
            let perStock = totalValue / Double(tickers.count)
            
            for ticker in tickers {
                guard let price = prices[ticker], price > 0 else {
                    print("⚠️ [\(player.displayName)] No price for \(ticker), skipping")
                    continue
                }
                
                let shares = perStock / price
                let holding = PortfolioHolding(
                    id: UUID().uuidString,
                    symbol: ticker,
                    shares: shares,
                    entryPrice: price,
                    entryDate: Date(),
                    costBasis: perStock
                )
                newPortfolio.holdings.append(holding)
                newPortfolio.cashBalance -= perStock
            }
            
            // Mop up any remaining cash into first holding
            if newPortfolio.cashBalance > 1 && !newPortfolio.holdings.isEmpty {
                let extraShares = newPortfolio.cashBalance / (prices[newPortfolio.holdings[0].symbol] ?? 1)
                newPortfolio.holdings[0] = PortfolioHolding(
                    id: newPortfolio.holdings[0].id,
                    symbol: newPortfolio.holdings[0].symbol,
                    shares: newPortfolio.holdings[0].shares + extraShares,
                    entryPrice: newPortfolio.holdings[0].entryPrice,
                    entryDate: newPortfolio.holdings[0].entryDate,
                    costBasis: newPortfolio.holdings[0].costBasis + newPortfolio.cashBalance
                )
                newPortfolio.cashBalance = 0
            }
            
            print("🤖 [\(player.displayName)] New portfolio built with \(newPortfolio.holdings.count) stocks")
            
            // Step 4: Save the new portfolio
            try await appState.sheetsService.savePortfolio(newPortfolio)
            
            print("✅ [\(player.displayName)] Portfolio rebuild complete!")
            
            await MainActor.run {
                lastTradeResults[player.id] = "Rebuilt with \(newPortfolio.holdings.count) stocks"
            }
            
        } catch {
            await MainActor.run {
                lastTradeResults[player.id] = "Error: \(error.localizedDescription)"
            }
            print("❌ AI trade error: \(error)")
        }
    }
    
    /// Auto-trade all AI players owned by the current user
    private func autoTradeAllPlayers() async {
        guard !myAIPlayers.isEmpty else { return }
        
        await MainActor.run {
            isAutoTrading = true
            lastTradeResults = [:]
        }
        
        // Trade each AI player sequentially to avoid rate limits
        for player in myAIPlayers {
            await triggerTrade(for: player)
            // Small delay between trades to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }
        
        await MainActor.run {
            isAutoTrading = false
        }
    }
}

// MARK: - AI Player Card

struct AIPlayerCard: View {
    let player: User
    var isOwned: Bool = true
    var lastTradeResult: String?
    let onTrade: (@escaping (Bool) -> Void) -> Void
    
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
            
            // Last trade result
            if let result = lastTradeResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.neonGreen)
                    Text(result)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.neonGreen)
                }
                .transition(.opacity)
            }
            
            // Trade Button (only for owned AI players)
            if isOwned {
                Button {
                    onTrade { trading in
                        isTrading = trading
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
                        Text(isTrading ? "REBUILDING..." : "REBUILD PORTFOLIO")
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
                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            
                            TextField("e.g., TALL BOY", text: $name)
                                .textFieldStyle(.plain)
                                .font(.headline)
                                .foregroundColor(Theme.text)
                                .padding()
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                        }
                        
                        // LLM Provider
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI BRAIN")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            
                            Picker("Provider", selection: $selectedProvider) {
                                ForEach(LLMProvider.allCases, id: \.self) { provider in
                                    Text(provider.rawValue.uppercased())
                                        .tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Thesis
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INVESTMENT THESIS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            
                            TextEditor(text: $thesis)
                                .font(.body)
                                .foregroundColor(Theme.text)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding()
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                            
                            Text("\(thesis.count)/20 min characters")
                                .font(.caption)
                                .foregroundColor(thesis.count >= 20 ? Theme.positive : Theme.textSecondary)
                        }
                        
                        // Example theses
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EXAMPLE THESES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            
                            ForEach(exampleTheses, id: \.self) { example in
                                Button {
                                    thesis = example
                                } label: {
                                    Text(example)
                                        .font(.caption)
                                        .foregroundColor(Theme.text)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Theme.cardBackground)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.negative)
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("CREATE AI PLAYER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.textSecondary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await createAIPlayer() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(Theme.neonGreen)
                        } else {
                            Text("Create")
                                .fontWeight(.bold)
                        }
                    }
                    .foregroundColor(isValid ? Theme.neonGreen : Theme.textSecondary)
                    .disabled(!isValid || isCreating)
                }
            }
        }
    }
    
    private let exampleTheses = [
        "Focus on high-growth tech companies with strong AI exposure and recurring revenue models.",
        "Value investing in dividend aristocrats with 10+ years of consistent dividend growth.",
        "Small-cap momentum plays with recent earnings beats and analyst upgrades.",
        "ESG leaders with strong environmental ratings and clean energy exposure."
    ]
    
    private func createAIPlayer() async {
        guard isValid else { return }
        
        isCreating = true
        errorMessage = nil
        
        do {
            let aiPlayer = try await AIPlayerService.shared.createAIPlayer(
                name: name,
                thesis: thesis,
                provider: selectedProvider
            )
            
            await MainActor.run {
                onCreated(aiPlayer)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#Preview {
    AIPlayersView()
        .environmentObject(AppState())
}
