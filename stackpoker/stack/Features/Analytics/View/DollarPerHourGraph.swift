import SwiftUI
import Charts

struct DollarPerHourGraph: View {
    let sessions: [Session]
    
        // Start showing graph after 10 sessions with smoothed calculation
    private var validDataPoints: [CumulativeDataPoint] {
        let sortedSessions = sessions.sorted { $0.startDate < $1.startDate }
        guard sortedSessions.count >= 10 else { return [] }
        
        var cumulativeProfit: Double = 0
        var cumulativeHours: Double = 0
        var dataPoints: [CumulativeDataPoint] = []
        
        // Get baseline from first 10 sessions
        let baselineSessions = Array(sortedSessions.prefix(10))
        let baselineProfit = baselineSessions.reduce(0) { $0 + $1.profit }
        let baselineHours = baselineSessions.reduce(0) { $0 + $1.hoursPlayed }
        
        for (index, session) in sortedSessions.enumerated() {
            cumulativeProfit += session.profit
            cumulativeHours += session.hoursPlayed
            
            // Only show data points starting from session 10
            if index >= 9 {
                let sessionNumber = index + 1
                let rawDollarPerHour = cumulativeHours > 0 ? cumulativeProfit / cumulativeHours : 0
                
                // Smooth early sessions to prevent jumps
                let smoothedDollarPerHour: Double
                if sessionNumber <= 30 {
                    // Use exponential moving average for smoothing
                    let alpha = min(0.3, Double(sessionNumber - 10) / 20.0) // Gradually increase sensitivity
                    let baselineRate = baselineHours > 0 ? baselineProfit / baselineHours : 0
                    smoothedDollarPerHour = (1 - alpha) * baselineRate + alpha * rawDollarPerHour
                } else {
                    smoothedDollarPerHour = rawDollarPerHour
                }
                
                dataPoints.append(CumulativeDataPoint(
                    sessionNumber: sessionNumber,
                    dollarPerHour: smoothedDollarPerHour,
                    cumulativeProfit: cumulativeProfit,
                    cumulativeHours: cumulativeHours,
                    date: session.startDate
                ))
            }
        }
        
        return dataPoints
    }
    
