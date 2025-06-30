import SwiftUI
import Charts

struct DailyTimeMoneyBarGraph: View {
    let sessions: [Session]
    @State private var selectedView: TimeView = .monthly
    
    enum TimeView: String, CaseIterable {
        case monthly = "Monthly"
        case yearly = "Yearly"
    }
    
    private var dataPoints: [DayOfWeekDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedView {
        case .monthly:
            // Get last 30 days
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return generateDayOfWeekDataPoints(from: thirtyDaysAgo, to: now)
        case .yearly:
            // Get last 12 months
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return generateDayOfWeekDataPoints(from: oneYearAgo, to: now)
        }
    }
    
    private func generateDayOfWeekDataPoints(from startDate: Date, to endDate: Date) -> [DayOfWeekDataPoint] {
        let calendar = Calendar.current
        
        // Filter sessions within the date range
        let filteredSessions = sessions.filter { session in
            session.startDate >= startDate && session.startDate <= endDate
        }
        
        // Group sessions by day of week
        var dayOfWeekStats: [Int: (profit: Double, hours: Double, sessionCount: Int)] = [:]
        
        for session in filteredSessions {
            let dayOfWeek = calendar.component(.weekday, from: session.startDate)
            // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
            // We want: 0 = Monday, 1 = Tuesday, ..., 6 = Sunday
            // Formula: (dayOfWeek - 2 + 7) % 7
            let adjustedDayOfWeek = (dayOfWeek - 2 + 7) % 7
            
            let current = dayOfWeekStats[adjustedDayOfWeek] ?? (profit: 0, hours: 0, sessionCount: 0)
            dayOfWeekStats[adjustedDayOfWeek] = (
                profit: current.profit + session.profit,
                hours: current.hours + session.hoursPlayed,
                sessionCount: current.sessionCount + 1
            )
        }
        
        // Create data points for all days of the week
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var dataPoints: [DayOfWeekDataPoint] = []
        
        for i in 0..<7 {
            let stats = dayOfWeekStats[i] ?? (profit: 0, hours: 0, sessionCount: 0)
            dataPoints.append(DayOfWeekDataPoint(
                dayOfWeek: i,
                dayName: dayNames[i],
                profit: stats.profit,
                hours: stats.hours,
                sessionCount: stats.sessionCount
            ))
            
            // Debug: Print stats for each day
            print("DEBUG: \(dayNames[i]) - Hours: \(stats.hours), Profit: \(stats.profit), Sessions: \(stats.sessionCount)")
        }
        
        return dataPoints
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Activity by Day of Week")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // View selector
                HStack(spacing: 8) {
                    ForEach(TimeView.allCases, id: \.self) { view in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedView = view
                            }
                        }) {
                            Text(view.rawValue)
                                .font(.system(size: 12, weight: selectedView == view ? .semibold : .regular))
                                .foregroundColor(selectedView == view ? .white : .gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedView == view ? Color.gray.opacity(0.3) : Color.clear)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Chart
            if dataPoints.allSatisfy({ $0.hours == 0 }) {
                Text("No data available")
                    .foregroundColor(.gray)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    // Legend
                    legendView
                    
                    // Chart
                    chartView
                }
            }
            
            // Summary stats
            summaryStatsView
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Computed Properties
    
    private var legendView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
                Text("Hours")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
                Text("Profit ($)")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    private var chartView: some View {
        let maxHours = dataPoints.map { $0.hours }.max() ?? 1
        let maxProfit = dataPoints.map { $0.profit }.max() ?? 1
        
        return Chart {
            // Grid lines (including negative values)
            ForEach([-100, -75, -50, -25, 0, 25, 50, 75, 100], id: \.self) { gridValue in
                RuleMark(y: .value("Grid", Double(gridValue)))
                    .foregroundStyle(Color.gray.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            
            ForEach(dataPoints, id: \.dayOfWeek) { point in
                // Hours bar (normalized to 0-100)
                BarMark(
                    x: .value("Day", point.dayName),
                    y: .value("Hours", maxHours > 0 ? (point.hours / maxHours) * 100 : 0),
                    width: .fixed(20)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.cyan.opacity(0.6)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
                .position(by: .value("Metric", "Hours"))
                
                // Profit bar (normalized to 0-100)
                BarMark(
                    x: .value("Day", point.dayName),
                    y: .value("Profit", maxProfit > 0 ? (point.profit / maxProfit) * 100 : 0),
                    width: .fixed(20)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green.opacity(0.8), Color.mint.opacity(0.6)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
                .position(by: .value("Metric", "Profit"))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                if let dayName = value.as(String.self) {
                    AxisValueLabel {
                        Text(dayName.prefix(3))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let normalizedValue = value.as(Double.self) {
                    AxisValueLabel {
                        HStack(spacing: 4) {
                            Text("$\(Int((normalizedValue / 100) * maxProfit))")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                            Text("|")
                                .font(.system(size: 9))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("\(Int((normalizedValue / 100) * maxHours))h")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .frame(height: 200)
        .padding(.horizontal, 20)
    }
    
    private var summaryStatsView: some View {
        HStack(spacing: 20) {
            let totalHours = dataPoints.reduce(0) { $0 + $1.hours }
            let totalProfit = dataPoints.reduce(0) { $0 + $1.profit }
            let bestDay = dataPoints.max(by: { $0.hours < $1.hours })?.dayName.prefix(3) ?? ""
            
            SummaryStat(
                title: "Total Hours",
                value: totalHours,
                suffix: "h",
                color: .blue
            )
            
            SummaryStat(
                title: "Total Profit",
                value: totalProfit,
                prefix: "$",
                color: .green
            )
            
            SummaryStat(
                title: "Best Day",
                value: 0, // We'll calculate this
                suffix: String(bestDay),
                color: .orange
            )
        }
        .padding(.horizontal, 20)
    }
}

struct DayOfWeekDataPoint {
    let dayOfWeek: Int // 0 = Monday, 6 = Sunday
    let dayName: String
    let profit: Double
    let hours: Double
    let sessionCount: Int
}

struct SummaryStat: View {
    let title: String
    let value: Double
    var prefix: String = ""
    var suffix: String = ""
    let color: Color
    
    private var formattedValue: String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(formattedValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 
