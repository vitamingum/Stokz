import SwiftUI

/// LeaderboardView shows all players ranked by net worth
/// LIQUID DEATH STYLE - Bold Black & White
struct LeaderboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedUser: User?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Top 3 Podium
                        if appState.leaderboard.count >= 3 {
                            podiumView
                        }
                        
                        // Full Leaderboard
                        leaderboardList
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LEADERBOARD")
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
            }
        }
    }
    
    // MARK: - Podium View (Liquid Death Style)
    private var podiumView: some View {
        HStack(alignment: .bottom, spacing: 16) {
            // 2nd Place
            if appState.leaderboard.count > 1 {
                podiumItem(entry: appState.leaderboard[1], height: 100)
            }
            
            // 1st Place
            if !appState.leaderboard.isEmpty {
                podiumItem(entry: appState.leaderboard[0], height: 130)
            }
            
            // 3rd Place
            if appState.leaderboard.count > 2 {
                podiumItem(entry: appState.leaderboard[2], height: 80)
            }
        }
        .padding()
        .padding(.top, 20)
        .background(Color.black)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.2)),
            alignment: .bottom
        )
    }
    
    private func podiumItem(entry: LeaderboardEntry, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Rank Medal
            ZStack {
                Circle()
                    .fill(medalColor(for: entry.rank))
                    .frame(width: 36, height: 36)
                
                Text("\(entry.rank)")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.black)
            }
            
            // Avatar
            UserAvatarView(user: entry.user, size: 50)
            
            // Name
            Text(entry.user.displayName.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Net Worth
            Text(entry.netWorth.asCompactCurrency)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.5))
            
            // Podium block
            Rectangle()
                .fill(Color(white: 0.1))
                .frame(height: height)
                .overlay(
                    Rectangle()
                        .stroke(medalColor(for: entry.rank), lineWidth: 2)
                )
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {
            selectedUser = entry.user
        }
    }
    
    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return .white // Gold -> White for B&W
        case 2: return Color(white: 0.6) // Silver
        case 3: return Color(white: 0.4) // Bronze
        default: return Color(white: 0.3)
        }
    }
    
    // MARK: - Leaderboard List (Liquid Death Style)
    private var leaderboardList: some View {
        VStack(spacing: 0) {
            ForEach(appState.leaderboard) { entry in
                VStack(spacing: 0) {
                    LeaderboardRow(
                        entry: entry,
                        onTap: {
                            selectedUser = entry.user
                        }
                    )
                    .padding(.horizontal)
                    
                    if entry.id != appState.leaderboard.last?.id {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(white: 0.15))
                            .padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color.black)
        .padding()
    }
}

// MARK: - Leaderboard Row (Liquid Death Style)
struct LeaderboardRow: View {
    @EnvironmentObject var appState: AppState
    let entry: LeaderboardEntry
    var onTap: (() -> Void)?
    
    @State private var investmentStyle: String?
    @State private var isLoadingStyle = false
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                // Rank number (LEFT)
                ZStack {
                    Circle()
                        .fill(rankColor)
                        .frame(width: 32, height: 32)
                    
                    Text("\(entry.rank)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.black)
                }
                
                // Avatar
                UserAvatarView(user: entry.user, size: 40)
                
                // Name and Performance
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.user.displayName.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white)
                    
                    // Investment style tagline from Gemini
                    if let style = investmentStyle {
                        Text(style)
                            .font(.system(size: 10, weight: .medium))
                            .italic()
                            .foregroundColor(Color(white: 0.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isLoadingStyle {
                        Text("...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(white: 0.3))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: entry.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(abs(entry.profitLossPercent), specifier: "%.2f")%")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(entry.isPositive ? .white : Color(white: 0.4))
                }
                
                Spacer()
                
                // Net Worth (RIGHT)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(entry.netWorth.asCurrency)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                    
                    Text("NET WORTH")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.4))
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadInvestmentStyle()
        }
    }
    
    private func loadInvestmentStyle() {
        print("🤖 [Gemini] loadInvestmentStyle called for user: \(entry.user.displayName)")
        
        // Get user's holdings from the sheets service
        guard let portfolio = appState.sheetsService.portfolios[entry.user.id] else {
            print("🤖 [Gemini] No portfolio found for user \(entry.user.id)")
            return
        }
        
        guard !portfolio.holdings.isEmpty else {
            print("🤖 [Gemini] Portfolio empty for user \(entry.user.displayName)")
            return
        }
        
        let holdings = portfolio.holdings.map { $0.symbol }
        print("🤖 [AI] Found \(holdings.count) holdings: \(holdings.joined(separator: ", "))")
        
        isLoadingStyle = true
        Task {
            let style = await AIService.shared.getInvestmentStyle(holdings: holdings)
            await MainActor.run {
                self.investmentStyle = style
                self.isLoadingStyle = false
                print("🤖 [AI] Style set: \(style ?? "nil")")
            }
        }
    }
    
    private var rankColor: Color {
        switch entry.rank {
        case 1: return .white
        case 2: return Color(white: 0.6)
        case 3: return Color(white: 0.4)
        default: return Color(white: 0.25)
        }
    }
}

// MARK: - Preview
#Preview {
    LeaderboardView()
        .environmentObject(AppState.shared)
}
