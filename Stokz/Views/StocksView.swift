import SwiftUI

/// StocksView shows union of all stocks across all users
/// LIQUID DEATH STYLE - Bold Black & White
struct StocksView: View {
    @EnvironmentObject var appState: AppState
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
                            VStack(spacing: 0) {
                                StockWithOwnersRow(
                                    stockWithOwners: item.stock,
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
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 10) {
                // Stock Info
                HStack {
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
        // Use AI data service for company names
        if let companyName = StockDataService.shared.getCompanyName(ticker: symbol) {
            return companyName
        }
        // Fallback for stocks not in our database
        return symbol
    }
}

// MARK: - Stock Detail View (Liquid Death Style)
struct StockDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let stockWithOwners: StockWithOwners
    
    // Stock fact card data
    private var stockFact: StockFact? {
        let fact = StockDataService.shared.getFact(ticker: stockWithOwners.stock.symbol)
        print("📊 Getting fact for \(stockWithOwners.stock.symbol): \(fact != nil ? "Found" : "Not found")")
        print("📊 Service loaded: \(StockDataService.shared.isLoaded), count: \(StockDataService.shared.stockCount)")
        return fact
    }
    
    // Similar stocks from AI embeddings
    private var similarStocks: [(ticker: String, score: Double, fact: StockFact?)] {
        StockDataService.shared.findSimilar(to: stockWithOwners.stock.symbol, limit: 5)
    }
    
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
                        
                        // AI Fact Card Section
                        // Debug: Show if data loaded
                        Text("Data: \(StockDataService.shared.isLoaded ? "✅ \(StockDataService.shared.stockCount)" : "❌ Not loaded")")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .padding(.horizontal)
                        
                        if let fact = stockFact, !fact.summary.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("🤖")
                                        .font(.system(size: 16))
                                    Text("AI FACT CARD")
                                        .font(.system(size: 12, weight: .bold))
                                        .tracking(3)
                                        .foregroundColor(Color(white: 0.5))
                                }
                                .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(fact.company)
                                        .font(.system(size: 16, weight: .black))
                                        .foregroundColor(.white)
                                    
