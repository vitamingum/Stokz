import SwiftUI

/// Header showing ticker symbol and company name
struct StockHeaderView: View {
    let ticker: String
    let stockFact: StockFact?
    
    var body: some View {
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
}
