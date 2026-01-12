import SwiftUI

/// Section showing similar stocks with navigation links
struct SimilarStocksSection: View {
    let similarStocks: [(ticker: String, score: Double, fact: StockFact?)]
    
    var body: some View {
        if !similarStocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
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
                
                // Stock list
                VStack(spacing: 0) {
                    ForEach(similarStocks, id: \.ticker) { item in
                        NavigationLink(destination: StockDiscoveryView(ticker: item.ticker)) {
                            SimilarStockRow(
                                ticker: item.ticker,
                                fact: item.fact,
                                score: item.score
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Divider (except for last item)
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
}

/// Single row showing a similar stock
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
            
            // Match percentage
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
