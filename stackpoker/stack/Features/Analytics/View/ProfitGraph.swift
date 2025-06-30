import SwiftUI
import Charts

struct ProfitGraph: View {
    @ObservedObject var sessionStore: SessionStore
    
    private var cumulativeProfitData: [(Date, Double)] {
        var cumulative: Double = 0
        let sorted = sessionStore.sessions.sorted { $0.startDate < $1.startDate }
        return sorted.map { session in
            cumulative += session.profit
            return (session.startDate, cumulative)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if cumulativeProfitData.isEmpty {
                Text("No sessions recorded")
                    .foregroundColor(.gray)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            } else {
                // Chart
                Chart {
                    // Background gradient area
                    AreaMark(
                        x: .value("Date", cumulativeProfitData.first?.0 ?? Date()),
                        y: .value("Profit", cumulativeProfitData.first?.1 ?? 0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.1)),
                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.02))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Line and points
                    ForEach(cumulativeProfitData, id: \.0) { date, profit in
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Profit", profit)
                        )
                        .foregroundStyle(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Date", date),
                            y: .value("Profit", profit)
                        )
                        .foregroundStyle(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .symbolSize(25)
                    }
                    .interpolationMethod(.linear)
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                            .foregroundStyle(Color.gray.opacity(0.7))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel(format: .currency(code: "USD").precision(.fractionLength(0)))
                            .foregroundStyle(Color.gray.opacity(0.7))
                    }
                }
                .chartXScale(domain: {
                    if let first = cumulativeProfitData.first?.0,
                       let last = cumulativeProfitData.last?.0 {
                        // Add 1 day padding on each side
                        let calendar = Calendar.current
                        let startDate = calendar.date(byAdding: .day, value: -1, to: first) ?? first
                        let endDate = calendar.date(byAdding: .day, value: 1, to: last) ?? last
                        return startDate...endDate
                    }
                    return Date.now...Date.now
                }())
                .chartYScale(domain: { 
                    if let minProfit = cumulativeProfitData.map({ $0.1 }).min(),
                       let maxProfit = cumulativeProfitData.map({ $0.1 }).max() {
                        // Add 20% padding to the profit range
                        let range = maxProfit - minProfit
                        let padding = range * 0.2
                        return (minProfit - padding)...(maxProfit + padding)
                    }
                    return 0...1000
                }())
                
                // Session list
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sessionStore.sessions.sorted(by: { $0.startDate > $1.startDate }), id: \.id) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatDate(session.startDate))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                Text(session.profit >= 0 ? "+$\(Int(session.profit))" : "-$\(abs(Int(session.profit)))")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(session.profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(UIColor(red: 18/255, green: 19/255, blue: 22/255, alpha: 1.0)))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
} 

