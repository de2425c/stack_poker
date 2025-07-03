import SwiftUI

// MARK: - Chart Path Helper
struct ChartPath: View {
    let dataPoints: [(Date, Double)]
    let geometry: GeometryProxy
    let color: Color
    let showFill: Bool
    
    var body: some View {
        ZStack {
            if showFill {
                // Fill area
                Path { path in
                    guard !dataPoints.isEmpty else { return }
                    
                    let minProfit = dataPoints.map { $0.1 }.min() ?? 0
                    let maxProfit = max(dataPoints.map { $0.1 }.max() ?? 1, 1)
                    let range = max(maxProfit - minProfit, 1)
                    
                    // Use session-based indexing instead of date-based positioning
                    let stepX = dataPoints.count > 1 ? geometry.size.width / CGFloat(dataPoints.count - 1) : geometry.size.width
                    
                    func getY(_ value: Double) -> CGFloat {
                        let normalized = range == 0 ? 0.5 : (value - minProfit) / range
                        return geometry.size.height * (1 - CGFloat(normalized))
                    }
                    
                    func getX(_ index: Int) -> CGFloat {
                        return CGFloat(index) * stepX
                    }
                    
                    // Start from bottom
                    path.move(to: CGPoint(x: getX(0), y: geometry.size.height))
                    path.addLine(to: CGPoint(x: getX(0), y: getY(dataPoints[0].1)))
                    
                    // Draw through all points using session indices
                    for i in 1..<dataPoints.count {
                        let x = getX(i)
                        let y = getY(dataPoints[i].1)
                        
                        let prevX = getX(i-1)
                        let prevY = getY(dataPoints[i-1].1)
                        
                        let controlPoint1 = CGPoint(x: prevX + stepX/3, y: prevY)
                        let controlPoint2 = CGPoint(x: x - stepX/3, y: y)
                        
                        path.addCurve(to: CGPoint(x: x, y: y), control1: controlPoint1, control2: controlPoint2)
                    }
                    
                    // Close to bottom
                    path.addLine(to: CGPoint(x: getX(dataPoints.count - 1), y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.35), location: 0),
                            .init(color: color.opacity(0.15), location: 0.4),
                            .init(color: color.opacity(0.08), location: 0.7),
                            .init(color: Color.clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Line path
            Path { path in
                guard !dataPoints.isEmpty else { return }
                
                let minProfit = dataPoints.map { $0.1 }.min() ?? 0
                let maxProfit = max(dataPoints.map { $0.1 }.max() ?? 1, 1)
                let range = max(maxProfit - minProfit, 1)
                
                // Use session-based indexing instead of date-based positioning
                let stepX = dataPoints.count > 1 ? geometry.size.width / CGFloat(dataPoints.count - 1) : geometry.size.width
                
                func getY(_ value: Double) -> CGFloat {
                    let normalized = range == 0 ? 0.5 : (value - minProfit) / range
                    return geometry.size.height * (1 - CGFloat(normalized))
                }
                
                func getX(_ index: Int) -> CGFloat {
                    return CGFloat(index) * stepX
                }
                
                path.move(to: CGPoint(x: getX(0), y: getY(dataPoints[0].1)))
                
                // Draw through all points using session indices
                for i in 1..<dataPoints.count {
                    let x = getX(i)
                    let y = getY(dataPoints[i].1)
                    
                    let prevX = getX(i-1)
                    let prevY = getY(dataPoints[i-1].1)
                    
                    let controlPoint1 = CGPoint(x: prevX + stepX/3, y: prevY)
                    let controlPoint2 = CGPoint(x: x - stepX/3, y: y)
                    
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
            .shadow(color: color.opacity(0.4), radius: 4, y: 2)
        }
    }
}