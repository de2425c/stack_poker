import SwiftUI
import FirebaseFirestore
import Charts
import UIKit
import FirebaseAuth

struct DashboardView: View {
    @StateObject private var handStore: HandStore
    @StateObject private var sessionStore: SessionStore
    @StateObject private var postService = PostService()
    @EnvironmentObject private var userService: UserService
    @State private var selectedTimeRange = 1 // Default to 1W (index 1)
    @State private var selectedTab = 0 // 0 = Dashboard, 1 = Hands, 2 = Sessions
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"]
    
    init(userId: String) {
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
    }
    
    private var totalBankroll: Double {
        // Calculate total profit from all sessions
        return sessionStore.sessions.reduce(0) { $0 + $1.profit }
    }
    
    private var selectedTimeRangeProfit: Double {
        let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
        return filteredSessions.reduce(0) { $0 + $1.profit }
    }
    
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessionStore.sessions
        }
    }
    
    private var winRate: Double {
        // Calculate win rate percentage
        let totalSessions = sessionStore.sessions.count
        if totalSessions == 0 { return 0 }
        
        let winningSessions = sessionStore.sessions.filter { $0.profit > 0 }.count
        return Double(winningSessions) / Double(totalSessions) * 100
    }
    
    private var averageProfit: Double {
        // Calculate average profit per session
        let totalSessions = sessionStore.sessions.count
        if totalSessions == 0 { return 0 }
        
        return totalBankroll / Double(totalSessions)
    }
    
    private var totalSessions: Int {
        return sessionStore.sessions.count
    }
    
    private var bestSession: (profit: Double, id: String)? {
        if let best = sessionStore.sessions.max(by: { $0.profit < $1.profit }) {
            return (best.profit, best.id)
        }
        return nil
    }
    
    var body: some View {
            ZStack {
            // Background color
            AppBackgroundView()
                    .ignoresSafeArea()
                
            ScrollView {
                VStack(spacing: 4) { // Further reduced spacing
                    // Refined tab navigation
                    NavigationTabBar(selectedTab: $selectedTab)
                        .padding(.top, 8) // Use explicit value instead of .top
                    
                    // Content based on selected tab
                    if selectedTab == 0 {
                        // DASHBOARD TAB
                        
                        // Integrated Chart Section with Profit display
                        IntegratedChartSection(
                            selectedTimeRange: $selectedTimeRange,
                            timeRanges: timeRanges,
                            sessions: sessionStore.sessions,
                            totalProfit: totalBankroll,
                            timeRangeProfit: selectedTimeRangeProfit
                        )
                        .padding(.top, 6) // Reduced top padding
                        .padding(.bottom, 2) // Minimal padding to move cards up
                        
                        // Stats Cards
                        EnhancedStatsCardGrid(
                            winRate: winRate,
                            averageProfit: averageProfit,
                            totalSessions: totalSessions,
                            bestSession: bestSession
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        
                    } else if selectedTab == 1 {
                        // HANDS TAB
                        HandsTab(handStore: handStore)
                        
                    } else {
                        // SESSIONS TAB
                        SessionsTab(sessionStore: sessionStore)
                    }
                }
                .padding(.bottom, 90) // Added significant bottom padding for better scrolling
            }
        }
        .environmentObject(handStore)
        .environmentObject(postService)
        .environmentObject(userService)
        .onAppear {
            sessionStore.fetchSessions()
        }
    }
}

// MARK: - Refined Navigation Tab Bar
struct NavigationTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 34) { // Increased spacing slightly
            // Dashboard tab
            Button {
                selectedTab = 0
            } label: {
                Text("DASHBOARD")
                    .font(.system(size: 16, weight: selectedTab == 0 ? .bold : .medium))
                    .foregroundColor(selectedTab == 0 ? .white : .gray)
                    .padding(.bottom, 2)
                    .overlay(
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(selectedTab == 0 ? 
                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                Color.clear)
                            .offset(y: 10)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Hands tab
            Button {
                selectedTab = 1
            } label: {
                Text("HANDS")
                    .font(.system(size: 16, weight: selectedTab == 1 ? .bold : .medium))
                    .foregroundColor(selectedTab == 1 ? .white : .gray)
                    .padding(.bottom, 2)
                    .overlay(
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(selectedTab == 1 ? 
                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                Color.clear)
                            .offset(y: 10)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Sessions tab
            Button {
                selectedTab = 2
            } label: {
                Text("SESSIONS")
                    .font(.system(size: 16, weight: selectedTab == 2 ? .bold : .medium))
                    .foregroundColor(selectedTab == 2 ? .white : .gray)
                    .padding(.bottom, 2)
                    .overlay(
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(selectedTab == 2 ? 
                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                Color.clear)
                            .offset(y: 10)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
                        Spacer()
                    }
        .padding(.horizontal, 16)
        .padding(.vertical, 4) // Added slight vertical padding
    }
}

// Integrated Chart Section with Profit Display
struct IntegratedChartSection: View {
    @Binding var selectedTimeRange: Int
    let timeRanges: [String]
    let sessions: [Session]
    let totalProfit: Double
    let timeRangeProfit: Double
    
    // Filter sessions based on selected time range
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessions
        }
    }
    
    var body: some View {
                VStack(spacing: 0) {
            // Profit info at top with better integration - transparent
            VStack(alignment: .leading, spacing: 4) {
                Text("Profit")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.7))
                    .padding(.horizontal, 2) // Moved further left
                
                Text("$\(Int(totalProfit))")
                    .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                    .padding(.horizontal, 2) // Moved further left
                
                HStack(spacing: 4) {
                    Image(systemName: timeRangeProfit >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundColor(timeRangeProfit >= 0 ? 
                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                            Color.red)
                    
                    Text("$\(abs(Int(timeRangeProfit)))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(timeRangeProfit >= 0 ? 
                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                            Color.red)
                    
                    Text("Past \(timeRanges[selectedTimeRange].lowercased())")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16) // Moved further left
                .padding(.bottom, 4)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Removed background - fully transparent
            .padding(.horizontal, 16)
            
            // Time Range Selectors - more refined
            TimeRangeSelector(selectedRange: $selectedTimeRange, ranges: timeRanges)
                .padding(.horizontal, 16)
                .padding(.top, 6) // Reduced padding
            
            // Chart View
            ZStack {
                if sessions.isEmpty {
                    Text("No sessions recorded")
                        .foregroundColor(.gray)
                        .frame(height: 220)
                } else {
                    // Clean chart view
                    BankrollGraph(sessions: sessions, selectedTimeRange: selectedTimeRange)
                        .padding(.horizontal, 4) // Less horizontal padding to expand
                        .padding(.top, 2) // Further reduced padding
                }
            }
        }
    }
}

// Simplified TimeRangeSelector to fix type checking issue
struct TimeRangeSelector: View {
    @Binding var selectedRange: Int
    let ranges: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRange = index
                        }
                    }) {
                        TimeRangeButton(text: range, isSelected: selectedRange == index)
                    }
                    .buttonStyle(ScalePressButtonStyle())
                }
            }
        }
    }
}