    private var currentDollarPerHour: Double {
        validDataPoints.last?.dollarPerHour ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header section with title and current value
            VStack(alignment: .leading, spacing: 4) {
                Text("Cumulative $/Hour")
                    .font(.plusJakarta(.footnote, weight: .medium))
                    .foregroundColor(.gray)
                
                HStack(alignment: .bottom, spacing: 8) {
                    Text("$\(String(format: "%.1f", abs(currentDollarPerHour)))/hr")
                        .font(.plusJakarta(.title, weight: .bold))
                        .foregroundColor(.white)
                
                    // Trend indicator
                    HStack(spacing: 4) {
                        Image(systemName: currentDollarPerHour >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.plusJakarta(.caption2))
                            .foregroundColor(currentDollarPerHour >= 0 ? 
                                           Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                           Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                        
                        Text("after \(sessions.count) sessions")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Chart or not enough data message
            if validDataPoints.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.plusJakarta(.title2))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    VStack(spacing: 4) {
                        Text("Not enough data yet")
                            .font(.plusJakarta(.subheadline, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Play \(10 - sessions.count) more session\(10 - sessions.count == 1 ? "" : "s") to see your $/hour trend")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geometry in
                    ZStack {
                        // Subtle grid lines
                        VStack(spacing: 0) {
                            ForEach(0..<4) { _ in
                                Spacer()
                                Rectangle()
                                    .fill(Color.gray.opacity(0.08))
                                    .frame(height: 0.5)
                            }
                        }
                        .padding(.vertical, 15)
                        
                        // Background gradient for depth
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0),
                                .init(color: Color.white.opacity(0.01), location: 0.3),
                                .init(color: Color.white.opacity(0.02), location: 0.7),
                                .init(color: Color.clear, location: 1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.overlay)
                        
                        // Main chart path
                        if !validDataPoints.isEmpty {
                            let chartColor = currentDollarPerHour >= 0 ? 
                                Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
                            
                                                         CumulativeChartPath(
                                 dataPoints: validDataPoints.map { (sessionNumber: $0.sessionNumber, dollarPerHour: $0.dollarPerHour) },
                                 totalSessions: sessions.count,
                                 geometry: geometry,
                                 color: chartColor,
                                 showFill: true
                             )
                        }
                        
                        // Zero line reference
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
                .frame(height: 180)
                .padding(.horizontal, 16)
            }
            
            // Summary stats in a clean row
            if !validDataPoints.isEmpty, let lastPoint = validDataPoints.last {
                HStack(spacing: 0) {
                    CumulativeStatItem(
                        title: "Current Rate",
                        value: "$\(String(format: "%.1f", lastPoint.dollarPerHour))/hr",
                        color: lastPoint.dollarPerHour >= 0 ? .green : .red
                    )
                    
                    Divider()
                        .frame(width: 1, height: 30)
                        .background(Color.gray.opacity(0.2))
                    
                    CumulativeStatItem(
                        title: "Total Sessions",
                        value: "\(sessions.count)",
                        color: .cyan
                    )
                    
                    Divider()
                        .frame(width: 1, height: 30)
                        .background(Color.gray.opacity(0.2))
                    
                    CumulativeStatItem(
                        title: "Total Hours",
                        value: "\(String(format: "%.1f", lastPoint.cumulativeHours))h",
                        color: .orange
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
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

// MARK: - Supporting Views

struct CumulativeStatItem: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.plusJakarta(.caption2, weight: .medium))
                .foregroundColor(.gray.opacity(0.7))
                .tracking(0.5)
            
            Text(value)
                .font(.plusJakarta(.subheadline, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CumulativeChartPath: View {
    let dataPoints: [(sessionNumber: Int, dollarPerHour: Double)]
    let totalSessions: Int
    let geometry: GeometryProxy
    let color: Color
    let showFill: Bool
    
    var body: some View {
        ZStack {
            if showFill {
                // Fill area
                Path { path in
                    guard !dataPoints.isEmpty else { return }
                    
                    let minValue = dataPoints.map { $0.dollarPerHour }.min() ?? 0
                    let maxValue = max(dataPoints.map { $0.dollarPerHour }.max() ?? 1, 1)
                    let range = max(maxValue - minValue, 1)
                    
                    func getY(_ value: Double) -> CGFloat {
                        let normalized = range == 0 ? 0.5 : (value - minValue) / range
                        return geometry.size.height * (1 - CGFloat(normalized))
                    }
                    
                    // Calculate X position based on session number relative to total sessions
                    func getX(for sessionNumber: Int) -> CGFloat {
                        let progress = CGFloat(sessionNumber - 1) / CGFloat(max(totalSessions - 1, 1))
                        return progress * geometry.size.width
                    }
                    
                    // Start from bottom at first data point's X position
                    let firstX = getX(for: dataPoints[0].sessionNumber)
                    path.move(to: CGPoint(x: firstX, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: firstX, y: getY(dataPoints[0].dollarPerHour)))
                    
                    // Smooth curve through all points using actual session positions
                    for i in 1..<dataPoints.count {
                        let x = getX(for: dataPoints[i].sessionNumber)
                        let y = getY(dataPoints[i].dollarPerHour)
                        
                        let prevX = getX(for: dataPoints[i-1].sessionNumber)
                        let prevY = getY(dataPoints[i-1].dollarPerHour)
                        
                        let deltaX = x - prevX
                        let controlPoint1 = CGPoint(x: prevX + deltaX/3, y: prevY)
                        let controlPoint2 = CGPoint(x: x - deltaX/3, y: y)
                        
                        path.addCurve(to: CGPoint(x: x, y: y), control1: controlPoint1, control2: controlPoint2)
                    }
                    
                    // Close to bottom at last data point's X position
                    let lastX = getX(for: dataPoints.last!.sessionNumber)
                    path.addLine(to: CGPoint(x: lastX, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.25), location: 0),
                            .init(color: color.opacity(0.12), location: 0.4),
                            .init(color: color.opacity(0.05), location: 0.7),
                            .init(color: Color.clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Main line
            Path { path in
                guard !dataPoints.isEmpty else { return }
                
                let minValue = dataPoints.map { $0.dollarPerHour }.min() ?? 0
                let maxValue = max(dataPoints.map { $0.dollarPerHour }.max() ?? 1, 1)
                let range = max(maxValue - minValue, 1)
                
                func getY(_ value: Double) -> CGFloat {
                    let normalized = range == 0 ? 0.5 : (value - minValue) / range
                    return geometry.size.height * (1 - CGFloat(normalized))
                }
                
                // Calculate X position based on session number relative to total sessions
                func getX(for sessionNumber: Int) -> CGFloat {
                    let progress = CGFloat(sessionNumber - 1) / CGFloat(max(totalSessions - 1, 1))
                    return progress * geometry.size.width
                }
                
                path.move(to: CGPoint(x: getX(for: dataPoints[0].sessionNumber), y: getY(dataPoints[0].dollarPerHour)))
                
                for i in 1..<dataPoints.count {
                    let x = getX(for: dataPoints[i].sessionNumber)
                    let y = getY(dataPoints[i].dollarPerHour)
                    
                    let prevX = getX(for: dataPoints[i-1].sessionNumber)
                    let prevY = getY(dataPoints[i-1].dollarPerHour)
                    
                    let deltaX = x - prevX
                    let controlPoint1 = CGPoint(x: prevX + deltaX/3, y: prevY)
                    let controlPoint2 = CGPoint(x: x - deltaX/3, y: y)
                    
                    path.addCurve(to: CGPoint(x: x, y: y), control1: controlPoint1, control2: controlPoint2)
                }
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.9),
                        color,
                        color.opacity(0.95)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: color.opacity(0.3), radius: 3, y: 1)
        }
    }
}

// Keep the existing data model
struct CumulativeDataPoint {
    let sessionNumber: Int
    let dollarPerHour: Double
    let cumulativeProfit: Double
    let cumulativeHours: Double
    let date: Date
} 