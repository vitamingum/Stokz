import SwiftUI

/// UserPortfolioView shows another user's portfolio in read-only mode
/// LIQUID DEATH STYLE - Bold Black & White
struct UserPortfolioView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let user: User
    
    @State private var selectedTimeRange: TimeRange = .oneMonth
    
    private var portfolio: Portfolio {
        appState.sheetsService.getPortfolio(for: user.id)
    }
    
    private var allocations: [(symbol: String, percent: Double, value: Double)] {
        appState.portfolioManager.getAllocations(
            portfolio: portfolio,
            prices: appState.priceService.prices
        )
    }
    
    private var netWorth: Double {
        appState.portfolioManager.calculateNetWorth(
            portfolio: portfolio,
            prices: appState.priceService.prices
        )
    }
    
    private var profitLossPercent: Double {
        ((netWorth - PortfolioManager.initialCash) / PortfolioManager.initialCash) * 100
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // User Header
                        userHeader
                        
                        // Performance Chart
                        chartSection
                        
                        // Holdings
                        holdingsSection
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(user.displayName.uppercased())
                        .font(.system(size: 18, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - User Header (Liquid Death Style)
    private var userHeader: some View {
        VStack(spacing: 16) {
            UserAvatarView(user: user, size: 70)
            
            VStack(spacing: 8) {
                Text("NET WORTH")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundColor(Color(white: 0.5))
                
                Text(netWorth.asCurrency)
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
                
                HStack(spacing: 6) {
                    Image(systemName: profitLossPercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(profitLossPercent, specifier: "%+.2f")%")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundColor(profitLossPercent >= 0 ? .white : Color(white: 0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.black)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.2)),
            alignment: .bottom
        )
    }
    
    // MARK: - Chart Section (Liquid Death Style)
    private var chartSection: some View {
        VStack(spacing: 16) {
            // Time Range Picker
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.displayName.uppercased()).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Chart
            PerformanceChartView(
                userId: user.id,
                timeRange: selectedTimeRange
            )
            .frame(height: 200)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.black)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.2)),
            alignment: .bottom
        )
    }
    
    // MARK: - Holdings Section (Liquid Death Style)
    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HOLDINGS")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundColor(Color(white: 0.5))
                .padding(.horizontal)
                .padding(.top)
            
            if allocations.isEmpty {
                VStack(spacing: 12) {
                    Text("💀")
                        .font(.system(size: 40))
                    Text("NO HOLDINGS YET")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(2)
                        .foregroundColor(Color(white: 0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(allocations, id: \.symbol) { allocation in
                        let stock = appState.priceService.stocks[allocation.symbol]
                        
                        VStack(spacing: 0) {
                            StockRowView(
                                symbol: allocation.symbol,
                                allocationPercent: allocation.percent,
                                stock: stock
                            )
                            .padding(.horizontal)
                            
                            if allocation.symbol != allocations.last?.symbol {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(Color(white: 0.15))
                                    .padding(.leading)
                            }
                        }
                    }
                }
                .background(Color(white: 0.08))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }
}

// MARK: - Preview
#Preview {
    UserPortfolioView(
        user: User(
            id: "user1",
            email: "alice@example.com",
            displayName: "Alice",
            photoURL: nil,
            createdAt: Date()
        )
    )
    .environmentObject(AppState.shared)
}