// Helper view to simplify the TimeRangeSelector
struct TimeRangeButton: View {
    let text: String
    let isSelected: Bool
    
    private var accentColor: Color {
        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: isSelected ? 0.15 : 0))
    }
    
    private var strokeColor: Color {
        isSelected ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.2)) : Color.clear
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .white : Color.gray.opacity(0.6))
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(Capsule().fill(accentColor))
            .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
    }
}

// Enhanced stat cards grid with perfect symmetry and consistent design
struct EnhancedStatsCardGrid: View {
    let winRate: Double
    let averageProfit: Double
    let totalSessions: Int
    let bestSession: (profit: Double, id: String)?
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Win Rate
                EnhancedStatCard(
                    title: "Win Rate",
                    value: winRate,
                    suffix: "%",
                    isPercentage: true,
                    color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
                )
                
                // Average Profit
                EnhancedStatCard(
                    title: "Average Profit",
                    value: averageProfit,
                    prefix: "$",
                    subtext: "Per session",
                    color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
                )
            }
            
            HStack(spacing: 16) {
                // Total Sessions
                EnhancedStatCard(
                    title: "Total Sessions",
                    value: Double(totalSessions),
                    subtext: "Played",
                    color: .white
                )
                
                // Best Session
                EnhancedStatCard(
                    title: "Best Session",
                    value: bestSession?.profit ?? 0,
                    prefix: "$",
                    subtext: "Profit",
                    color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
                )
            }
        }
    }
}

// Enhanced stat card with consistent style
struct EnhancedStatCard: View {
    let title: String
    let value: Double
    var prefix: String = ""
    var suffix: String = ""
    var subtext: String = ""
    var isPercentage: Bool = false
    let color: Color
    
    private var formattedValue: String {
        if isPercentage {
            return String(format: "%.1f", value)
        } else {
            return "\(Int(value))"
        }
    }
    
    var body: some View {
        ZStack {
            // Glass-morphism background with subtle gradient
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)),
                            Color(UIColor(red: 25/255, green: 25/255, blue: 30/255, alpha: 1.0))
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.1),
                                    Color.clear,
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            
            VStack(spacing: 0) {
                // Title at top with subtle spacing
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                Spacer()
                
                // Central content based on type
                if isPercentage {
                    // Elegant circular progress for percentage
                    ZStack {
                        // Track
                        Circle()
                            .stroke(
                                Color.gray.opacity(0.1),
                                lineWidth: 6
                            )
                            .frame(width: 80, height: 80)
                        
                        // Progress
                        Circle()
                            .trim(from: 0, to: min(CGFloat(value / 100), 1.0))
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        color,
                                        color.opacity(0.8)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: value)
                        
                        // Value text with subtle shadow
                        VStack(spacing: 0) {
                            Text(formattedValue)
                                .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                            
                            Text(suffix)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(color)
                        }
                    }
                    .padding(.bottom, 16)
                } else {
                    // Clean large text display for non-percentages
                    VStack(spacing: 2) {
                        Text("\(prefix)\(formattedValue)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white) // Changed from color to white
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                        
                        if !subtext.isEmpty {
                            Text(subtext)
                                .font(.system(size: 13))
                                .foregroundColor(Color.gray.opacity(0.7))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                Spacer()
            }
        }
        .frame(height: 160)
    }
}



// MARK: - BankrollGraph - without the redundant header
struct BankrollGraph: View {
    let sessions: [Session]
    let selectedTimeRange: Int
    
    // Filter sessions based on selected time range
    private var filteredSessions: [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch selectedTimeRange {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessions
        }
    }
    
