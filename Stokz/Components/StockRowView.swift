import SwiftUI

/// StockRowView displays a single stock holding with allocation percentage and price movement
/// LIQUID DEATH STYLE - Bold Black & White
struct StockRowView: View {
    let symbol: String
    let allocationPercent: Double
    let stock: Stock?
    var showAllocation: Bool = true
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                // Stock Symbol and Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(symbol)
                        .font(.system(size: 18, weight: .black))
                        .tracking(1)
                        .foregroundColor(.white)
                    
                    if let stock = stock {
                        Text(stockName(for: symbol).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(Color(white: 0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Price and Change
                if let stock = stock {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(stock.currentPrice.asCurrency)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            Image(systemName: stock.isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            
                            Text("\(abs(stock.priceChangePercent), specifier: "%.2f")%")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(stock.isPositive ? .white : Color(white: 0.4))
                    }
                }
                
                // Allocation Percentage
                if showAllocation {
                    Text("\(allocationPercent, specifier: "%.0f")%")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                        .frame(minWidth: 50, alignment: .trailing)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Helper to get company name (simplified)
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

/// Compact stock row for lists (Liquid Death Style)
struct CompactStockRowView: View {
    let symbol: String
    let price: Double
    let changePercent: Double
    
    var isPositive: Bool { changePercent >= 0 }
    
    var body: some View {
        HStack {
            Text(symbol)
                .font(.system(size: 14, weight: .black))
                .tracking(1)
                .foregroundColor(.white)
            
            Spacer()
            
            Text(price.asCurrency)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 2) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text("\(abs(changePercent), specifier: "%.2f")%")
                    .font(.caption)
            }
            .foregroundColor(isPositive ? .green : .red)
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview {
    VStack {
        StockRowView(
            symbol: "AAPL",
            allocationPercent: 33.5,
            stock: Stock(
                symbol: "AAPL",
                currentPrice: 178.50,
                previousClose: 176.20,
                lastUpdated: Date()
            )
        )
        
        Divider()
        
        StockRowView(
            symbol: "TSLA",
            allocationPercent: 25.2,
            stock: Stock(
                symbol: "TSLA",
                currentPrice: 248.50,
                previousClose: 252.30,
                lastUpdated: Date()
            )
        )
    }
    .padding()
}
