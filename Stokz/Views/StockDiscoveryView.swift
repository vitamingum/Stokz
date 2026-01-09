import SwiftUI

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
                    headerSection
                    
                    if showAddButton {
                        addButton
                    }
                    
                    factCardSection
                    
                    similarStocksSection
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(ticker)
                .font(.system(size: 48, weight: .black))
                .foregroundColor(.white)
            
            if let fact = stockFact {
                Text(fact.company)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.5))
            } else {
                Text("Stock data not available")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.4))
            }
        }
        .padding(.top, 20)
    }
    
    private var addButton: some View {
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
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isInPortfolio || showAddedConfirmation ? Color.green : Color.white)
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .disabled(isAdding || isInPortfolio)
        .opacity(isInPortfolio ? 0.7 : 1.0)
    }
    
    @ViewBuilder
    private var factCardSection: some View {
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
                    
                    if let tags = fact.tags, !tags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(tags.prefix(4), id: \.self) { tag in
                                Text(tag.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(4)
                                    .foregroundColor(Color(white: 0.5))
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    HStack(spacing: 16) {
                        if let founded = fact.founded {
                            Text("EST. \(founded)")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundColor(Color(white: 0.4))
                        }
                        if let hq = fact.headquarters {
                            Text(hq.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundColor(Color(white: 0.4))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(Color(white: 0.08))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        } else {
            VStack(spacing: 8) {
                Text("📊")
                    .font(.system(size: 32))
                Text("NO AI DATA")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Color(white: 0.3))
                Text("Limited data available for this stock")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    @ViewBuilder
    private var similarStocksSection: some View {
        if !similarStocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("🔗")
                        .font(.system(size: 16))
                    Text("SIMILAR STOCKS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(3)
                        .foregroundColor(Color(white: 0.5))
                    
                    Spacer()
                    
                    Text("TAP TO EXPLORE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.3))
                }
                .padding(.horizontal)
                
                VStack(spacing: 0) {
                    ForEach(similarStocks, id: \.ticker) { item in
                        NavigationLink(destination: StockDiscoveryView(ticker: item.ticker)) {
                            SimilarStockRow(ticker: item.ticker, fact: item.fact, score: item.score)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if item.ticker != similarStocks.last?.ticker {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color(white: 0.12))
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(white: 0.08))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
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

struct SimilarStockRow: View {
    let ticker: String
    let fact: StockFact?
    let score: Double
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticker)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                if let fact = fact {
                    Text(fact.company)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(Int(score * 100))%")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(white: 0.3))
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(white: 0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        StockDiscoveryView(ticker: "AAPL")
            .environmentObject(AppState.shared)
    }
}