    private var dataPoints: [(Date, Double)] {
        var cumulative = 0.0
        let sorted = filteredSessions.sorted { $0.startDate < $1.startDate }
        
        // If no sessions in selected range, use placeholder data
        if sorted.isEmpty {
            return [
                (Date().addingTimeInterval(-86400 * 7), 0),
                (Date(), 0)
            ]
        }
        
        return sorted.map {
            cumulative += $0.profit
            return ($0.startDate, cumulative)
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        
        switch selectedTimeRange {
        case 0: // 24H
            formatter.dateFormat = "HH:mm"
        case 1: // 1W
            formatter.dateFormat = "EE"
        case 2: // 1M
            formatter.dateFormat = "d MMM"
        case 3: // 6M
            formatter.dateFormat = "MMM"
        case 4: // 1Y
            formatter.dateFormat = "MMM"
        default: // All
            formatter.dateFormat = "MMM yy"
        }
        
        return formatter
    }

    var body: some View {
        // Chart only - no header section
        VStack(spacing: 0) {
            // Chart with beautiful rendering
            ZStack {
                if filteredSessions.isEmpty {
                    Text("No sessions in selected period")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(height: 200)
                } else {
                    GeometryReader { geometry in
                        ZStack {
                            // Y-axis grid lines (subtle)
                            VStack(spacing: 0) {
                                ForEach(0..<5) { i in
                Spacer()
                                    Divider()
                                        .background(Color.gray.opacity(0.1))
                                }
                            }
                            
                            // Chart
                            ChartArea(dataPoints: dataPoints, geometry: geometry)
                                .offset(y: 5) // Small offset for aesthetics
                        }
                        .padding(.top, 5)
                        .padding(.bottom, 10) // Reduced padding since no date markers
                    }
                    .frame(height: 220)
                }
            }
            .padding(.bottom, 30) // Removed extra padding since no date markers
            
            // Removed date markers completely
        }
        .padding(.top, 4) // Reduced padding
        .padding(.bottom, 4) // Reduced padding
        .background(Color(UIColor(red: 19/255, green: 19/255, blue: 24/255, alpha: 0.4))) // More transparent
        .cornerRadius(18)
    }
}

struct ChartArea: View {
    let dataPoints: [(Date, Double)]
    let geometry: GeometryProxy
    
    private var minValue: Double {
        dataPoints.map { $0.1 }.min() ?? 0
    }
    
    private var maxValue: Double {
        let max = dataPoints.map { $0.1 }.max() ?? 0
        // Add 10% padding to max value
        return max * 1.1
    }
    
    private var valueRange: Double {
        max(maxValue - minValue, 1) // Avoid division by zero
    }
    
    private func yPosition(for value: Double) -> CGFloat {
        let normalizedValue = (value - minValue) / valueRange
        return geometry.size.height * (1 - CGFloat(normalizedValue))
    }

    var body: some View {
        ZStack {
            // Gradient area fill
            Path { path in
                guard dataPoints.count > 1 else { return }
                
                let step = geometry.size.width / CGFloat(dataPoints.count - 1)
                
                // Start at the bottom left
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                
                // Line to first data point
                path.addLine(to: CGPoint(x: 0, y: yPosition(for: dataPoints[0].1)))
                
                // Connect all data points
                for i in 1..<dataPoints.count {
                    let x = CGFloat(i) * step
                    let y = yPosition(for: dataPoints[i].1)
                    
                    // Create a smooth curve
                    if i > 0 {
                        let prevX = CGFloat(i-1) * step
                        let prevY = yPosition(for: dataPoints[i-1].1)
                        
                        let controlPoint1 = CGPoint(x: prevX + step/3, y: prevY)
                        let controlPoint2 = CGPoint(x: x - step/3, y: y)
                        
                        path.addCurve(to: CGPoint(x: x, y: y), 
                                      control1: controlPoint1, 
                                      control2: controlPoint2)
                    }
                }
                
                // Complete the path to bottom right and back to start
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.25)), location: 0),
                        .init(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.05)), location: 0.7),
                        .init(color: Color.clear, location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Line path with smooth curves
            Path { path in
                guard dataPoints.count > 1 else { return }
                
                let step = geometry.size.width / CGFloat(dataPoints.count - 1)
                
                // Start at first data point
                path.move(to: CGPoint(x: 0, y: yPosition(for: dataPoints[0].1)))
                
                // Connect all data points with smooth curves
                for i in 1..<dataPoints.count {
                    let x = CGFloat(i) * step
                    let y = yPosition(for: dataPoints[i].1)
                    
                    // Create a smooth curve
                    if i > 0 {
                        let prevX = CGFloat(i-1) * step
                        let prevY = yPosition(for: dataPoints[i-1].1)
                        
                        let controlPoint1 = CGPoint(x: prevX + step/3, y: prevY)
                        let controlPoint2 = CGPoint(x: x - step/3, y: y)
                        
                        path.addCurve(to: CGPoint(x: x, y: y), 
                                      control1: controlPoint1, 
                                      control2: controlPoint2)
                    }
                }
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)),
                        Color(UIColor(red: 100/255, green: 230/255, blue: 90/255, alpha: 1.0))
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.2)), radius: 3, y: 1)
            
            // Data points with smaller, more subtle glow
            ForEach(dataPoints.indices, id: \.self) { i in
                let x = CGFloat(i) * (geometry.size.width / CGFloat(dataPoints.count - 1))
                let y = yPosition(for: dataPoints[i].1)
                
                // Subtle glow effect
                Circle()
                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.15)))
                    .frame(width: 8, height: 8)
                    .position(x: x, y: y)
                
                // Main dot - reduced size
                Circle()
                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)
            }
        }
    }
}

// MARK: - Hands Tab
struct HandsTab: View {
    @ObservedObject var handStore: HandStore
    