                                    Text(fact.summary)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(white: 0.7))
                                        .lineSpacing(4)
                                    
                                    // Tags
                                    if let tags = fact.tags, !tags.isEmpty {
                                        HStack(spacing: 8) {
                                            ForEach(tags.prefix(4), id: \.self) { tag in
                                                Text(tag.uppercased())
                                                    .font(.system(size: 9, weight: .bold))
                                                    .tracking(1)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color(white: 0.15))
                                                    .foregroundColor(Color(white: 0.6))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    
                                    // Sector badge
                                    HStack {
                                        Text(fact.sector.uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(2)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.1))
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                    .padding(.top, 4)
                                }
                                .padding()
                                .background(Color(white: 0.08))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                        
                        // Similar Stocks Section (AI-powered) - TAPPABLE
                        if !similarStocks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("✨")
                                        .font(.system(size: 16))
                                    Text("SIMILAR STOCKS")
                                        .font(.system(size: 12, weight: .bold))
                                        .tracking(3)
                                        .foregroundColor(Color(white: 0.5))
                                    Spacer()
                                    Text("AI")
                                        .font(.system(size: 9, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.2))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                                .padding(.horizontal)
                                
                                ForEach(similarStocks, id: \.ticker) { item in
                                    NavigationLink(destination: SimilarStockDetailView(ticker: item.ticker)) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.ticker)
                                                    .font(.system(size: 14, weight: .black))
                                                    .foregroundColor(.white)
                                                if let fact = item.fact {
                                                    Text(fact.company)
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundColor(Color(white: 0.5))
                                                        .lineLimit(1)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // Similarity score
                                            Text("\(Int(item.score * 100))%")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(Color(white: 0.4))
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(Color(white: 0.3))
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 10)
                                        .background(Color(white: 0.08))
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        
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

// MARK: - Similar Stock Detail View (for exploring from recommendations)
struct SimilarStockDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var isAdding = false
    @State private var showAddedConfirmation = false
    
    let ticker: String
    
    private var stockFact: StockFact? {
        StockDataService.shared.getFact(ticker: ticker)
    }
    
    private var similarStocks: [(ticker: String, score: Double, fact: StockFact?)] {
        StockDataService.shared.findSimilar(to: ticker, limit: 5)
    }
    
    // Check if stock is already in portfolio
    private var isInPortfolio: Bool {
        appState.currentUserPortfolio?.holdings.contains(where: { $0.symbol == ticker }) ?? false
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(ticker)
                            .font(.system(size: 48, weight: .black))
                            .foregroundColor(.white)
                        
                        if let fact = stockFact {
                            Text(fact.company)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    .padding(.top, 20)
                    
                    // ADD TO PORTFOLIO Button
                    Button(action: addToPortfolio) {
                        HStack(spacing: 10) {
                            if isAdding {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else if showAddedConfirmation {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                Text("ADDED!")
                                    .font(.system(size: 14, weight: .black))
                                    .tracking(2)
                            } else if isInPortfolio {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("IN PORTFOLIO")
                                    .font(.system(size: 14, weight: .black))
                                    .tracking(2)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                Text("ADD TO PORTFOLIO")
                                    .font(.system(size: 14, weight: .black))
                                    .tracking(2)
                            }
                        }
                        .foregroundColor(isInPortfolio || showAddedConfirmation ? .black : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isInPortfolio || showAddedConfirmation ? Color.green : Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    .disabled(isAdding || isInPortfolio)
                    .opacity(isInPortfolio ? 0.7 : 1.0)
                    
                    // AI Fact Card
                    if let fact = stockFact, !fact.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("🤖")
                                    .font(.system(size: 16))
                                Text("AI FACT CARD")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(3)
                                    .foregroundColor(Color(white: 0.5))
                            }
                            .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(fact.summary)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(white: 0.7))
                                    .lineSpacing(4)
                                
                                // Tags
                                if let tags = fact.tags, !tags.isEmpty {
                                    HStack(spacing: 8) {
                                        ForEach(tags.prefix(4), id: \.self) { tag in
                                            Text(tag.uppercased())
                                                .font(.system(size: 9, weight: .bold))
                                                .tracking(1)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(white: 0.15))
                                                .foregroundColor(Color(white: 0.6))
                                                .cornerRadius(4)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                                
                                // Sector badge
                                if !fact.sector.isEmpty {
                                    Text(fact.sector.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                        .padding(.top, 4)
                                }
                            }
                            .padding()
                            .background(Color(white: 0.08))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Similar Stocks (recursive exploration!)
                    if !similarStocks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("✨")
                                    .font(.system(size: 16))
                                Text("SIMILAR STOCKS")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(3)
                                    .foregroundColor(Color(white: 0.5))
                                Spacer()
                                Text("AI")
                                    .font(.system(size: 9, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.2))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            .padding(.horizontal)
                            
                            ForEach(similarStocks, id: \.ticker) { item in
                                NavigationLink(destination: SimilarStockDetailView(ticker: item.ticker)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.ticker)
                                                .font(.system(size: 14, weight: .black))
                                                .foregroundColor(.white)
                                            if let fact = item.fact {
                                                Text(fact.company)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(Color(white: 0.5))
                                                    .lineLimit(1)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Text("\(Int(item.score * 100))%")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(white: 0.4))
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(white: 0.3))
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                    .background(Color(white: 0.08))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
    
    private func addToPortfolio() {
        isAdding = true
        Task {
            await appState.addStock(symbol: ticker)
            await MainActor.run {
                isAdding = false
                showAddedConfirmation = true
                
                // Reset confirmation after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showAddedConfirmation = false
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    StocksView()
        .environmentObject(AppState.shared)
}
