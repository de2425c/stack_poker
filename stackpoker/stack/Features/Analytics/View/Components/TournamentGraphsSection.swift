import SwiftUI
import Charts

struct TournamentGraphsSection: View {
    let sessions: [Session]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tournament Graphs")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Buy-in Distribution Graph
                    GraphCard(
                        title: "Buy-in Distribution",
                        subtitle: "Tournament Stakes",
                        gradient: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)]
                    ) {
                        BuyInDistributionChart(sessions: sessions)
                    }
                    
                    // ROI by Stake Graph
                    GraphCard(
                        title: "ROI by Stake",
                        subtitle: "Return on Investment",
                        gradient: [Color.green.opacity(0.8), Color.teal.opacity(0.6)]
                    ) {
                        ROIByStakeChart(sessions: sessions)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Buy-in Distribution Chart

struct BuyInDistributionChart: View {
    let sessions: [Session]
    
    // Data point for charting
    struct BuyInData: Identifiable {
        let id = UUID()
        let range: String
        let count: Int
        let sortOrder: Int
    }
    
    // Group buy-ins into ranges
    private var buyInDistribution: [BuyInData] {
        guard !sessions.isEmpty else { return [] }
        
        let buyIns = sessions.map { $0.buyIn }
        var ranges: [String: Int] = [:]
        
        for buyIn in buyIns {
            let range: String
            
            switch buyIn {
            case 0...100:
                range = "$0-$100"
            case 101...500:
                range = "$100-$500"
            case 501...1500:
                range = "$500-$1.5K"
            case 1501...5000:
                range = "$1.5K-$5K"
            case 5001...25000:
                range = "$5K-$25K"
            default:
                range = "$25K+"
            }
            
            ranges[range] = (ranges[range] ?? 0) + 1
        }
        
        return ranges.map { (range, count) in
            let sortOrder = getSortOrder(for: range)
            return BuyInData(range: range, count: count, sortOrder: sortOrder)
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func getSortOrder(for range: String) -> Int {
        switch range {
        case "$0-$100": return 0
        case "$100-$500": return 1
        case "$500-$1.5K": return 2
        case "$1.5K-$5K": return 3
        case "$5K-$25K": return 4
        case "$25K+": return 5
        default: return 6
        }
    }
    
    var body: some View {
        if buyInDistribution.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
                Text("No sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(buyInDistribution) { data in
                BarMark(
                    x: .value("Range", data.range),
                    y: .value("Count", data.count)
                )
                .foregroundStyle(.white)
                .cornerRadius(4)
                // Add annotation above each bar
                .annotation(position: .top) {
                    Text(data.range)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.bottom, 2)
                }
            }
            .frame(height: 140)
            .padding(.top, 20) // Space for annotations above bars
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    // No label here
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            EmptyView()
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
}

// MARK: - ROI by Stake Chart

struct ROIByStakeChart: View {
    let sessions: [Session]
    
    // Data point for ROI charting
    struct ROIData: Identifiable {
        let id = UUID()
        let range: String
        let roi: Double
        let sortOrder: Int
    }
    
    // Group sessions by buy-in ranges and calculate ROI
    private var roiByStake: [ROIData] {
        guard !sessions.isEmpty else { return [] }
        
        var rangeData: [String: (totalBuyIn: Double, totalCashout: Double, sortOrder: Int)] = [:]
        
        for session in sessions {
            let range: String
            let sortOrder: Int
            
            switch session.buyIn {
            case 0...100:
                range = "$0-$100"
                sortOrder = 0
            case 101...500:
                range = "$100-$500"
                sortOrder = 1
            case 501...1500:
                range = "$500-$1.5K"
                sortOrder = 2
            case 1501...5000:
                range = "$1.5K-$5K"
                sortOrder = 3
            case 5001...25000:
                range = "$5K-$25K"
                sortOrder = 4
            default:
                range = "$25K+"
                sortOrder = 5
            }
            
            if rangeData[range] == nil {
                rangeData[range] = (totalBuyIn: 0, totalCashout: 0, sortOrder: sortOrder)
            }
            
            rangeData[range]?.totalBuyIn += session.buyIn
            rangeData[range]?.totalCashout += session.cashout
        }
        
        return rangeData.compactMap { (range, data) in
            guard data.totalBuyIn > 0 else { return nil }
            let roi = ((data.totalCashout - data.totalBuyIn) / data.totalBuyIn) * 100
            return ROIData(range: range, roi: roi, sortOrder: data.sortOrder)
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    // Custom logarithmic axis values: -100, -10, 0, 10, 100, 1000
    private var logAxisValues: [Double] {
        let minROI = roiByStake.map { $0.roi }.min() ?? -100
        let maxROI = roiByStake.map { $0.roi }.max() ?? 100
        
        var values: [Double] = []
        
        // Add negative values if needed
        if minROI < 0 {
            let negativeValues = [-1000, -100, -10].filter { $0 >= minROI }
            values.append(contentsOf: negativeValues)
        }
        
        // Always include 0
        values.append(0)
        
        // Add positive values
        let positiveValues = [10, 100, 1000].filter { $0 <= max(maxROI, 10) }
        values.append(contentsOf: positiveValues)
        
        return values
    }
    
    // Transform ROI to logarithmic scale for proper bar sizing
    private func logTransform(_ roi: Double) -> Double {
        if roi > 0 {
            return log10(roi + 1) // Add 1 to handle roi=0, log10(1)=0
        } else if roi < 0 {
            return -log10(abs(roi) + 1) // Negative log for negative ROI
        } else {
            return 0 // roi = 0
        }
    }
    
    // Convert log-transformed value back to original ROI for display
    private func inverseLogTransform(_ transformedROI: Double) -> Double {
        if transformedROI > 0 {
            return pow(10, transformedROI) - 1
        } else if transformedROI < 0 {
            return -(pow(10, abs(transformedROI)) - 1)
        } else {
            return 0
        }
    }
    
    // Format ROI value for display
    private func formatROI(_ roi: Double) -> String {
        return "\(Int(roi))%"
    }
    
    // Get the range for the chart domain
    private var chartDomain: ClosedRange<Double> {
        let transformedValues = roiByStake.map { logTransform($0.roi) }
        let minValue = transformedValues.min() ?? -2
        let maxValue = transformedValues.max() ?? 2
        return minValue...maxValue
    }
    
    var body: some View {
        if roiByStake.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
                Text("No sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(roiByStake) { data in
                BarMark(
                    x: .value("Range", data.range),
                    y: .value("ROI", logTransform(data.roi)) // Use log-transformed value for bar height
                )
                .foregroundStyle(.white)
                .cornerRadius(4)
                // Add annotation above each bar
                .annotation(position: .top) {
                    Text(data.range)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.bottom, 2)
                }
            }
            .frame(height: 140)
            .padding(.top, 20) // Space for annotations above bars
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    // No label here
                }
            }
            .chartYScale(domain: chartDomain)
            .chartYAxis {
                AxisMarks(position: .leading, values: logAxisValues.map { logTransform($0) }) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel {
                        if let transformedROI = value.as(Double.self) {
                            let originalROI = inverseLogTransform(transformedROI)
                            Text(formatROI(originalROI))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            EmptyView()
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
}

#Preview {
    TournamentGraphsSection(sessions: [])
        .background(Color.black)
} 