    // Group hands by time periods
    private var groupedHands: (today: [SavedHand], lastWeek: [SavedHand], older: [SavedHand]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        
        var today: [SavedHand] = []
        var lastWeek: [SavedHand] = []
        var older: [SavedHand] = []
        
                for hand in handStore.savedHands {
            if calendar.isDate(hand.timestamp, inSameDayAs: now) {
                today.append(hand)
            } else if hand.timestamp >= oneWeekAgo && hand.timestamp < startOfToday {
                lastWeek.append(hand)
            } else {
                older.append(hand)
            }
        }
        
        return (today, lastWeek, older)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                // Add top padding
                Spacer()
                    .frame(height: 16)
                
                LazyVStack(spacing: 16) {
                    // Today's hands
                    if !groupedHands.today.isEmpty {
                        HandListSection(title: "Today", hands: groupedHands.today)
                    }
                    
                    // Last week's hands
                    if !groupedHands.lastWeek.isEmpty {
                        HandListSection(title: "Last Week", hands: groupedHands.lastWeek)
                    }
                    
                    // Older hands
                    if !groupedHands.older.isEmpty {
                        HandListSection(title: "All Time", hands: groupedHands.older)
                    }
                    
                    // Empty state
                    if handStore.savedHands.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                                .padding(.top, 40)
                            
                            Text("No Hands Recorded")
                                .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                            
                            Text("Your hand histories will appear here")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}

// Section header with hands
struct HandListSection: View {
    let title: String
    let hands: [SavedHand]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.85)) // Changed to greyish color
                
                Spacer()
                
                Text("\(hands.count) hands")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            // Hands in this section - keep original cards
            VStack(spacing: 12) {
                ForEach(hands) { savedHand in
                    HandSummaryRow(hand: savedHand.hand, id: savedHand.id)
                        .background(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Update HandSummaryRow
struct HandSummaryRow: View {
    let hand: ParsedHandHistory
    let id: String // Add ID for deletion
    @State private var showingReplay = false
    @State private var showingDeleteAlert = false
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var handStore: HandStore
    
    private func formatMoney(_ amount: Double) -> String {
        if amount >= 0 {
            return "$\(Int(amount))"
        } else {
            return "$\(abs(Int(amount)))"
        }
    }

    private var heroCards: [Card]? {
        if let hero = hand.raw.players.first(where: { $0.isHero }),
           let cards = hero.cards {
            return cards.map { Card(from: $0) }
        }
        return nil
    }
    
    private var handStrength: String? {
        hand.raw.players.first(where: { $0.isHero })?.finalHand
    }
    
    // Hero P&L for this hand
    private var heroPnl: Double {
        return hand.raw.pot.heroPnl
    }
    private var userId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Left: Cards display
            if let cards = heroCards {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        ForEach(cards, id: \.id) { card in
                            CardView(card: card)
                                .aspectRatio(0.69, contentMode: .fit)
                                .frame(width: 32, height: 46)
                                .shadow(color: .black.opacity(0.2), radius: 2)
                        }
                    }
                    
                    if let strength = handStrength {
                        Text(strength)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 10)
            }
            
            // Middle: Hand info (stakes, etc)
            VStack(alignment: .leading, spacing: 4) {
                // Stakes
                Text("\(formatMoney(hand.raw.gameInfo.smallBlind))/\(formatMoney(hand.raw.gameInfo.bigBlind))")
                        .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)))
                    )
                
