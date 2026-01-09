import SwiftUI

/// UsersView shows all players in the game
/// LIQUID DEATH STYLE - Bold Black & White
struct UsersView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var llmService = LocalLLMService.shared
    @State private var selectedUser: User?
    @State private var investmentStyles: [String: String] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.sheetsService.users) { user in
                            let entry = appState.leaderboard.first { $0.user.id == user.id }
                            
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    UserRowView(
                                        user: user,
                                        rank: entry?.rank,
                                        netWorth: entry?.netWorth,
                                        profitLossPercent: entry?.profitLossPercent,
                                        showRank: false,
                                        onTap: {
                                            selectedUser = user
                                        }
                                    )
                                    
                                    // Investment Style
                                    if let style = investmentStyles[user.id] {
                                        Text(style)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Color(white: 0.5))
                                            .padding(.leading, 52)  // Align with name (avatar width + spacing)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(Color(white: 0.15))
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PLAYERS")
                        .font(.system(size: 18, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white)
                }
            }
            .sheet(item: $selectedUser) { user in
                UserPortfolioView(user: user)
            }
            .refreshable {
                await appState.loadAllData()
                investmentStyles.removeAll()
                await loadInvestmentStyles()
            }
            .task {
                await loadInvestmentStyles()
            }
            .onChange(of: appState.sheetsService.users.count) { _, _ in
                investmentStyles.removeAll()
                Task {
                    await loadInvestmentStyles()
                }
            }
            .onChange(of: appState.leaderboard) { _, _ in
                // Leaderboard changes when portfolios change
                investmentStyles.removeAll()
                Task {
                    await loadInvestmentStyles()
                }
            }
            .onChange(of: llmService.isModelLoaded) { _, isLoaded in
                // Reload styles when model becomes ready
                if isLoaded {
                    investmentStyles.removeAll()
                    Task {
                        await loadInvestmentStyles()
                    }
                }
            }
            .overlay {
                if appState.sheetsService.users.isEmpty {
                    emptyStateView
                }
            }
        }
    }
    
    private func loadInvestmentStyles() async {
        for user in appState.sheetsService.users {
            let holdings = appState.sheetsService.portfolios[user.id]?.holdings.map { $0.symbol } ?? []
            let style = await LocalLLMService.shared.getInvestmentStyle(userId: user.id, holdings: holdings)
            await MainActor.run {
                investmentStyles[user.id] = style
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("👥")
                .font(.system(size: 80))
            
            Text("NO PLAYERS")
                .font(.system(size: 24, weight: .black))
                .tracking(4)
                .foregroundColor(.white)
            
            Text("INVITE FRIENDS TO\nJOIN THE CARNAGE")
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Preview
#Preview {
    UsersView()
        .environmentObject(AppState.shared)
}
