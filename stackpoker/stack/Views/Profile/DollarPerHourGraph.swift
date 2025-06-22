import SwiftUI
import Charts

struct DollarPerHourGraph: View {
    let sessions: [Session]
    
    private var dataPoints: [CumulativeDataPoint] {
        let sortedSessions = sessions.sorted { $0.startDate < $1.startDate }
        var cumulativeProfit: Double = 0
        var cumulativeHours: Double = 0
        var dataPoints: [CumulativeDataPoint] = []
        
        for (index, session) in sortedSessions.enumerated() {
            cumulativeProfit += session.profit
            cumulativeHours += session.hoursPlayed
            
            let dollarPerHour = cumulativeHours > 0 ? cumulativeProfit / cumulativeHours : 0
            
            dataPoints.append(CumulativeDataPoint(
                sessionNumber: index + 1,
                dollarPerHour: dollarPerHour,
                cumulativeProfit: cumulativeProfit,
                cumulativeHours: cumulativeHours,
                date: session.startDate
            ))
        }
        
        return dataPoints
    }
    
    private var gridLines: [Double] {
        guard !dataPoints.isEmpty else { return [0] }
        
        let minValue = dataPoints.map { $0.dollarPerHour }.min() ?? 0
        let maxValue = dataPoints.map { $0.dollarPerHour }.max() ?? 0
        
        // Ensure we include 0 if it's not in the range
        let actualMin = min(minValue, 0)
        let actualMax = max(maxValue, 0)
        
        // Create 7 evenly spaced grid lines
        let range = actualMax - actualMin
        let step = range / 6.0
        
        return (0...6).map { index in
            actualMin + (step * Double(index))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Cumulative $/Hour")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Current $/hour display
                if let lastPoint = dataPoints.last {
                    HStack(spacing: 4) {
                        Text("$\(String(format: "%.2f", lastPoint.dollarPerHour))/hr")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(lastPoint.dollarPerHour >= 0 ? .green : .red)
                        
                        Image(systemName: lastPoint.dollarPerHour >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 10))
                            .foregroundColor(lastPoint.dollarPerHour >= 0 ? .green : .red)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Chart
            if dataPoints.isEmpty {
                Text("No sessions recorded")
                    .foregroundColor(.gray)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    // Grid lines
                    ForEach(gridLines, id: \.self) { gridValue in
                        RuleMark(y: .value("Grid", gridValue))
                            .foregroundStyle(Color.gray.opacity(0.2))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    
                    ForEach(dataPoints, id: \.sessionNumber) { point in
                        LineMark(
                            x: .value("Session", point.sessionNumber),
                            y: .value("$/Hour", point.dollarPerHour)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.mint.opacity(0.8), Color.green.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        
                        // Add area fill below the line
                        AreaMark(
                            x: .value("Session", point.sessionNumber),
                            y: .value("$/Hour", point.dollarPerHour)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.mint.opacity(0.3),
                                    Color.mint.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    // Add a horizontal line at $0 for reference
                    RuleMark(y: .value("Break Even", 0))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
                .chartXAxis {
                    AxisMarks { value in
                        if let sessionNumber = value.as(Int.self) {
                            // Show every 5th session number to avoid crowding
                            if sessionNumber % 5 == 0 || sessionNumber == dataPoints.count {
                                AxisValueLabel {
                                    Text("\(sessionNumber)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        if let dollarPerHour = value.as(Double.self) {
                            AxisValueLabel {
                                Text("$\(Int(dollarPerHour))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding(.horizontal, 20)
            }
            
            // Summary stats
            HStack(spacing: 20) {
                if let lastPoint = dataPoints.last {
                    SummaryStat(
                        title: "Current $/Hour",
                        value: lastPoint.dollarPerHour,
                        prefix: "$",
                        suffix: "/hr",
                        color: lastPoint.dollarPerHour >= 0 ? .green : .red
                    )
                    
                    SummaryStat(
                        title: "Total Sessions",
                        value: Double(dataPoints.count),
                        suffix: "",
                        color: .blue
                    )
                    
                    SummaryStat(
                        title: "Total Hours",
                        value: lastPoint.cumulativeHours,
                        suffix: "h",
                        color: .orange
                    )
                }
            }
            .padding(.horizontal, 20)
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
}

struct CumulativeDataPoint {
    let sessionNumber: Int
    let dollarPerHour: Double
    let cumulativeProfit: Double
    let cumulativeHours: Double
    let date: Date
} 