                // Table size
                Text("\(hand.raw.gameInfo.tableSize) Players")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right: Profit and action
            VStack(alignment: .trailing, spacing: 8) {
                // P&L amount
                Text(formatMoney(heroPnl))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(heroPnl >= 0 ? 
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                    Color.red)
                    .shadow(color: heroPnl >= 0 ? 
                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)) : 
                            Color.red.opacity(0.3), radius: 2)
                
                // Action buttons
                HStack(spacing: 12) {
                    // Replay button
                    Button(action: {
                        showingReplay = true
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Delete button
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
            .padding(.trailing, 14)
                        .padding(.vertical, 10)
        }
        .padding(.vertical, 2)
        .background(
            // Modern glass-morphism style background
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor(red: 26/255, green: 26/255, blue: 32/255, alpha: 1.0)),
                        Color(UIColor(red: 22/255, green: 22/255, blue: 28/255, alpha: 1.0))
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.clear,
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        )
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Hand"),
                message: Text("Are you sure you want to delete this hand? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    // Delete the hand
                    Task {
                        do {
                            try await handStore.deleteHand(id: id)
                        } catch {
                            print("Error deleting hand: \(error.localizedDescription)")
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .fullScreenCover(isPresented: $showingReplay) {
            HandReplayView(hand: hand, userId: userId)
        }
    }
}

// MARK: - Sessions Tab
struct SessionsTab: View {
    @ObservedObject var sessionStore: SessionStore
    @State private var showingDeleteAlert = false
    @State private var selectedSession: Session? = nil
    @State private var showEditSheet = false
    @State private var editBuyIn = ""
    @State private var editCashout = ""
    @State private var editHours = ""
    @State private var showCalendarView = true
    @State private var selectedDate: Date? = nil
    @State private var currentMonth = Date()
    @State private var calendarAppearAnimation = false
    
    // Group sessions by time periods
    private var groupedSessions: (today: [Session], lastWeek: [Session], older: [Session]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        
        var today: [Session] = []
        var lastWeek: [Session] = []
        var older: [Session] = []
        
        // Sort sessions by start date (newest first)
        let sortedSessions = sessionStore.sessions.sorted(by: { $0.startDate > $1.startDate })
        
        for session in sortedSessions {
            if calendar.isDate(session.startDate, inSameDayAs: now) {
                today.append(session)
            } else if session.startDate >= oneWeekAgo && session.startDate < startOfToday {
                lastWeek.append(session)
            } else {
                older.append(session)
            }
        }
        
        return (today, lastWeek, older)
    }
    
    // Get sessions for a specific date
    private func sessionsForDate(_ date: Date) -> [Session] {
        let calendar = Calendar.current
        return sessionStore.sessions.filter { session in
            calendar.isDate(session.startDate, inSameDayAs: date)
        }.sorted(by: { $0.startDate > $1.startDate })
    }
    
    // Calculate monthly profit
    private func monthlyProfit(_ date: Date) -> Double {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        return sessionStore.sessions.filter { session in
            let sessionMonth = calendar.component(.month, from: session.startDate)
            let sessionYear = calendar.component(.year, from: session.startDate)
            return sessionMonth == month && sessionYear == year
        }.reduce(0) { $0 + $1.profit }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Calendar toggle button
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showCalendarView.toggle()
                        // Reset animation state when toggling
                        calendarAppearAnimation = false
                        // Delayed animation for when showing
                        if showCalendarView {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.6)) {
                                    calendarAppearAnimation = true
                                }
                            }
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        
                        Text(showCalendarView ? "Hide Calendar" : "Show Calendar")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Image(systemName: showCalendarView ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.7)))
                            .rotationEffect(Angle(degrees: showCalendarView ? 0 : -90))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showCalendarView)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 0.7)))
                            .shadow(color: Color.black.opacity(0.2), radius: 4, y: 2)
                    )
                }
                .buttonStyle(ScalePressButtonStyle())
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
            
        ScrollView {
                VStack(spacing: 22) {
                    // Calendar View
                    if showCalendarView {
                        LuxuryCalendarView(
                            sessions: sessionStore.sessions,
                            currentMonth: $currentMonth,
                            selectedDate: $selectedDate,
                            monthlyProfit: monthlyProfit(currentMonth),
                            isAnimated: calendarAppearAnimation
                        )
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.97))
                            )
                        )
                        .onAppear {
                            // Trigger animation when view appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.6)) {
                                    calendarAppearAnimation = true
                                }
                            }
                        }
                    }
                    
                    // Selected Date Sessions
                    if let selectedDate = selectedDate, !sessionsForDate(selectedDate).isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            // Date header
                            let formatter = DateFormatter()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(formatter.string(from: selectedDate))")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    let sessionsCount = sessionsForDate(selectedDate).count
                                    Text("\(sessionsCount) \(sessionsCount == 1 ? "session" : "sessions")")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.gray.opacity(0.8))
                                }
                                
                                Spacer()
                                
                                // Daily profit summary
                                let dailyProfit = sessionsForDate(selectedDate).reduce(0) { $0 + $1.profit }
                                Text(formatCurrency(dailyProfit))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(dailyProfit >= 0 ? 
                                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                                    Color.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(dailyProfit >= 0 ? 
                                                  Color(UIColor(red: 25/255, green: 45/255, blue: 30/255, alpha: 0.3)) : 
                                                  Color(UIColor(red: 45/255, green: 25/255, blue: 25/255, alpha: 0.3)))
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            
                            // Sessions for selected date with animation
                            VStack(spacing: 12) {
                                ForEach(Array(sessionsForDate(selectedDate).enumerated()), id: \.element.id) { index, session in
                                    EnhancedSessionSummaryRow(session: session, 
                                                              onSelect: {
                                        selectedSession = session
                                        editBuyIn = "\(Int(session.buyIn))"
                                        editCashout = "\(Int(session.cashout))"
                                        editHours = String(format: "%.1f", session.hoursPlayed)
                                        showEditSheet = true
                                    }, 
                                                              onDelete: {
                                        selectedSession = session
                                        showingDeleteAlert = true
                                    })
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                                        removal: .scale(scale: 0.95).combined(with: .opacity)
                                    ))
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 0.6)))
                                .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
                        )
                        .padding(.horizontal, 16)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    
                    // Today's sessions
                    if !groupedSessions.today.isEmpty && (selectedDate == nil || !Calendar.current.isDate(selectedDate!, inSameDayAs: Date())) {
                        EnhancedSessionsSection(title: "Today", sessions: groupedSessions.today, onSelect: { session in
                            selectedSession = session
                            editBuyIn = "\(Int(session.buyIn))"
                            editCashout = "\(Int(session.cashout))"
                            editHours = String(format: "%.1f", session.hoursPlayed)
                            showEditSheet = true
                        }, onDelete: { session in
                            selectedSession = session
                            showingDeleteAlert = true
                        })
                        .padding(.horizontal, 16)
                    }
                    
                    // Last week's sessions
                    if !groupedSessions.lastWeek.isEmpty {
                        EnhancedSessionsSection(title: "Last Week", sessions: groupedSessions.lastWeek, onSelect: { session in
                            selectedSession = session
                            editBuyIn = "\(Int(session.buyIn))"
                            editCashout = "\(Int(session.cashout))"
                            editHours = String(format: "%.1f", session.hoursPlayed)
                            showEditSheet = true
                        }, onDelete: { session in
                            selectedSession = session
                            showingDeleteAlert = true
                        })
                        .padding(.horizontal, 16)
                    }
                    
                    // Older sessions
                    if !groupedSessions.older.isEmpty {
                        EnhancedSessionsSection(title: "All Time", sessions: groupedSessions.older, onSelect: { session in
                            selectedSession = session
                            editBuyIn = "\(Int(session.buyIn))"
                            editCashout = "\(Int(session.cashout))"
                            editHours = String(format: "%.1f", session.hoursPlayed)
                            showEditSheet = true
                        }, onDelete: { session in
                            selectedSession = session
                            showingDeleteAlert = true
                        })
                        .padding(.horizontal, 16)
                    }
                    
                    // Empty state
                    if sessionStore.sessions.isEmpty {
                        EmptySessionsView()
                            .padding(32)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Session"),
                message: Text("Are you sure you want to delete this session? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let session = selectedSession {
                        Task {
                            do {
                                try await deleteSession(session.id)
                            } catch {
                                print("Error deleting session: \(error.localizedDescription)")
                            }
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showEditSheet) {
            if let session = selectedSession {
                EditSessionSheetView(
                    session: session,
                    buyIn: $editBuyIn,
                    cashout: $editCashout,
                    hours: $editHours,
                    onSave: {
                        updateSelectedSession()
                        showEditSheet = false
                    },
                    onCancel: {
                        showEditSheet = false
                    }
                )
            }
        }
    }
    
    // Format currency in a beautiful way
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
    
    // Function to delete session
    private func deleteSession(_ sessionId: String) async throws {
        try await sessionStore.deleteSession(sessionId) { error in
            if let error = error {
                print("Error deleting session: \(error.localizedDescription)")
            }
        }
    }
    
    // Update session with very basic logic
    private func updateSelectedSession() {
        guard let session = selectedSession,
              let buyInValue = Double(editBuyIn),
              let cashoutValue = Double(editCashout),
              let hoursPlayedValue = Double(editHours) else {
            return
        }
        
        // Create updated session data with minimal changes
        let updatedData: [String: Any] = [
            "hoursPlayed": hoursPlayedValue,
            "buyIn": buyInValue,
            "cashout": cashoutValue,
            "profit": cashoutValue - buyInValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Update in Firestore
        let db = Firestore.firestore()
        db.collection("sessions").document(session.id).updateData(updatedData) { error in
            if error == nil {
                // If successful, refresh sessions
                self.sessionStore.fetchSessions()
            } else {
                print("Error updating session: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
}

// Beautiful animated empty state
struct EmptySessionsView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 70))
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)))
                .padding(.top, 30)
                .scaleEffect(isAnimating ? 1.0 : 0.9)
                .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.15)), radius: 10, x: 0, y: 5)
            
            Text("No Sessions Recorded")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Start tracking your poker sessions to see your progress and analyze your performance")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}

