import SwiftUI

/// ContentView - Main tab-based navigation
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("selectedTab") private var selectedTab = 0
    @StateObject private var bugReportService = BugReportService.shared
    @StateObject private var aiService = AIService.shared
    @AppStorage("hasCompletedAPIKeySetup") private var hasCompletedAPIKeySetup = false
    @State private var showInvalidKeyToast = false
    @State private var invalidKeyMessage = ""
    
    var body: some View {
        Group {
            if !appState.isInitialized {
                // Show loading screen while initializing
                LoadingView()
            } else if appState.authService.isAuthenticated {
                // After auth, check if API key is set up
                if !hasCompletedAPIKeySetup && !aiService.isConfigured {
                    APIKeySetupView(onComplete: {
                        hasCompletedAPIKeySetup = true
                    })
                } else if appState.isLoading && appState.leaderboard.isEmpty && appState.allStocksWithOwners.isEmpty {
                    // Still loading data after auth - check multiple data sources
                    LoadingView(message: "Loading portfolio...")
                } else {
                    mainTabView
                        .onAppear {
                            validateAPIKeyOnStart()
                        }
                }
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
        .onShake {
            bugReportService.triggerBugReport()
        }
        .sheet(isPresented: $bugReportService.isShowingBugReport) {
            BugReportView()
                .environmentObject(appState)
        }
        .overlay(alignment: .top) {
            if showInvalidKeyToast {
                InvalidAPIKeyToast(message: invalidKeyMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        // Navigate to settings
                        selectedTab = 4
                        withAnimation { showInvalidKeyToast = false }
                    }
            }
        }
        .overlay(alignment: .top) {
            if appState.showDataRefreshedToast {
                DataRefreshedToast(message: appState.dataRefreshMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showInvalidKeyToast)
        .animation(.easeInOut, value: appState.showDataRefreshedToast)
    }
    
    private func validateAPIKeyOnStart() {
        guard aiService.isConfigured else { return }
        
        Task {
            let isValid = await aiService.validateAPIKey()
            if !isValid {
                await MainActor.run {
                    invalidKeyMessage = aiService.validationMessage ?? "Invalid API key"
                    showInvalidKeyToast = true
                    
                    // Auto-dismiss after 5 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        await MainActor.run {
                            withAnimation { showInvalidKeyToast = false }
                        }
                    }
                }
            }
        }
    }
    
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            PortfolioView()
                .tabItem {
                    Label("PORTFOLIO", systemImage: "chart.pie.fill")
                }
                .tag(0)
            
            LeaderboardView()
                .tabItem {
                    Label("PLAYERS", systemImage: "trophy.fill")
                }
                .tag(1)
            
            StocksView()
                .tabItem {
                    Label("STOCKS", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
            
            AIPlayersView()
                .tabItem {
                    Label("AI", systemImage: "cpu")
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
                    FeatureRow(icon: "dollarsign.circle.fill", title: "MURDER THE MARKET", description: "$100K paper money. Real carnage.")
                    FeatureRow(icon: "person.3.fill", title: "DESTROY FRIENDSHIPS", description: "Climb the leaderboard.")
                    FeatureRow(icon: "brain", title: "KILLER AI AGENTS", description: "Smack talk that buries.")
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

// MARK: - Invalid API Key Toast
struct InvalidAPIKeyToast: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("API KEY INVALID")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
                    .foregroundColor(.white)
                
                Text(message + " • Tap to fix")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(Color(white: 0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.15))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 50) // Below dynamic island/notch
    }
}

// MARK: - Data Refreshed Toast
struct DataRefreshedToast: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.15))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .padding(.top, 50) // Below dynamic island/notch
    }
}

// MARK: - Spinning Skull Loading Indicator
/// Small spinning app icon used as a global loading indicator in nav bars
struct SpinningSkull: View {
    @State private var isAnimating = false

    var body: some View {
        Image("AppIconImage")
            .resizable()
            .scaledToFill()
            .scaleEffect(1.7)
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
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
