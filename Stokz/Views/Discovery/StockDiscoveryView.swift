import SwiftUI

/// Universal Stock Discovery View - shows stock details with infinite exploration
/// Use this anywhere a user taps on a stock to see details and similar stocks
struct StockDiscoveryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var isAdding = false
    @State private var showAddedConfirmation = false
    
    let ticker: String
    let showAddButton: Bool
    let onAdd: ((String) -> Void)?
    
    init(ticker: String, showAddButton: Bool = true, onAdd: ((String) -> Void)? = nil) {
        self.ticker = ticker
        self.showAddButton = showAddButton
        self.onAdd = onAdd
    }
    
    private var stockFact: StockFact? {
        StockDataService.shared.getFact(ticker: ticker)
    }
    
    private var similarStocks: [(ticker: String, score: Double, fact: StockFact?)] {
        StockDataService.shared.findSimilar(to: ticker, limit: 5)
    }
    
    private var isInPortfolio: Bool {
        appState.currentUserPortfolio?.holdings.contains(where: { $0.symbol == ticker }) ?? false
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header with ticker and company name
                    StockHeaderView(ticker: ticker, stockFact: stockFact)
                    
                    // ADD TO PORTFOLIO Button (optional)
                    if showAddButton {
                        AddToPortfolioButton(
                            isAdding: isAdding,
                            showAddedConfirmation: showAddedConfirmation,
                            isInPortfolio: isInPortfolio,
                            action: addToPortfolio
                        )
                    }
                    
                    // AI Fact Card or placeholder
                    StockFactCardView(stockFact: stockFact)
                    
                    // Similar Stocks Section
                    SimilarStocksSection(similarStocks: similarStocks)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func addToPortfolio() {
        guard !isInPortfolio else { return }
        
        isAdding = true
        
        Task {
            if let onAdd = onAdd {
                onAdd(ticker)
            } else {
                await appState.addStock(symbol: ticker)
            }
            isAdding = false
            showAddedConfirmation = true
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        StockDiscoveryView(ticker: "AAPL")
            .environmentObject(AppState.shared)
    }
}