// Enhanced section header
struct EnhancedSessionsSection: View {
    let title: String
    let sessions: [Session]
    let onSelect: (Session) -> Void
    let onDelete: (Session) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.85)) // Changed to greyish color
                
                Spacer()
                
                Text("\(sessions.count) sessions")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .padding(.horizontal, 8)
            
            // Sessions in this section
            VStack(spacing: 12) {
                ForEach(sessions) { session in
                    EnhancedSessionSummaryRow(session: session, onSelect: {
                        onSelect(session)
                    }, onDelete: {
                        onDelete(session)
                    })
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Luxury Calendar View
struct LuxuryCalendarView: View {
    let sessions: [Session]
    @Binding var currentMonth: Date
    @Binding var selectedDate: Date?
    let monthlyProfit: Double
    var isAnimated: Bool
    
    // Animation states
    @State private var isChangingMonth = false
    @State private var monthTransitionDirection: Double = 1 // 1 for next, -1 for prev
    @State private var isGridAnimated = false
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"] // Ultra minimal day indicators
    
    private var monthHeader: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: currentMonth).uppercased()
    }
    
    // Format currency in a beautiful way
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month header with animated arrows
            HStack {
                Text("\(monthHeader)")
                    .luxuryText(fontSize: 16, weight: .bold)
                    .foregroundColor(.white)
                    .opacity(isAnimated ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: isAnimated)
                    .offset(x: isChangingMonth ? monthTransitionDirection * -30 : 0)
                    .opacity(isChangingMonth ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isChangingMonth)
                
                Spacer()
                
                if monthlyProfit != 0 {
                    Text(formatCurrency(monthlyProfit))
                        .luxuryText(fontSize: 16, weight: .bold)
                        .foregroundColor(monthlyProfit > 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .opacity(isAnimated ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.2), value: isAnimated)
                        .offset(x: isChangingMonth ? monthTransitionDirection * -30 : 0)
                        .opacity(isChangingMonth ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isChangingMonth)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Previous month button
                    Button(action: {
                        hapticFeedback(style: .light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isChangingMonth = true
                            monthTransitionDirection = -1
                            isGridAnimated = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isChangingMonth = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        isGridAnimated = true
                                    }
                                }
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)))
                            .clipShape(Circle())
                    }
                    .buttonStyle(ScalePressButtonStyle())
                    
                    // Next month button
                    Button(action: {
                        hapticFeedback(style: .light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isChangingMonth = true
                            monthTransitionDirection = 1
                            isGridAnimated = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isChangingMonth = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        isGridAnimated = true
                                    }
                                }
                            }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)))
                            .clipShape(Circle())
                    }
                    .buttonStyle(ScalePressButtonStyle())
                }
                .opacity(isAnimated ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.15), value: isAnimated)
            }
            .padding(.horizontal, 8)
            
            VStack(spacing: 12) {
                // Days of the week header
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Color.gray.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .opacity(isAnimated ? 1 : 0)
                            .animation(.easeOut(duration: 0.3).delay(0.2), value: isAnimated)
                    }
                }
                
                // Calendar grid with staggered animation - FIX THE ERROR HERE
                LazyVGrid(columns: columns, spacing: 6) { // Reduced spacing
                    ForEach(Array(0..<daysInMonth().count), id: \.self) { index in
                        if let date = daysInMonth()[index] {
                            let dailyProfit = profitForDate(date)
                            let hasSession = sessionsForDate(date).count > 0
                            
                            MinimalistCalendarCell(
                                date: date,
                                dailyProfit: dailyProfit,
                                isSelected: selectedDate != nil && Calendar.current.isDate(date, inSameDayAs: selectedDate!),
                                hasSession: hasSession,
                                isAnimated: isAnimated && isGridAnimated,
                                animationDelay: Double(index % 7) * 0.03 + Double(index / 7) * 0.05
                            )
                            .onTapGesture {
                                hapticFeedback(style: .light)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    // Deselect if already selected
                                    if selectedDate != nil && Calendar.current.isDate(date, inSameDayAs: selectedDate!) {
                                        selectedDate = nil
                                    } else if hasSession {
                                        selectedDate = date
                                    }
                                }
                            }
                            .offset(x: isChangingMonth ? monthTransitionDirection * 30 : 0)
                            .opacity(isChangingMonth ? 0 : 1)
                            .animation(
                                .easeInOut(duration: 0.3)
                                .delay(Double(index % 7) * 0.01),
                                value: isChangingMonth
                            )
                        } else {
                            // Empty cell with subtle animation
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .padding(.horizontal, 6) // Reduced horizontal padding
            .opacity(isChangingMonth ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.3), value: isChangingMonth)
        }
        .padding(16) // Reduced padding
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)))
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
        )
            .onAppear {
            // Initialize animation state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isGridAnimated = true
                }
            }
        }
    }
    
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    // Generate array of dates for the calendar grid
    private func daysInMonth() -> [Date?] {
        let calendar = Calendar.current
        
        // Find the first day of the month
        let components = calendar.dateComponents([.year, .month], from: currentMonth)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth)
        else { return [] }
        
        let numDays = range.count
        
        // Find day of week for first day (0 = Sunday in iOS, but we want Monday = 0)
        var firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 2
        if firstWeekday < 0 { firstWeekday += 7 } // Adjust for Sunday
        
        var days = [Date?]()
        
        // Add empty cells for days before the 1st
        for _ in 0..<firstWeekday {
            days.append(nil)
        }
        
        // Add a cell for each day of the month
        for day in 1...numDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        // Add empty cells to complete the grid if needed
        let remainder = (days.count % 7)
        if remainder > 0 {
            for _ in 0..<(7 - remainder) {
                days.append(nil)
            }
        }
        
        return days
    }
    
    // Calculate profit for a specific date
    private func profitForDate(_ date: Date) -> Double {
        let sessionProfit = sessionsForDate(date).reduce(0) { $0 + $1.profit }
        return sessionProfit
    }
    
    // Get sessions for a specific date
    private func sessionsForDate(_ date: Date) -> [Session] {
        let calendar = Calendar.current
        return sessions.filter { session in
            calendar.isDate(session.startDate, inSameDayAs: date)
        }
    }
}

