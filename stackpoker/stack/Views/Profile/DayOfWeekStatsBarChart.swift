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
                let maxHours = statsByDay.map { $0.hours }.max() ?? 1
                let maxProfitAbs = statsByDay.map { abs($0.profit) }.max() ?? 1
                let availableHeight = geometry.size.height - 40 // Space for labels
                let dayWidth = geometry.size.width / 7.0
                let barWidth: CGFloat = 12 // Individual bar width
                let barSpacing: CGFloat = 3 // Space between hours and profit bars
                
                VStack(spacing: 0) {
                    // Chart area
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            let stats = statsByDay[dayIndex]
                            
                            VStack(spacing: 0) {
                                // Chart bars area
                                HStack(alignment: .bottom, spacing: barSpacing) {
                                    // Hours bar (blue)
                                    VStack(spacing: 2) {
                                        if stats.hours > 0 {
                                            Text("\(String(format: "%.0f", stats.hours))h")
                                                .font(.plusJakarta(.caption2, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                        }
                                        
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(stops: [
                                                        .init(color: hoursColor.opacity(0.3), location: 0),
                                                        .init(color: hoursColor.opacity(0.7), location: 0.3),
                                                        .init(color: hoursColor, location: 0.8),
                                                        .init(color: hoursColor.opacity(0.9), location: 1)
                                                    ]),
                                                    startPoint: .bottom,
                                                    endPoint: .top
                                                )
                                            )
                                            .frame(
                                                width: barWidth,
                                                height: stats.hours > 0 ? max(4, (stats.hours / maxHours) * availableHeight * 0.8) : 4
                                            )
                                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                                            .opacity(stats.hours > 0 ? 1.0 : 0.15)
                                            .shadow(color: hoursColor.opacity(0.3), radius: 2, x: 0, y: -1)
                                    }
                                    
                                    // Profit bar (green/red)
                                    VStack(spacing: 2) {
                                        if stats.profit != 0 {
                                            Text("$\(Int(stats.profit))")
                                                .font(.plusJakarta(.caption2, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                        }
                                        
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(stops: [
                                                        .init(color: (stats.profit >= 0 ? profitColor : negativeColor).opacity(0.3), location: 0),
                                                        .init(color: (stats.profit >= 0 ? profitColor : negativeColor).opacity(0.7), location: 0.3),
                                                        .init(color: stats.profit >= 0 ? profitColor : negativeColor, location: 0.8),
                                                        .init(color: (stats.profit >= 0 ? profitColor : negativeColor).opacity(0.9), location: 1)
                                                    ]),
                                                    startPoint: .bottom,
                                                    endPoint: .top
                                                )
                                            )
                                            .frame(
                                                width: barWidth,
                                                height: abs(stats.profit) > 0 ? max(4, (abs(stats.profit) / maxProfitAbs) * availableHeight * 0.8) : 4
                                            )
                                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                                            .opacity(stats.profit != 0 ? 1.0 : 0.15)
                                            .shadow(color: (stats.profit >= 0 ? profitColor : negativeColor).opacity(0.3), radius: 2, x: 0, y: -1)
                                    }
                                }
                                .frame(width: dayWidth, height: availableHeight, alignment: .bottom)
                            }
                        }
                    }
                    
                    // Day labels
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(dayLabels[i])
                                .font(.plusJakarta(.caption2, weight: .medium))
                                .foregroundColor(.gray.opacity(0.8))
                                .frame(width: dayWidth)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(height: 140)
            .padding(.horizontal, 16)
            
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
