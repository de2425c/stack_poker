import SwiftUI

enum DayOfWeekStatsPeriod: String, CaseIterable, Identifiable {
    case month = "Past Month"
    case year = "Past Year"
    var id: String { rawValue }
}

struct DayOfWeekStatsBarChart: View {
    let sessions: [Session]
    let period: DayOfWeekStatsPeriod

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let hoursColor = Color(UIColor(red: 38/255, green: 155/255, blue: 255/255, alpha: 1.0))
    private let profitColor = Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0))

    private struct DayStats {
        var hours: Double = 0
        var profit: Double = 0
    }

    private var statsByDay: [DayStats] {
        var stats = Array(repeating: DayStats(), count: 7)
        let calendar = Calendar.current
        let now = Date()
        let filtered: [Session] = {
            switch period {
            case .month:
                let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return sessions.filter { $0.startDate >= oneMonthAgo }
            case .year:
                let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
                return sessions.filter { $0.startDate >= oneYearAgo }
            }
        }()
        for session in filtered {
            let weekday = calendar.component(.weekday, from: session.startDate) - 1 // 0 = Sunday
            if weekday >= 0 && weekday < 7 {
                stats[weekday].hours += session.hoursPlayed
                stats[weekday].profit += session.profit
            }
        }
        return stats
    }

    var body: some View {
        GeometryReader { geometry in
            let maxHours = statsByDay.map { $0.hours }.max() ?? 1
            let maxProfit = statsByDay.map { abs($0.profit) }.max() ?? 1
            let barMaxHeight = geometry.size.height * 0.7
            let groupWidth = geometry.size.width / 7
            let barWidth = groupWidth * 0.35

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        let stats = statsByDay[i]
                        VStack(spacing: 2) {
                            // Profit bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(profitColor)
                                .frame(width: barWidth, height: max(2, barMaxHeight * CGFloat(abs(stats.profit) / maxProfit)))
                                .opacity(stats.profit == 0 ? 0.15 : 1)
                                .overlay(
                                    Text(stats.profit == 0 ? "" : "$\(Int(stats.profit))")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .offset(y: -10)
                                )
                            // Hours bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(hoursColor)
                                .frame(width: barWidth, height: max(2, barMaxHeight * CGFloat(stats.hours / maxHours)))
                                .opacity(stats.hours == 0 ? 0.15 : 1)
                                .overlay(
                                    Text(stats.hours == 0 ? "" : String(format: "%.1fh", stats.hours))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .offset(y: -10)
                                )
                        }
                        .frame(width: groupWidth, height: barMaxHeight, alignment: .bottom)
                    }
                }
                .frame(height: barMaxHeight)
                // Day labels
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                            .frame(width: groupWidth)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(height: 160)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.18))
        )
    }
} 
