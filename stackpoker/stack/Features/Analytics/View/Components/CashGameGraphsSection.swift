import SwiftUI
import Charts

struct CashGameGraphsSection: View {
    let sessions: [Session]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cash Game Graphs")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Hourly Rate vs Duration Graph
                    GraphCard(
                        title: "Hourly Rate vs Duration",
                        subtitle: "Performance by Duration",
                        gradient: [Color(red: 64/255, green: 156/255, blue: 255/255), Color(red: 100/255, green: 180/255, blue: 255/255)]
                    ) {
                        HourlyRateVsDurationChart(sessions: sessions)
                    }
                    
                    // Add more graphs here in the future
                }
                .padding(.horizontal, 24)
            }
        }
    }
}



// MARK: - Swift Charts Implementation

struct HourlyRateVsDurationChart: View {
    let sessions: [Session]
    
    // Data point for charting
    struct DataPoint: Identifiable {
        let id = UUID()
        let duration: Double
        let hourlyRate: Double
    }
    
    // Raw data points from sessions
    private var dataPoints: [DataPoint] {
        return sessions.compactMap { session -> DataPoint? in
            guard session.hoursPlayed > 0 else { return nil }
            let hourlyRate = session.profit / session.hoursPlayed
            return DataPoint(duration: session.hoursPlayed, hourlyRate: hourlyRate)
        }
    }
    
    // Outlier-filtered data using MAD
    private var cleanedDataPoints: [DataPoint] {
        guard !dataPoints.isEmpty else { return [] }
        
        let rates = dataPoints.map { $0.hourlyRate }
        let median = rates.sorted()[rates.count / 2]
        let deviations = rates.map { abs($0 - median) }
        let mad = deviations.sorted()[deviations.count / 2]
        
        guard mad > 0 else { return dataPoints }
        
        let threshold = 3 * mad // 3 MAD threshold
        return dataPoints.filter { abs($0.hourlyRate - median) <= threshold }
    }
    
    // LOWESS smoothed points for the trend line
    private var smoothedPoints: [DataPoint] {
        guard cleanedDataPoints.count >= 2 else { return [] }
        
        let sortedData = cleanedDataPoints.sorted { $0.duration < $1.duration }
        let minDuration = sortedData.first!.duration
        let maxDuration = sortedData.last!.duration
        
        var points: [DataPoint] = []
        let steps = 50
        
        for i in 0..<steps {
            let x = minDuration + (maxDuration - minDuration) * Double(i) / Double(steps - 1)
            let y = lowessSmooth(at: x, from: sortedData)
            points.append(DataPoint(duration: x, hourlyRate: y))
        }
        
        return points
    }
    
    var body: some View {
        if cleanedDataPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
                Text("No sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cleanedDataPoints.count <= 4 {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
                Text("Not enough data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Text("Need more than 4 sessions")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                // LOWESS smoothed trend line
                ForEach(smoothedPoints) { point in
                    LineMark(
                        x: .value("Duration", point.duration),
                        y: .value("Hourly Rate", point.hourlyRate)
                    )
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel {
                        if let duration = value.as(Double.self) {
                            Text("\(Int(duration))h")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel {
                        if let rate = value.as(Double.self) {
                            Text("$\(Int(rate))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(.clear)
            }
        }
    }
    
    // LOWESS smoothing function
    private func lowessSmooth(at x: Double, from data: [DataPoint]) -> Double {
        let bandwidth = 0.5 // 50% bandwidth
        let n = data.count
        let k = max(3, Int(Double(n) * bandwidth))
        
        // Calculate distances and find k nearest neighbors
        let distances = data.map { abs($0.duration - x) }
        let sortedIndices = distances.enumerated().sorted { $0.element < $1.element }
        let nearestIndices = Array(sortedIndices.prefix(k).map { $0.offset })
        
        let maxDistance = distances[sortedIndices[k-1].offset]
        guard maxDistance > 0 else { return data.first?.hourlyRate ?? 0 }
        
        // Weighted average with tricube weights
        var sumWeights = 0.0
        var sumWeightedY = 0.0
        
        for i in nearestIndices {
            let point = data[i]
            let distance = distances[i]
            let u = distance / maxDistance
            let weight = pow(1.0 - pow(u, 3), 3) // Tricube weight
            
            sumWeights += weight
            sumWeightedY += weight * point.hourlyRate
        }
        
        return sumWeights > 0 ? sumWeightedY / sumWeights : 0
    }
}

#Preview {
    let sampleSessions = [
        Session(id: "1", data: [
            "userId": "preview",
            "gameType": "CASH GAME",
            "gameName": "The Mirage",
            "stakes": "$2/$5",
            "startDate": Date(),
            "startTime": Date(),
            "endTime": Date(),
            "hoursPlayed": 3.5,
            "buyIn": 500.0,
            "cashout": 850.0,
            "profit": 350.0,
            "createdAt": Date()
        ]),
        Session(id: "2", data: [
            "userId": "preview",
            "gameType": "CASH GAME",
            "gameName": "Bellagio",
            "stakes": "$5/$10",
            "startDate": Date(),
            "startTime": Date(),
            "endTime": Date(),
            "hoursPlayed": 6.0,
            "buyIn": 1000.0,
            "cashout": 1200.0,
            "profit": 200.0,
            "createdAt": Date()
        ])
    ]
    
    CashGameGraphsSection(sessions: sampleSessions)
        .background(Color.black)
} 