import SwiftUI

/// Chat-style AI stock screener component
/// Shows input box + results
struct StockScreenerChatView: View {
    @StateObject private var screener = StockScreenerService.shared
    @EnvironmentObject var appState: AppState
    
    @State private var prompt: String = ""
    @State private var showResults = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Divider
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.2))
            
            // Header
            HStack(spacing: 6) {
                Text("🥤")
                    .font(.system(size: 16))
                
                Text("TALL BOY")
                    .font(.system(size: 14, weight: .black))
                    .tracking(2)
                    .foregroundColor(.white)
                
                Text("AI Stock Scout")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                
                Spacer()
                
                if screener.isScreening {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Live feed during screening
            if screener.isScreening {
                liveFeedView
            }
            
            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    // Placeholder
                    if prompt.isEmpty {
                        Text("Ask me to find stocks... moats, memes, AI plays, value traps...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(white: 0.35))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $prompt)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minHeight: 60, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($isFocused)
                }
                .background(Color(white: 0.1))
                .cornerRadius(12)
                
                Button(action: submitSearch) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(prompt.isEmpty || screener.isScreening ? Color(white: 0.3) : .white)
                }
                .disabled(prompt.isEmpty || screener.isScreening)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            // Results
            if !screener.results.isEmpty {
                resultsView
            }
            
            // Error
            if let error = screener.lastError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.black)
    }
    
    // MARK: - Live Feed View
    
    private var liveFeedView: some View {
        VStack(spacing: 0) {
            // Running top scorers
            if !screener.topScorers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EMERGING LEADERS")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.4))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(screener.topScorers.prefix(8), id: \.ticker) { stock in
                                HStack(spacing: 4) {
                                    Text(stock.ticker)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("\(Int(stock.score))")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(stock.score >= 7 ? Color.green : Color(white: 0.6))
                                        .cornerRadius(4)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(white: 0.15))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            // Activity feed
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(screener.liveFeed.suffix(15)) { item in
                            feedItemView(item)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 120)
                .onChange(of: screener.liveFeed.count) { _, _ in
                    if let last = screener.liveFeed.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(white: 0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
    
    private func feedItemView(_ item: StockScreenerService.FeedItem) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(feedColor(item.type))
                .frame(width: 6, height: 6)
            
            Text(item.message)
                .font(.system(size: 11, weight: item.type == .found ? .bold : .medium, design: .monospaced))
                .foregroundColor(feedColor(item.type))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
    
    private func feedColor(_ type: StockScreenerService.FeedItem.FeedType) -> Color {
        switch type {
        case .system: return Color(white: 0.5)
        case .batch: return Color(white: 0.4)
        case .found: return .green
        case .error: return .red
        }
    }
    
    private func submitSearch() {
        guard !prompt.isEmpty, !screener.isScreening else { return }
        isFocused = false
        Task {
            await screener.screen(prompt: prompt)
        }
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Results header
            HStack(spacing: 4) {
                Text("🥤")
                    .font(.system(size: 12))
                Text("TALL BOY'S PICKS")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1)
                    .foregroundColor(Color(white: 0.5))
                
                Spacer()
                
                Button(action: { 
                    screener.results = []
                    screener.liveFeed = []
                    screener.topScorers = []
                }) {
                    Text("CLEAR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.4))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Stock picks
            ForEach(screener.results) { pick in
                StockPickRow(pick: pick)
            }
        }
    }
}

// MARK: - Stock Pick Row

struct StockPickRow: View {
    let pick: StockPick
    @EnvironmentObject var appState: AppState
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            HStack(alignment: .top, spacing: 12) {
                // Score badge
                Text(String(format: "%.0f", pick.score))
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 32, height: 32)
                    .background(scoreColor)
                    .cornerRadius(6)
                
                // Stock info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pick.ticker)
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                        
                        Text(pick.company)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(white: 0.45))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(white: 0.3))
                    }
                    
                    // Thesis - the key reasoning from the LLM
                    Text(pick.thesis)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(white: 0.7))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            StockPickDetailView(pick: pick)
                .environmentObject(appState)
        }
        
        Rectangle()
            .frame(height: 1)
            .foregroundColor(Color(white: 0.1))
            .padding(.leading, 56)
    }
    
    // Score color based on match quality
    private var scoreColor: Color {
        if pick.score >= 85 {
            return .green
        } else if pick.score >= 70 {
            return Color(red: 0.9, green: 0.8, blue: 0.2) // gold
        } else {
            return .white
        }
    }
}

// MARK: - Stock Pick Detail View

struct StockPickDetailView: View {
    let pick: StockPick
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var detailedThesis: String = ""
    @State private var isLoadingThesis = true
    @State private var isAdding = false
    @State private var showAddedConfirmation = false
    
    private var isInPortfolio: Bool {
        appState.currentUserPortfolio?.holdings.contains(where: { $0.symbol == pick.ticker }) ?? false
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text(pick.ticker)
                                .font(.system(size: 48, weight: .black))
                                .foregroundColor(.white)
                            
                            Text(pick.company)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(white: 0.5))
                            
                            // Score badge
                            HStack(spacing: 6) {
                                Text("MATCH SCORE")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(Color(white: 0.4))
                                
                                Text(String(format: "%.0f", pick.score))
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(scoreColor)
                                    .cornerRadius(4)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.top, 20)
                        
                        // Add to Portfolio button
                        addButton
                        
                        // AI Thesis section
                        thesisSection
                        
                        // Quick reason from screening
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("📋")
                                    .font(.system(size: 14))
                                Text("QUICK TAKE")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(Color(white: 0.4))
                            }
                            
                            Text(pick.thesis)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(white: 0.6))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(white: 0.08))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadDetailedThesis()
        }
    }
    
    private var thesisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🥤")
                    .font(.system(size: 14))
                Text("TALL BOY'S THESIS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Color(white: 0.4))
            }
            
            if isLoadingThesis {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                    Text("Analyzing...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.08))
                .cornerRadius(12)
            } else {
                Text(detailedThesis)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.8))
                    .lineSpacing(4)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.08))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
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
    
    private var scoreColor: Color {
        if pick.score >= 85 {
            return .green
        } else if pick.score >= 70 {
            return Color(red: 0.9, green: 0.8, blue: 0.2)
        } else {
            return .white
        }
    }
    
    private func loadDetailedThesis() async {
        let thesis = await StockScreenerService.shared.getDetailedThesis(
            ticker: pick.ticker,
            company: pick.company
        )
        await MainActor.run {
            detailedThesis = thesis
            isLoadingThesis = false
        }
    }
    
    private func addToPortfolio() {
        guard !isInPortfolio else { return }
        isAdding = true
        
        Task {
            await appState.addStock(symbol: pick.ticker)
            await MainActor.run {
                isAdding = false
                showAddedConfirmation = true
            }
            
            // Reset confirmation after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showAddedConfirmation = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            StockScreenerChatView()
                .environmentObject(AppState.shared)
        }
    }
}
