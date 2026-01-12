import SwiftUI

/// AI-generated fact card showing stock summary, tags, and metadata
struct StockFactCardView: View {
    let stockFact: StockFact?
    
    var body: some View {
        if let fact = stockFact, !fact.summary.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("🤖")
                        .font(.system(size: 16))
                    Text("AI FACT CARD")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(3)
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.horizontal)
                
                // Content card
                VStack(alignment: .leading, spacing: 8) {
                    // Summary
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
                                    .cornerRadius(4)
                                    .foregroundColor(Color(white: 0.5))
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // Founded / HQ metadata
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
            // No AI data placeholder
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
}