// Super minimalist calendar cell
struct MinimalistCalendarCell: View {
    let date: Date
    let dailyProfit: Double
    let isSelected: Bool
    let hasSession: Bool
    let isAnimated: Bool
    let animationDelay: Double
    
    private var dayNumber: String {
        let calendar = Calendar.current
        return "\(calendar.component(.day, from: date))"
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private func formatAmount(_ amount: Double) -> String {
        let absAmount = abs(amount)
        if absAmount >= 1000 {
            return String(format: "$%.1fk", absAmount / 1000)
        } else {
            return "$\(Int(absAmount))"
        }
    }
    
    // Determine cell background color based on state and profit
    private var cellColor: Color {
        if isSelected {
            return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3))
        } else if hasSession {
            if dailyProfit > 0 {
                return Color(UIColor(red: 22/255, green: 45/255, blue: 30/255, alpha: 0.7))
            } else {
                return Color(UIColor(red: 45/255, green: 22/255, blue: 22/255, alpha: 0.7))
            }
        } else {
            return Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 0.5))
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Day number
            Text(dayNumber)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .white)
                .fixedSize(horizontal: true, vertical: false) // Prevent truncation
                .frame(maxWidth: .infinity)
            
            // Profit indicator (if has session)
            if hasSession {
                Text(formatAmount(dailyProfit))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(
                        dailyProfit > 0 ? 
                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                            Color.red
                    )
                    .fixedSize(horizontal: true, vertical: false) // Prevent truncation
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(cellColor)
        .cornerRadius(8)
        .overlay(
            Group {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.white.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1, dash: [])
                        )
                }
            }
        )
        .scaleEffect(isAnimated ? 1.0 : 0.8)
        .opacity(isAnimated ? 1.0 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1 + animationDelay), value: isAnimated)
        // Add subtle hover effect for interactive feel
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// Enhanced session card - more minimal version
struct EnhancedSessionSummaryRow: View {
    let session: Session
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var showingActions = false
    
