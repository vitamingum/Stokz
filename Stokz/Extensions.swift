import SwiftUI

/// Extensions for formatting and UI helpers
extension Double {
    /// Format as currency string
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
    
    /// Format as signed currency string (+$100.00 or -$100.00)
    var asSignedCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+$"
        formatter.negativePrefix = "-$"
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
    
    /// Format as compact currency (e.g., $100K, $1.2M)
    var asCompactCurrency: String {
        let absValue = abs(self)
        let sign = self < 0 ? "-" : ""
        
        if absValue >= 1_000_000 {
            return "\(sign)$\(String(format: "%.1f", absValue / 1_000_000))M"
        } else if absValue >= 1_000 {
            return "\(sign)$\(String(format: "%.0f", absValue / 1_000))K"
        } else {
            return "\(sign)$\(String(format: "%.0f", absValue))"
        }
    }
    
    /// Format as percentage
    var asPercent: String {
        String(format: "%.2f%%", self)
    }
    
    /// Format as signed percentage
    var asSignedPercent: String {
        String(format: "%+.2f%%", self)
    }
}

// MARK: - Date Extensions
extension Date {
    /// Format as short date string
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format as time string
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format for charts
    var chartLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}

// MARK: - Color Extensions
extension Color {
    /// Positive/gain color
    static let gain = Color.green
    
    /// Negative/loss color
    static let loss = Color.red
    
    /// Color for profit/loss based on value
    static func profitLoss(_ value: Double) -> Color {
        value >= 0 ? .gain : .loss
    }
}

// MARK: - View Extensions
extension View {
    /// Apply card styling
    func cardStyle() -> some View {
        self
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    /// Hide view conditionally
    @ViewBuilder func hidden(_ shouldHide: Bool) -> some View {
        if shouldHide {
            self.hidden()
        } else {
            self
        }
    }
}

// MARK: - String Extensions
extension String {
    /// Check if string is valid stock symbol
    var isValidStockSymbol: Bool {
        let pattern = "^[A-Z]{1,5}$"
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Array Extensions
extension Array where Element == PortfolioHolding {
    /// Get total value at given prices
    func totalValue(prices: [String: Double]) -> Double {
        reduce(0) { total, holding in
            let price = prices[holding.symbol] ?? holding.entryPrice
            return total + holding.currentValue(at: price)
        }
    }
}

// MARK: - User Extension for Identifiable binding
extension User: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - StockWithOwners Hashable
extension StockWithOwners: Hashable {
    static func == (lhs: StockWithOwners, rhs: StockWithOwners) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
