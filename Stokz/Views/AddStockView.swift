import SwiftUI

/// AddStockView allows users to search and add stocks to their portfolio
/// LIQUID DEATH STYLE - Bold Black & White
struct AddStockView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var llmService = LocalLLMService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [StockSearchResult] = []
    @State private var isSearching = false
    @State private var selectedStock: StockSearchResult?
    @State private var isAdding = false
    
    // Popular stocks for quick selection
    private let popularStocks = [
        ("AAPL", "Apple"),
        ("GOOGL", "Alphabet"),
        ("MSFT", "Microsoft"),
        ("TSLA", "Tesla"),
        ("NVDA", "NVIDIA"),
        ("AMZN", "Amazon"),
        ("META", "Meta"),
        ("NFLX", "Netflix")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Search Results
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("SEARCH RESULTS")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(3)
                                    .foregroundColor(Color(white: 0.5))
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                
                                ForEach(searchResults) { result in
                                    stockRow(symbol: result.symbol, name: result.description, isResult: true)
                                }
                            }
                        }
                        
                        // Popular Stocks
                        if searchText.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("POPULAR STOCKS")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(3)
                                    .foregroundColor(Color(white: 0.5))
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                
                                ForEach(popularStocks, id: \.0) { symbol, name in
                                    stockRow(symbol: symbol, name: name, isResult: false)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "SEARCH STOCKS")
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD STOCK")
                        .font(.system(size: 18, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                }
            }
            .onChange(of: searchText) { _, newValue in
                Task {
                    await performSearch(query: newValue)
                }
            }
        }
    }
    
    @ViewBuilder
    private func stockRow(symbol: String, name: String, isResult: Bool) -> some View {
        Button(action: { addStock(symbol) }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(symbol)
                        .font(.system(size: 18, weight: .black))
                        .tracking(1)
                        .foregroundColor(.white)
                    Text(name.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(Color(white: 0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isAlreadyOwned(symbol) {
                    Text("OWNED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.3))
                } else if isAdding && selectedStock?.symbol == symbol {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .disabled(isAdding || isAlreadyOwned(symbol))
        
        Rectangle()
            .frame(height: 1)
            .foregroundColor(Color(white: 0.15))
    }
    
    // MARK: - Search
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Debounce search
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        guard query == searchText else { return }
        
        isSearching = true
        
        do {
            searchResults = try await appState.priceService.searchStocks(query: query)
        } catch {
            searchResults = []
        }
        
        isSearching = false
    }
    
    // MARK: - Add Stock
    private func addStock(_ symbol: String) {
        guard !isAlreadyOwned(symbol) else { return }
        
        selectedStock = StockSearchResult(symbol: symbol, description: "", type: "")
        isAdding = true
        
        Task {
            await appState.addStock(symbol: symbol)
            isAdding = false
            dismiss()
        }
    }
    
    // MARK: - Check Ownership
    private func isAlreadyOwned(_ symbol: String) -> Bool {
        appState.currentUserPortfolio?.holdings.contains { $0.symbol == symbol } ?? false
    }
}

// MARK: - Preview
#Preview {
    AddStockView()
        .environmentObject(AppState.shared)
}
