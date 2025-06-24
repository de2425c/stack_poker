import SwiftUI

struct DayOfWeekStatsBarChart: View {
    let sessions: [Session]

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let hoursColor = Color(UIColor(red: 38/255, green: 155/255, blue: 255/255, alpha: 1.0))
    private let profitColor = Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0))
    private let negativeColor = Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))

    private struct DayStats {
        var hours: Double = 0
        var profit: Double = 0
    }

    private var statsByDay: [DayStats] {
        var stats = Array(repeating: DayStats(), count: 7)
        let calendar = Calendar.current
        
        for session in sessions {
            let weekday = calendar.component(.weekday, from: session.startDate) - 1 // 0 = Sunday
            if weekday >= 0 && weekday < 7 {
                stats[weekday].hours += session.hoursPlayed
                stats[weekday].profit += session.profit
            }
        }
        return stats
    }
    
    // Calculate totals for the header
    private var totalStats: (hours: Double, profit: Double) {
        let total = statsByDay.reduce((0, 0)) { result, stats in
            (result.0 + stats.hours, result.1 + stats.profit)
        }
        return total
    }
    
    // Find best performing day
    private var bestDay: (day: String, metric: String) {
        let maxProfitIndex = statsByDay.enumerated().max(by: { $0.element.profit < $1.element.profit })?.offset ?? 0
        let maxHoursIndex = statsByDay.enumerated().max(by: { $0.element.hours < $1.element.hours })?.offset ?? 0
        
        if statsByDay[maxProfitIndex].profit > 0 {
            return (dayLabels[maxProfitIndex], "$\(Int(statsByDay[maxProfitIndex].profit))")
        } else if statsByDay[maxHoursIndex].hours > 0 {
            return (dayLabels[maxHoursIndex], "\(String(format: "%.1f", statsByDay[maxHoursIndex].hours))h")
        } else {
            return ("--", "0")
        }
    }

    private func formatAxisProfit(_ value: Double) -> String {
        let num = Int(value / 1000)
        return "\(num)k"
    }
    
    private func formatAxisHours(_ value: Double) -> String {
        return "\(Int(value))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and stats
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity by Day of Week")
                    .font(.plusJakarta(.footnote, weight: .medium))
                    .foregroundColor(.gray)
                
                // Stats row
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Hours")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                        Text("\(String(format: "%.1f", totalStats.hours))h")
                            .font(.plusJakarta(.subheadline, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Profit")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                        Text("$\(Int(totalStats.profit))")
                            .font(.plusJakarta(.subheadline, weight: .bold))
                            .foregroundColor(totalStats.profit >= 0 ? profitColor : negativeColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Best Day")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                        Text("\(bestDay.metric) \(bestDay.day)")
                            .font(.plusJakarta(.subheadline, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Chart
            GeometryReader { geometry in
                let maxHours = max(1, statsByDay.map { $0.hours }.max() ?? 1)
                let maxProfitAbs = max(1, statsByDay.map { abs($0.profit) }.max() ?? 1)

                let yAxisWidth: CGFloat = 40
                let chartContentWidth = geometry.size.width - (yAxisWidth * 2)
                let availableHeight = geometry.size.height - 30 // For x-axis labels

                HStack(spacing: 0) {
                    // Left Y-Axis (Profit)
                    VStack {
                        Text(formatAxisProfit(maxProfitAbs))
                        Spacer()
                        Text(formatAxisProfit(maxProfitAbs / 2))
                        Spacer()
                        Text("$0")
                    }
                    .frame(width: yAxisWidth, height: availableHeight)
                    .font(.plusJakarta(.caption2, weight: .medium))
                    .foregroundColor(.gray)

                    // Chart Bars
                    VStack(spacing: 0) {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                let stats = statsByDay[dayIndex]
                                let dayGroupWidth = (chartContentWidth - (6 * 4)) / 7
                                let barWidth = (dayGroupWidth / 2) - 2

                                HStack(alignment: .bottom, spacing: 2) {
                                    // Hours Bar
                                    Rectangle()
                                        .fill(hoursColor)
                                        .frame(width: barWidth, height: (stats.hours / maxHours) * availableHeight)
                                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))

                                    // Profit Bar
                                    Rectangle()
                                        .fill(stats.profit >= 0 ? profitColor : negativeColor)
                                        .frame(width: barWidth, height: (abs(stats.profit) / maxProfitAbs) * availableHeight)
                                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                                }
                                .frame(width: dayGroupWidth)
                            }
                        }
                        .frame(height: availableHeight)

                        // Day labels (X-Axis)
                        HStack(spacing: 4) {
                            ForEach(dayLabels, id: \.self) { label in
                                Text(label)
                                    .font(.plusJakarta(.caption, weight: .medium))
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 6)
                    }

                    // Right Y-Axis (Hours)
                    VStack {
                        Text(formatAxisHours(maxHours))
                        Spacer()
                        Text(formatAxisHours(maxHours / 2))
                        Spacer()
                        Text("0")
                    }
                    .frame(width: yAxisWidth, height: availableHeight)
                    .font(.plusJakarta(.caption2, weight: .medium))
                    .foregroundColor(.gray)
                }
            }
            .frame(height: 180)
            .padding(.horizontal)
            
            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(hoursColor)
                        .frame(width: 12, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("Hours")
                        .font(.plusJakarta(.caption2, weight: .medium))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(profitColor)
                        .frame(width: 12, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("Profit ($)")
                        .font(.plusJakarta(.caption2, weight: .medium))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            ZStack {
                // Transparent glassy background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.1)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.02))
                
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
} 