    private func formatMoney(_ amount: Double) -> String {
            return "$\(abs(Int(amount)))"
        }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"  // Shorter date format
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with game info and profit
            HStack(alignment: .center) {
                // Game info with icon removed
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.gameName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(session.stakes)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.gray.opacity(0.8))
                }
                
                Spacer()
                
                // Profit amount
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatMoney(session.profit))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(session.profit >= 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .padding(.bottom, 2)
                    
                    // Date and hours in one line
                    HStack(spacing: 6) {
                        Text(formatDate(session.startDate))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color.gray.opacity(0.7))
                        
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(Color.gray.opacity(0.5))
                        
                        Text("\(String(format: "%.1f", session.hoursPlayed))h")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color.gray.opacity(0.7))
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)))
        )
        .contextMenu {
            Button(action: onSelect) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onTapGesture {
            hapticFeedback(style: .light)
            onSelect()
        }
    }
    
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - EditSessionSheetView
struct EditSessionSheetView: View {
    let session: Session
    @Binding var buyIn: String
    @Binding var cashout: String
    @Binding var hours: String
    var onSave: () -> Void
    var onCancel: () -> Void
    @State private var isSaving = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor(red: 18/255, green: 18/255, blue: 23/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Session summary section
                        VStack(spacing: 16) {
                            // Game info
                            HStack {
                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.gameName)
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                                    
                                    Text(session.stakes)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color(UIColor(red: 30/255, green: 30/255, blue: 38/255, alpha: 1.0)))
                                        )
                                }
                                
                Spacer()
                                
                                // Date
                                let dateFormatter = DateFormatter()
                                Text(dateFormatter.string(from: session.startDate))
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.gray)
                            }
                            
                            Divider()
                                .background(Color.gray.opacity(0.2))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // Form fields with beautiful styling
                        VStack(spacing: 24) {
                            // Buy In
                            LuxuryFormField(
                                icon: "arrow.down.circle.fill",
                                iconColor: Color(UIColor(red: 255/255, green: 100/255, blue: 100/255, alpha: 1.0)),
                                title: "Buy-in",
                                value: $buyIn,
                                prefix: "$",
                                keyboardType: .numberPad
                            )
                            
                            // Cashout
                            LuxuryFormField(
                                icon: "arrow.up.circle.fill",
                                iconColor: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)),
                                title: "Cashout",
                                value: $cashout,
                                prefix: "$",
                                keyboardType: .numberPad
                            )
                            
                            // Hours
                            LuxuryFormField(
                                icon: "clock.fill",
                                iconColor: Color.blue.opacity(0.8),
                                title: "Hours Played",
                                value: $hours,
                                prefix: "",
                                keyboardType: .decimalPad
                            )
                            
                            // Live profit calculation
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(UIColor(red: 25/255, green: 25/255, blue: 30/255, alpha: 1.0)),
                                                Color(UIColor(red: 22/255, green: 22/255, blue: 28/255, alpha: 1.0))
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                                
                                let buyInValue = Double(buyIn) ?? 0
                                let cashoutValue = Double(cashout) ?? 0
                                let profit = cashoutValue - buyInValue
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Profit")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.gray)
                                        
                                        Text(formatCurrency(profit))
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .foregroundColor(profit >= 0 ? 
                                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                                Color(UIColor(red: 255/255, green: 100/255, blue: 100/255, alpha: 1.0))
                                            )
                                    }
                                    
                Spacer()
                                    
                                    // Rate calculation
                                    let hoursValue = Double(hours) ?? 0
                                    let hourlyRate = hoursValue > 0 ? profit / hoursValue : 0
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Hourly")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.gray)
                                        
                                        Text("\(formatCurrency(hourlyRate))/h")
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundColor(hourlyRate >= 0 ? 
                                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                                Color(UIColor(red: 255/255, green: 100/255, blue: 100/255, alpha: 1.0))
                                            )
                                    }
                                }
                                .padding(16)
                            }
                            .frame(height: 90)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            
                            // Save button
                            Button(action: {
                                isSaving = true
                                // Small delay to show loading animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    onSave()
                                    isSaving = false
                                }
                            }) {
                                ZStack {
                                    // Button background
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)),
                                                    Color(UIColor(red: 100/255, green: 230/255, blue: 85/255, alpha: 0.8))
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.2)), radius: 10, y: 5)
                                    
                                    if isSaving {
                                        // Loading spinner
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .scaleEffect(1.2)
                                    } else {
                                        // Text
                                        Text("Save Changes")
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                                    }
                                }
                                .frame(height: 58)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            }
                            .buttonStyle(ScalePressButtonStyle())
                            .disabled(buyIn.isEmpty || cashout.isEmpty || hours.isEmpty || isSaving)
                            .opacity(buyIn.isEmpty || cashout.isEmpty || hours.isEmpty ? 0.6 : 1.0)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: 
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
            )
        }
        .preferredColorScheme(.dark)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
}

// Beautiful form field component
struct LuxuryFormField: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var value: String
    let prefix: String
    let keyboardType: UIKeyboardType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Field title
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
            
            // Input field
            HStack(alignment: .center, spacing: 8) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                TextField("0", text: $value)
                    .keyboardType(keyboardType)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(height: 54)
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)))
                    .shadow(color: Color.black.opacity(0.1), radius: 3, y: 1)
            )
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Button Styles
struct ScalePressButtonStyle: ButtonStyle {
    let scaleAmount: CGFloat = 0.95
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Adds a gentle hover effect for interactive elements
struct HoverEffectModifier: ViewModifier {
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .shadow(color: isHovering ? Color.black.opacity(0.2) : Color.black.opacity(0.1), 
                    radius: isHovering ? 8 : 5, 
                    y: isHovering ? 4 : 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func hoverEffect() -> some View {
        self.modifier(HoverEffectModifier())
    }
    
    // Add elegant transition to any view
    func elegantTransition() -> some View {
        self.transition(
            .asymmetric(
                insertion: .scale(scale: 0.97).combined(with: .opacity),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            )
        )
    }
    
    // Custom modifier for gorgeous text
    func luxuryText(fontSize: CGFloat, weight: Font.Weight = .medium) -> some View {
        self
            .font(.system(size: fontSize, weight: weight, design: .rounded))
            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

extension EnhancedSessionSummaryRow {
    func formatCurrency(_ amount: Double) -> String {
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
}



