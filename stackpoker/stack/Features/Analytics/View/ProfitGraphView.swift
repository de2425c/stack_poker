import SwiftUI

// MARK: - Profit Graph View
struct ProfitGraphView: View {
    let sessions: [Session]
    let selectedTimeRange: Int
    let timeRanges: [String]
    let adjustedProfitCalculator: ((Session) -> Double)?
    
    private func getTimeRangeLabel(for index: Int) -> String {
        guard index >= 0 && index < timeRanges.count else { return "selected period" }
        let range = timeRanges[index]
        switch range {
        case "24H": return "day"
        case "1W": return "week"
        case "1M": return "month"
        case "6M": return "6 months"
        case "1Y": return "year"
        case "All": return "ever"
        default: return "selected period"
        }
    }
    
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessions
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Y-axis grid lines
                VStack(spacing: 0) {
                    ForEach(0..<5) { _ in
                    Spacer()
                        Divider()
                            .background(Color.gray.opacity(0.1))
                    }
                }
                
                // Background gradient
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: Color.white.opacity(0.02), location: 0.3),
                        .init(color: Color.white.opacity(0.03), location: 0.7),
                        .init(color: Color.clear, location: 1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.overlay)
                
                // Profit-only chart (sessions only)
                let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
                
                if !filteredSessions.isEmpty {
                    let sortedSessions = filteredSessions.sorted { $0.startDate < $1.startDate }
                    let cumulativeData = sortedSessions.reduce(into: [(Date, Double)]()) { result, session in
                        let previousTotal = result.last?.1 ?? 0
                        let profit = adjustedProfitCalculator?(session) ?? session.profit
                        result.append((session.startDate, previousTotal + profit))
                    }
                    
                    let totalProfit = cumulativeData.last?.1 ?? 0
                    let chartColor = totalProfit >= 0 ? 
                        Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                        Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
                    
                    // Draw chart path
                    ChartPath(
                        dataPoints: cumulativeData,
                        geometry: geometry,
                        color: chartColor,
                        showFill: true
                    )
                } else {
                    // Empty state message inside the graph area
                    VStack(spacing: 12) {
                        Text("😢")
                            .font(.system(size: 40))
                        Text("You haven't recorded a session in the past \(getTimeRangeLabel(for: selectedTimeRange).lowercased())")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}