import SwiftUI

/// Add to Portfolio button with loading/success states
struct AddToPortfolioButton: View {
    let isAdding: Bool
    let showAddedConfirmation: Bool
    let isInPortfolio: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
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
}
