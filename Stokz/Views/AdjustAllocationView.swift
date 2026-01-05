import SwiftUI

/// AdjustAllocationView allows users to adjust the allocation percentage of a stock
/// LIQUID DEATH STYLE - Bold Black & White
struct AdjustAllocationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let symbol: String
    
    @State private var targetPercent: Double = 0
    @State private var isSaving = false
    
    private var currentAllocation: Double {
        appState.getAllocations().first { $0.symbol == symbol }?.percent ?? 0
    }
    
    private var stock: Stock? {
        appState.priceService.stocks[symbol]
    }
    
    private var otherAllocations: [(symbol: String, percent: Double)] {
        let allocations = appState.getAllocations().filter { $0.symbol != symbol }
        let remainingPercent = 100 - targetPercent
        let totalOther = allocations.reduce(0) { $0 + $1.percent }
        
        return allocations.map { alloc in
            let scaledPercent = totalOther > 0 ? (alloc.percent / totalOther) * remainingPercent : remainingPercent / Double(allocations.count)
            return (symbol: alloc.symbol, percent: scaledPercent)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Stock Info Header
                    stockHeader
                    
                    // Allocation Slider
                    allocationSlider
                    
                    // Preview of other allocations
                    allocationPreview
                    
                    Spacer()
                    
                    // Save Button
                    Button(action: saveAllocation) {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("APPLY CHANGES")
                                .font(.system(size: 16, weight: .black))
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 18)
                    .background(abs(targetPercent - currentAllocation) < 0.1 ? Color(white: 0.3) : Color.white)
                    .foregroundColor(.black)
                    .disabled(isSaving || abs(targetPercent - currentAllocation) < 0.1)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADJUST")
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        Task {
                            await appState.removeStock(symbol: symbol)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                    }
                }
            }
            .onAppear {
                targetPercent = currentAllocation
            }
        }
    }
    
    // MARK: - Stock Header (Liquid Death Style)
    private var stockHeader: some View {
        VStack(spacing: 12) {
            Text(symbol)
                .font(.system(size: 32, weight: .black))
                .tracking(4)
                .foregroundColor(.white)
            
            if let stock = stock {
                HStack(spacing: 12) {
                    Text(stock.currentPrice.asCurrency)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        Image(systemName: stock.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                        Text("\(stock.priceChangePercent, specifier: "%.2f")%")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(stock.isPositive ? .white : Color(white: 0.4))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.1))
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Allocation Slider (Liquid Death Style)
    private var allocationSlider: some View {
        VStack(spacing: 16) {
            Text("TARGET ALLOCATION")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundColor(Color(white: 0.5))
            
            Text("\(targetPercent, specifier: "%.0f")%")
                .font(.system(size: 64, weight: .black))
                .foregroundColor(.white)
            
            Slider(value: $targetPercent, in: 1...99, step: 1)
                .tint(.white)
                .padding(.horizontal)
            
            HStack {
                Text("1%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.4))
                Spacer()
                Text("99%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.horizontal)
            
            // Quick adjustment buttons
            HStack(spacing: 12) {
                ForEach([10, 25, 33, 50], id: \.self) { percent in
                    Button(action: { targetPercent = Double(percent) }) {
                        Text("\(percent)%")
                            .font(.system(size: 14, weight: .black))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                abs(targetPercent - Double(percent)) < 0.5
                                    ? Color.white
                                    : Color(white: 0.15)
                            )
                            .foregroundColor(
                                abs(targetPercent - Double(percent)) < 0.5
                                    ? .black
                                    : .white
                            )
                    }
                }
            }
        }
        .padding()
        .background(Color.black)
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Allocation Preview (Liquid Death Style)
    private var allocationPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESULTING ALLOCATIONS")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundColor(Color(white: 0.5))
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                // This stock
                HStack {
                    Text(symbol)
                        .font(.system(size: 16, weight: .black))
                        .tracking(1)
                        .foregroundColor(.black)
                    Spacer()
                    Text("\(targetPercent, specifier: "%.0f")%")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.black)
                }
                .padding()
                .background(Color.white)
                
                // Other stocks
                ForEach(otherAllocations, id: \.symbol) { alloc in
                    HStack {
                        Text(alloc.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(alloc.percent, specifier: "%.0f")%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    
                    if alloc.symbol != otherAllocations.last?.symbol {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(white: 0.15))
                            .padding(.leading)
                    }
                }
            }
            .background(Color(white: 0.1))
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
    
    // MARK: - Save
    private func saveAllocation() {
        isSaving = true
        
        Task {
            await appState.adjustAllocation(symbol: symbol, targetPercent: targetPercent)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Preview
#Preview {
    AdjustAllocationView(symbol: "AAPL")
        .environmentObject(AppState.shared)
}
