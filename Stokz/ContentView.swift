import SwiftUI

/// ContentView - Main tab-based navigation
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        Group {
            if !appState.isInitialized {
                // Show loading screen while initializing
                LoadingView()
            } else if appState.authService.isAuthenticated {
                if appState.isLoading && appState.currentUserPortfolio == nil {
                    // Still loading data after auth
                    LoadingView(message: "Loading portfolio...")
                } else {
                    mainTabView
                }
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            PortfolioView()
                .tabItem {
                    Label("PORTFOLIO", systemImage: "chart.pie.fill")
                }
                .tag(0)
            
            UsersView()
                .tabItem {
                    Label("PLAYERS", systemImage: "person.2.fill")
                }
                .tag(1)
            
            StocksView()
                .tabItem {
                    Label("STOCKS", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
            
            LeaderboardView()
                .tabItem {
                    Label("SCORES", systemImage: "trophy.fill")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Label("SETTINGS", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(.white)
        .background(Color.black)
    }
}

// MARK: - Login View (LIQUID DEATH STYLE)
struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Pure black background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo - Bold B&W style
                VStack(spacing: 20) {
                    // Use app icon or bold text
                    Text("💀")
                        .font(.system(size: 80))
                    
                    Text("STOKZ")
                        .font(.system(size: 56, weight: .black))
                        .tracking(8)
                        .foregroundColor(.white)
                    
                    Text("MURDER YOUR PORTFOLIO")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(4)
                        .foregroundColor(Color(white: 0.5))
                }
                
                Spacer()
                
                // Features - Bold style
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "dollarsign.circle.fill", title: "$100K TO PLAY", description: "Paper trading. Real stakes.")
                    FeatureRow(icon: "person.3.fill", title: "DESTROY FRIENDS", description: "Climb the leaderboard.")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "LIVE PRICES", description: "Real market data.")
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Sign In Button - Bold white on black
                Button(action: signIn) {
                    HStack(spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("SIGN IN WITH GOOGLE")
                                .font(.system(size: 16, weight: .black))
                                .tracking(2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.white)
                    .foregroundColor(.black)
                }
                .disabled(isLoading)
                .padding(.horizontal, 32)
                
                // Terms - Subtle
                Text("BY SIGNING IN, YOU ACCEPT YOUR FATE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(Color(white: 0.3))
                    .padding(.bottom, 40)
            }
        }
    }
    
    private func signIn() {
        isLoading = true
        
        Task {
            await appState.signIn()
            isLoading = false
        }
    }
}

// MARK: - Feature Row (Liquid Death Style)
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .tracking(1)
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.5))
            }
        }
    }
}

// MARK: - Loading View (Branded)
struct LoadingView: View {
    var message: String = "Loading..."
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // App Icon with pulse animation
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)
                    
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                }
                
                Text("STOKZ")
                    .font(.system(size: 42, weight: .black))
                    .tracking(8)
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    Text(message.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(Color(white: 0.5))
                }
                
                Spacer()
                    .frame(height: 80)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}

#Preview("Login") {
    LoginView()
        .environmentObject(AppState.shared)
}

#Preview("Loading") {
    LoadingView(message: "Loading portfolio...")
}
