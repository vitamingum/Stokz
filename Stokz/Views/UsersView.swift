import SwiftUI

/// UsersView shows all players in the game
/// LIQUID DEATH STYLE - Bold Black & White
struct UsersView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedUser: User?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.sheetsService.users) { user in
                            let entry = appState.leaderboard.first { $0.user.id == user.id }
                            
                            VStack(spacing: 0) {
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
            }
            .overlay {
                if appState.sheetsService.users.isEmpty {
                    emptyStateView
                }
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
