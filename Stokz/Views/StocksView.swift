import SwiftUI

/// StocksView shows union of all stocks across all users
/// LIQUID DEATH STYLE - Bold Black & White
struct StocksView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var llmService = LocalLLMService.shared
    @State private var selectedStock: StockWithOwners?
    
    // Sort stocks by day change for ranking
    private var rankedStocks: [(stock: StockWithOwners, rank: Int)] {
        let sorted = appState.allStocksWithOwners.sorted { $0.stock.priceChangePercent > $1.stock.priceChangePercent }
        return sorted.enumerated().map { (stock: $0.element, rank: $0.offset + 1) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rankedStocks, id: \.stock.id) { item in
                            let emoji = llmService.getStocksTabEmoji(
                                symbol: item.stock.stock.symbol,
                                rank: item.rank,
                                totalStocks: rankedStocks.count,
                                dayChangePercent: item.stock.stock.priceChangePercent
                            )
                            VStack(spacing: 0) {
                                StockWithOwnersRow(
                                    stockWithOwners: item.stock,
                                    emoji: emoji,
                                    onTap: {
                                        selectedStock = item.stock
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
                    Text("ALL STOCKS")
                        .font(.system(size: 18, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white)
                }
            }
            .sheet(item: $selectedStock) { stockWithOwners in
                StockDetailView(stockWithOwners: stockWithOwners)
            }
            .refreshable {
                await appState.loadAllData()
            }
            .overlay {
                if appState.allStocksWithOwners.isEmpty {
                    emptyStateView
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("📈")
                .font(.system(size: 80))
            
            Text("NO STOCKS")
                .font(.system(size: 24, weight: .black))
                .tracking(4)
                .foregroundColor(.white)
            
            Text("ADD STOCKS TO YOUR PORTFOLIO\nTO SEE THEM HERE")
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Stock with Owners Row (Liquid Death Style)
struct StockWithOwnersRow: View {
    let stockWithOwners: StockWithOwners
    var emoji: String = LocalLLMService.placeholder
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 10) {
                // Stock Info
                HStack {
                    // Emoji
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(stockWithOwners.stock.symbol)
                                .font(.system(size: 18, weight: .black))
                                .tracking(1)
                                .foregroundColor(.white)
                            
                            // Daily change - small colored text
                            Text("\(stockWithOwners.stock.priceChangePercent >= 0 ? "+" : "")\(String(format: "%.1f", stockWithOwners.stock.priceChangePercent))%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(stockWithOwners.stock.priceChangePercent >= 0 ? .green : .red)
                        }
                        
                        Text(stockName(for: stockWithOwners.stock.symbol).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color(white: 0.5))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(stockWithOwners.stock.currentPrice.asCurrency)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            Image(systemName: stockWithOwners.stock.isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(abs(stockWithOwners.stock.priceChangePercent), specifier: "%.2f")%")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(stockWithOwners.stock.isPositive ? .white : Color(white: 0.4))
                    }
                }
                
                // Owners
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.4))
                    
                    Text(ownersText.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(Color(white: 0.4))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var ownersText: String {
        let names = stockWithOwners.owners.map { $0.displayName }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        } else {
            return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2) more"
        }
    }
    
    private func stockName(for symbol: String) -> String {
        let names: [String: String] = [
            "AAPL": "Apple Inc.",
            "GOOGL": "Alphabet Inc.",
            "MSFT": "Microsoft Corp.",
            "TSLA": "Tesla Inc.",
            "NVDA": "NVIDIA Corp.",
            "AMZN": "Amazon.com Inc.",
            "META": "Meta Platforms Inc.",
            "NFLX": "Netflix Inc.",
            "AMD": "AMD Inc.",
            "DIS": "Walt Disney Co."
        ]
        return names[symbol] ?? symbol
    }
}

// MARK: - Stock Detail View (Liquid Death Style)
struct StockDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let stockWithOwners: StockWithOwners
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Stock Price Section
                        VStack(spacing: 12) {
                            Text(stockWithOwners.stock.currentPrice.asCurrency)
                                .font(.system(size: 48, weight: .black))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 6) {
                                Image(systemName: stockWithOwners.stock.isPositive ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 14, weight: .bold))
                                Text("\(stockWithOwners.stock.priceChange.asSignedCurrency) (\(stockWithOwners.stock.priceChangePercent, specifier: "%+.2f")%)")
                                    .font(.system(size: 14, weight: .heavy))
                            }
                            .foregroundColor(stockWithOwners.stock.isPositive ? .white : Color(white: 0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color(white: 0.2)),
                            alignment: .bottom
                        )
                        
                        // Owners Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("OWNED BY")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(3)
                                .foregroundColor(Color(white: 0.5))
                                .padding(.horizontal)
                            
                            ForEach(stockWithOwners.owners) { user in
                                let allocation = getAllocation(for: user.id)
                                
                                HStack {
                                    UserAvatarView(user: user, size: 36)
                                    
                                    Text(user.displayName.uppercased())
                                        .font(.system(size: 14, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    if let percent = allocation {
                                        Text("\(percent, specifier: "%.1f")%")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(stockWithOwners.stock.symbol)
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
    
    private func getAllocation(for userId: String) -> Double? {
        let portfolio = appState.sheetsService.getPortfolio(for: userId)
        let allocations = appState.portfolioManager.getAllocations(
            portfolio: portfolio,
            prices: appState.priceService.prices
        )
        return allocations.first { $0.symbol == stockWithOwners.stock.symbol }?.percent
    }
}

// MARK: - Preview
#Preview {
    StocksView()
        .environmentObject(AppState.shared)
}
