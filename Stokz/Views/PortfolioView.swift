import SwiftUI

// Simple wrapper for sheet(item:) pattern
struct DiscoveryItem: Identifiable {
    let id = UUID()
    let ticker: String
}

/// PortfolioView shows the user's portfolio with stocks, allocations, and live prices
/// LIQUID DEATH STYLE - Bold Black & White
struct PortfolioView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddStock = false
    @State private var selectedStock: String?
    @State private var showAdjustAllocation = false
    @State private var discoveryItem: DiscoveryItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Pure black background
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Net Worth Header
                        netWorthHeader
                        
                        // Holdings List
                        if let portfolio = appState.currentUserPortfolio, !portfolio.holdings.isEmpty {
                            holdingsList
                        } else {
                            emptyStateView
                        }
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PORTFOLIO")
                        .font(.system(size: 18, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddStock = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { Task { await appState.rebalanceEqually() } }) {
                            Label("REBALANCE EQUALLY", systemImage: "arrow.triangle.2.circlepath")
                        }
                        
                        Button(action: { Task { await appState.recordSnapshot() } }) {
                            Label("RECORD SNAPSHOT", systemImage: "camera")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showAddStock) {
                AddStockView()
            }
            .sheet(isPresented: $showAdjustAllocation) {
                if let symbol = selectedStock {
                    AdjustAllocationView(symbol: symbol)
                }
            }
            .sheet(item: $discoveryItem) { item in
                let _ = print("🔮 [Portfolio] Sheet opening for ticker: \(item.ticker)")
                NavigationStack {
                    StockDiscoveryView(ticker: item.ticker, showAddButton: false)
                        .environmentObject(appState)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("DONE") {
                                    discoveryItem = nil
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            }
                        }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .preferredColorScheme(.dark)
            }
            .refreshable {
                await appState.loadAllData()
            }
        }
    }
    
    // MARK: - Net Worth Header (Liquid Death Style)
    private var netWorthHeader: some View {
        VStack(spacing: 12) {
            Text("NET WORTH")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundColor(Color(white: 0.5))
            
            // Net Worth (no emoji)
            Text(appState.getNetWorth().asCurrency)
                .font(.system(size: 48, weight: .black))
                .foregroundColor(.white)
            
            // Profit/Loss
            if let portfolio = appState.currentUserPortfolio {
                let profitLoss = portfolio.totalProfitLoss(prices: appState.priceService.prices)
                let profitLossPercent = portfolio.totalProfitLossPercent(prices: appState.priceService.prices)
                let isPositive = profitLoss >= 0
                
                HStack(spacing: 6) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("\(profitLoss.asSignedCurrency) (\(profitLossPercent, specifier: "%+.2f")%)")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(1)
                }
                .foregroundColor(isPositive ? .white : Color(white: 0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.black)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.2)),
            alignment: .bottom
        )
    }
    
    // MARK: - Holdings List (Liquid Death Style)
    private var holdingsList: some View {
        // Rank holdings by daily change percent (best first)
        let allocations = appState.getAllocations()
        let sortedAllocations = allocations.sorted { a, b in
            let aChange = appState.priceService.stocks[a.symbol]?.priceChangePercent ?? 0
            let bChange = appState.priceService.stocks[b.symbol]?.priceChangePercent ?? 0
            return aChange > bChange
        }
        let totalHoldings = sortedAllocations.count
        
        return LazyVStack(spacing: 0) {
            // Cash row (always first)
            if let portfolio = appState.currentUserPortfolio {
                cashRow(cashBalance: portfolio.cashBalance, totalValue: appState.getNetWorth())
            }
            
            ForEach(Array(sortedAllocations.enumerated()), id: \.element.symbol) { index, allocation in
                let rank = index + 1
                let stock = appState.priceService.stocks[allocation.symbol]
                let holding = appState.currentUserPortfolio?.holdings.first(where: { $0.symbol == allocation.symbol })
                
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        // Tappable area for discovery (stock info)
                        Button(action: {
                            print("🔮 [Portfolio] Tapped stock: \(allocation.symbol)")
                            discoveryItem = DiscoveryItem(ticker: allocation.symbol)
                            print("🔮 [Portfolio] Set discoveryItem for \(allocation.symbol)")
                        }) {
                            HStack(spacing: 8) {
                                // Stock info (CENTER)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(allocation.symbol)
                                            .font(.system(size: 16, weight: .black))
                                            .tracking(1)
                                            .foregroundColor(.white)
                                        
                                        // Daily change
                                        if let stock = stock {
                                            Text("\(stock.priceChangePercent >= 0 ? "+" : "")\(String(format: "%.1f", stock.priceChangePercent))%")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(stock.priceChangePercent >= 0 ? .green : .red)
                                        }
                                    }
                                    
                                    if let stock = stock, let holding = holding {
                                        // Show: shares @ current price (entry: $X)
                                        Text("\(String(format: "%.2f", holding.shares)) @ \(stock.currentPrice.asCurrency)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(white: 0.6))
                                        Text("entry: \(holding.entryPrice.asCurrency)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Color(white: 0.4))
                                    } else if let stock = stock {
                                        Text(stock.currentPrice.asCurrency)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        // Value and allocation
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(allocation.value.asCurrency)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("\(allocation.percent, specifier: "%.0f")%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(white: 0.5))
                        }
                        .frame(minWidth: 70, alignment: .trailing)
                        
                        // +/- buttons (RIGHT)
                        HStack(spacing: 4) {
                            Button(action: {
                                Task { await appState.adjustAllocation(symbol: allocation.symbol, amountDelta: -5000) }
                            }) {
                                Text("-")
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color(white: 0.15))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                Task { await appState.adjustAllocation(symbol: allocation.symbol, amountDelta: 5000) }
                            }) {
                                Text("+")
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color(white: 0.15))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(white: 0.15))
                        .padding(.leading)
                }
                .background(Color.black)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await appState.removeStock(symbol: allocation.symbol) }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Cash Row (No X or +/- buttons)
    private func cashRow(cashBalance: Double, totalValue: Double) -> some View {
        let percent = totalValue > 0 ? (cashBalance / totalValue) * 100 : 0
        
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Cash Emoji (LEFT)
                Text("💵")
                    .font(.system(size: 22))
                    .frame(width: 32)
                
                // Cash info (CENTER)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CASH")
                        .font(.system(size: 16, weight: .black))
                        .tracking(1)
                        .foregroundColor(.white)
                    
                    Text("Available for purchase")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                }
                
                Spacer()
                
                // Value and allocation
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cashBalance.asCurrency)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(percent, specifier: "%.0f")%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                }
                .frame(minWidth: 70, alignment: .trailing)
                
                // Spacer to align with stock rows (where +/- buttons would be)
                Color.clear
                    .frame(width: 76, height: 36) // Width of two 36pt buttons + 4pt spacing
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.15))
                .padding(.leading)
        }
        .background(Color.black)
    }
    
    // MARK: - Empty State (Liquid Death Style)
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("💀")
                .font(.system(size: 80))
            
            Text("NO STOCKS")
                .font(.system(size: 24, weight: .black))
                .tracking(4)
                .foregroundColor(.white)
            
            Text("ADD YOUR FIRST STOCK TO\nSTART THE CARNAGE")
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
            
            Button(action: { showAddStock = true }) {
                Text("ADD STOCK")
                    .font(.system(size: 16, weight: .black))
                    .tracking(2)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.white)
            }
            .padding(.top, 8)
        }
        .padding(40)
    }
}

// MARK: - Preview
#Preview {
    PortfolioView()
        .environmentObject(AppState.shared)
}
