import SwiftUI

// MARK: - Monthly Profit Bar Chart
struct MonthlyProfitBarChart: View {
    let sessions: [Session]
    let bankrollTransactions: [BankrollTransaction]
    let adjustedProfitCalculator: ((Session) -> Double)?
    let onBarTouch: (String) -> Void
    
    @State private var selectedBarIndex: Int? = nil
    
    private func barHeight(for profit: Double, isPositive: Bool, positiveMax: Double, negativeMin: Double, maxAbsValue: Double, zeroLineY: CGFloat, geometryHeight: CGFloat) -> CGFloat {
        guard maxAbsValue > 0 else { return 0 }
        
        if isPositive {
            return (profit / positiveMax) * (zeroLineY - 30)
        } else {
            return (abs(profit) / abs(negativeMin)) * (geometryHeight - 30 - zeroLineY)
        }
    }
    
    private func barColor(isPositive: Bool) -> Color {
        return isPositive ? 
            Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
            Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
    }
    
    private var monthlyData: [(String, Double)] {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        
        // Get last 12 months
        var months: [Date] = []
        for i in 0..<12 {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                months.append(date)
            }
        }
        months.reverse()
        
        return months.map { month in
            let monthProfit = sessions.filter { session in
                calendar.isDate(session.startDate, equalTo: month, toGranularity: .month)
            }.reduce(0) { result, session in
                let profit = adjustedProfitCalculator?(session) ?? session.profit
                return result + profit
            }
            
            let bankrollProfit = bankrollTransactions.filter { transaction in
                calendar.isDate(transaction.timestamp, equalTo: month, toGranularity: .month)
            }.reduce(0) { $0 + $1.amount }
            
            return (formatter.string(from: month), monthProfit + bankrollProfit)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let data = monthlyData
            let maxValue = data.map { abs($0.1) }.max() ?? 1
            let centerY = geometry.size.height / 2
            let availableHeight = centerY - 25 // Leave space for labels
            let barWidth: CGFloat = 24 // Fixed width for consistency
            let totalBarsWidth = CGFloat(data.count) * barWidth
            let totalSpacing = geometry.size.width - totalBarsWidth - 32 // 16 padding on each side
            let spacing = totalSpacing / CGFloat(max(1, data.count - 1))
            
            ZStack {
                // Grid lines for reference
                VStack(spacing: 0) {
                    ForEach(0..<3) { i in
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 0.5)
                        if i < 2 { Spacer() }
                    }
                }
                .padding(.vertical, 15)
                
                // Central zero line (emphasized)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.gray.opacity(0.6),
                                Color.gray.opacity(0.8),
                                Color.gray.opacity(0.6),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: centerY)
                    .shadow(color: Color.gray.opacity(0.3), radius: 1, y: 0)
                
                // Bars with perfect alignment
                HStack(spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        let (month, profit) = item
                        let isPositive = profit >= 0
                        let barHeight = maxValue > 0 ? min(abs(profit) / maxValue * availableHeight, availableHeight) : 0
                        let barColor = barColor(isPositive: isPositive)
                        
                        VStack(spacing: 0) {
                            // Top section (positive values)
                            ZStack(alignment: .bottom) {
                                // Spacer to maintain layout
                                Color.clear
                                    .frame(height: availableHeight)
                                
                                // Positive bar
                                if isPositive && barHeight > 0 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: barColor.opacity(0.3), location: 0),
                                                    .init(color: barColor.opacity(0.7), location: 0.3),
                                                    .init(color: barColor, location: 0.7),
                                                    .init(color: barColor.opacity(0.9), location: 1)
                                                ]),
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .frame(width: barWidth, height: barHeight)
                                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                                        .shadow(color: barColor.opacity(0.4), radius: 3, x: 0, y: -2)
                                        .overlay(
                                            // Highlight effect
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.white.opacity(0.3),
                                                            Color.clear
                                                        ]),
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: barWidth * 0.7, height: barHeight * 0.4)
                                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                                                .offset(y: -barHeight * 0.3)
                                        )
                                        .scaleEffect(selectedBarIndex == index ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedBarIndex)
                                }
                            }
                            
                            // Center divider (zero line space)
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 4)
                            
                            // Bottom section (negative values)
                            ZStack(alignment: .top) {
                                // Spacer to maintain layout
                                Color.clear
                                    .frame(height: availableHeight)
                                
                                // Negative bar
                                if !isPositive && barHeight > 0 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: barColor.opacity(0.9), location: 0),
                                                    .init(color: barColor, location: 0.3),
                                                    .init(color: barColor.opacity(0.7), location: 0.7),
                                                    .init(color: barColor.opacity(0.3), location: 1)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: barWidth, height: barHeight)
                                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                                        .shadow(color: barColor.opacity(0.4), radius: 3, x: 0, y: 2)
                                        .overlay(
                                            // Highlight effect
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.clear,
                                                            Color.white.opacity(0.2)
                                                        ]),
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: barWidth * 0.7, height: barHeight * 0.4)
                                                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4))
                                                .offset(y: barHeight * 0.3)
                                        )
                                        .scaleEffect(selectedBarIndex == index ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedBarIndex)
                                }
                            }
                        }
                        .frame(width: barWidth)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedBarIndex = selectedBarIndex == index ? nil : index
                            }
                            onBarTouch(month)
                        }
                        
                        // Add spacing except after last item
                        if index < data.count - 1 {
                            Spacer()
                                .frame(width: spacing)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Month labels with better positioning
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                            Text(item.0.split(separator: " ").first ?? "")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.gray.opacity(0.8))
                                .frame(width: barWidth)
                                .multilineTextAlignment(.center)
                            
                            // Add spacing except after last item
                            if index < data.count - 1 {
                                Spacer()
                                    .frame(width: spacing)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                
                // Value labels on hover/selection
                if let selectedIndex = selectedBarIndex {
                    let selectedData = data[selectedIndex]
                    VStack(spacing: 4) {
                        Text(selectedData.0)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("$\(Int(selectedData.1).formattedWithCommas)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(selectedData.1 >= 0 ? 
                                          Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                          Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Material.ultraThinMaterial)
                                .opacity(0.9)
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }
                    )
                    .position(x: geometry.size.width / 2, y: 30)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}