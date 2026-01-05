import SwiftUI
import Charts

/// PerformanceChartView displays net worth over time using Swift Charts
/// LIQUID DEATH STYLE - Bold Black & White
struct PerformanceChartView: View {
    @EnvironmentObject var appState: AppState
    
    let userId: String
    var timeRange: TimeRange = .oneMonth
    
    private var chartData: [ChartDataPoint] {
        appState.getChartData(for: userId, range: timeRange)
    }
    
    private var minValue: Double {
        chartData.map { $0.value }.min() ?? 0
    }
    
    private var maxValue: Double {
        chartData.map { $0.value }.max() ?? 100_000
    }
    
    private var isPositive: Bool {
        guard let first = chartData.first?.value,
              let last = chartData.last?.value else {
            return true
        }
        return last >= first
    }
    
    private var percentChange: Double {
        guard let first = chartData.first?.value,
              let last = chartData.last?.value,
              first > 0 else {
            return 0
        }
        return ((last - first) / first) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if chartData.isEmpty {
                emptyChartView
            } else {
                // Performance Summary
                HStack {
                    Text(timeRange.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(Color(white: 0.5))
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(percentChange, specifier: "%+.2f")%")
                            .font(.system(size: 12, weight: .black))
                    }
                    .foregroundColor(isPositive ? .white : Color(white: 0.4))
                }
                
                // Chart (B&W Style)
                Chart(chartData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Net Worth", point.value)
                    )
                    .foregroundStyle(isPositive ? Color.white : Color(white: 0.5))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Net Worth", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                (isPositive ? Color.white : Color(white: 0.5)).opacity(0.2),
                                (isPositive ? Color.white : Color(white: 0.5)).opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: minValue * 0.95...maxValue * 1.05)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color(white: 0.2))
                        AxisValueLabel(format: .dateTime.month().day())
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color(white: 0.2))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(doubleValue.asCompactCurrency)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(white: 0.4))
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var emptyChartView: some View {
        VStack(spacing: 12) {
            Text("📊")
                .font(.system(size: 40))
            
            Text("NO DATA YET")
                .font(.system(size: 14, weight: .black))
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
            
            Text("PERFORMANCE DATA APPEARS\nAFTER DAILY SNAPSHOTS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(Color(white: 0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Standalone Performance View
struct PerformanceView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedTimeRange: TimeRange = .oneMonth
    @State private var selectedUserId: String?
    
    private var currentUserId: String {
        selectedUserId ?? appState.authService.currentUser?.id ?? ""
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // User Selector (if viewing others)
                if appState.sheetsService.users.count > 1 {
                    userSelector
                }
                
                // Time Range Picker
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Chart
                PerformanceChartView(
                    userId: currentUserId,
                    timeRange: selectedTimeRange
                )
                .frame(height: 250)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Performance")
        }
    }
    
    private var userSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(appState.sheetsService.users) { user in
                    let isSelected = currentUserId == user.id
                    
                    Button(action: { selectedUserId = user.id }) {
                        HStack(spacing: 6) {
                            UserAvatarView(user: user, size: 24)
                            Text(user.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Multi-User Comparison Chart
struct ComparisonChartView: View {
    @EnvironmentObject var appState: AppState
    
    var timeRange: TimeRange = .oneMonth
    
    private var allChartData: [(userId: String, userName: String, data: [ChartDataPoint], color: Color)] {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .cyan]
        
        return appState.sheetsService.users.enumerated().compactMap { index, user in
            let data = appState.getChartData(for: user.id, range: timeRange)
            guard !data.isEmpty else { return nil }
            return (
                userId: user.id,
                userName: user.displayName,
                data: data,
                color: colors[index % colors.count]
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allChartData.isEmpty {
                Text("No performance data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Legend
                HStack(spacing: 16) {
                    ForEach(allChartData, id: \.userId) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.userName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Chart
                Chart {
                    ForEach(allChartData, id: \.userId) { item in
                        ForEach(item.data) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Net Worth", point.value),
                                series: .value("User", item.userName)
                            )
                            .foregroundStyle(item.color)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(doubleValue.asCompactCurrency)
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    PerformanceChartView(userId: "user1", timeRange: .oneMonth)
        .frame(height: 200)
        .padding()
        .environmentObject(AppState.shared)
}
