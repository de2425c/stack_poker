import SwiftUI
import FirebaseFirestore
import Charts
import UIKit
import FirebaseAuth

struct DashboardView: View {
    @StateObject private var handStore: HandStore
    @StateObject private var sessionStore: SessionStore
    @StateObject private var bankrollStore: BankrollStore
    @StateObject private var postService = PostService()
    @EnvironmentObject private var userService: UserService
    @State private var selectedTimeRange = 1 // Default to 1W (index 1)
    @State private var selectedTab: Int // Changed to be initialized with parameter
    @State private var showingBankrollSheet = false
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"]
    
    init(userId: String, initialSelectedTab: Int = 0) {
        let bankrollStore = BankrollStore(userId: userId)
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId, bankrollStore: bankrollStore))
        _bankrollStore = StateObject(wrappedValue: bankrollStore)
        // Initialize selectedTab with the provided parameter
        _selectedTab = State(initialValue: initialSelectedTab)
        
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 18/255, green: 18/255, blue: 23/255, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor.white
    }
    
    private var totalBankroll: Double {
        // Calculate total bankroll: session profits + manual bankroll adjustments
        let sessionProfitTotal = sessionStore.sessions.reduce(0) { $0 + $1.profit }
        return sessionProfitTotal + bankrollStore.bankrollSummary.currentTotal
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

    // MARK: - New Computed Properties for Stats Grid (similar to ProfileView)
    private var totalHoursPlayed: Double {
        return sessionStore.sessions.reduce(0) { $0 + $1.hoursPlayed }
    }

    private var averageSessionLength: Double {
        if totalSessions == 0 { return 0 }
        return totalHoursPlayed / Double(totalSessions)
    }
    
    // MARK: - Computed Properties for Carousel Stats (similar to ProfileView)
    private var highestCashoutToBuyInRatio: (ratio: Double, session: Session)? {
        guard !sessionStore.sessions.isEmpty else { return nil }
        
        var maxRatio: Double = 0
        var sessionWithMaxRatio: Session? = nil
        
        for session in sessionStore.sessions {
            if session.buyIn > 0 { // Avoid division by zero
                let ratio = session.cashout / session.buyIn
                if ratio > maxRatio {
                    maxRatio = ratio
                    sessionWithMaxRatio = session
                }
            }
        }
        
        if let session = sessionWithMaxRatio, maxRatio > 0 { // Ensure there was a valid ratio found
            return (maxRatio, session)
        }
        return nil
    }

    enum TimeOfDayCategory: String, CaseIterable, Identifiable {
        case morning = "Morning Pro"
        case afternoon = "Afternoon Grinder"
        case evening = "Evening Shark"
        case night = "Night Owl"
        case unknown = "Versatile Player"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .morning: return "sun.max.fill"
            case .afternoon: return "cloud.sun.fill"
            case .evening: return "moon.stars.fill"
            case .night: return "zzz"
            case .unknown: return "questionmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .morning: return .yellow
            case .afternoon: return .orange
            case .evening: return .purple
            case .night: return .blue
            case .unknown: return .gray
            }
        }
    }

    private var pokerPersona: (category: TimeOfDayCategory, dominantHours: String) {
        guard !sessionStore.sessions.isEmpty else {
            return (.unknown, "N/A")
        }

        var morningSessions = 0 // 5 AM - 11:59 AM
        var afternoonSessions = 0 // 12 PM - 4:59 PM
        var eveningSessions = 0   // 5 PM - 8:59 PM
        var nightSessions = 0     // 9 PM - 4:59 AM

        let calendar = Calendar.current
        for session in sessionStore.sessions {
            let hour = calendar.component(.hour, from: session.startTime)
            switch hour {
            case 5..<12: morningSessions += 1
            case 12..<17: afternoonSessions += 1
            case 17..<21: eveningSessions += 1
            case 21..<24, 0..<5: nightSessions += 1
            default: break
            }
        }

        let counts = [
            TimeOfDayCategory.morning: morningSessions,
            TimeOfDayCategory.afternoon: afternoonSessions,
            TimeOfDayCategory.evening: eveningSessions,
            TimeOfDayCategory.night: nightSessions
        ]
        
        let totalPlaySessions = Double(morningSessions + afternoonSessions + eveningSessions + nightSessions)
        if totalPlaySessions == 0 { return (.unknown, "N/A")}

        var persona: TimeOfDayCategory = .unknown
        var maxCount = 0
        var dominantPeriodName = "N/A"

        for (category, count) in counts {
            if count > maxCount {
                maxCount = count
                persona = category
                dominantPeriodName = category.rawValue.components(separatedBy: " ").first ?? category.rawValue // e.g., "Morning"
            }
        }
        
        if maxCount == 0 { return (.unknown, "No dominant time") } // if all counts are 0
        
        let percentage = (Double(maxCount) / totalPlaySessions * 100)
        let dominantHoursString = "\(dominantPeriodName): \(String(format: "%.0f%%", percentage))"
        
        return (persona, dominantHoursString)
    }
    
    private var topLocation: (location: String, count: Int)? {
        guard !sessionStore.sessions.isEmpty else { return nil }
        
        let locationsFromSessions = sessionStore.sessions.map { session -> String? in
            let trimmedLocation = session.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let loc = trimmedLocation, !loc.isEmpty {
                return loc
            }
            let trimmedGameName = session.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGameName.isEmpty {
                return trimmedGameName 
            }
            return nil
        }

        let validLocations = locationsFromSessions.compactMap { $0 }.filter { !$0.isEmpty }
        if validLocations.isEmpty { return nil }
        
        let locationCounts = validLocations.reduce(into: [:]) { counts, location in counts[location, default: 0] += 1 }
        
        if let (topLoc, count) = locationCounts.max(by: { $0.value < $1.value }) {
            return (topLoc, count)
        }
        return nil
    }
    
    var body: some View {
        NavigationView {
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
                                timeRangeProfit: selectedTimeRangeProfit,
                                onAdjustBankroll: {
                                    showingBankrollSheet = true
                                }
                            )
                            .padding(.top, 6) // Reduced top padding
                            .padding(.bottom, 2) // Minimal padding to move cards up
                            
                            // Stats Cards
                            EnhancedStatsCardGrid(
                                winRate: winRate,
                                averageProfit: averageProfit,
                                totalSessions: totalSessions,
                                bestSession: bestSession,
                                totalHoursPlayed: totalHoursPlayed, // Pass new stat
                                averageSessionLength: averageSessionLength // Pass new stat
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            
                            // Highlight Carousel Section
                            Text("HIGHLIGHTS")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 10) // Space above carousel

                            HighlightStatsCarousel(
                                highestCashoutToBuyInRatio: highestCashoutToBuyInRatio,
                                pokerPersona: pokerPersona,
                                topLocation: topLocation
                            )
                            .frame(height: 220) // Give the carousel a decent height
                            .padding(.bottom, 16)
                            
                        } else if selectedTab == 1 {
                            // HANDS TAB
                            HandsTab(handStore: handStore)
                            
                        } else {
                            // SESSIONS TAB
                            SessionsTab(sessionStore: sessionStore, bankrollStore: bankrollStore)
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
            .navigationBarHidden(true) // Hide the top navigation bar
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Use StackNavigationViewStyle for proper push navigation
        .sheet(isPresented: $showingBankrollSheet) {
            BankrollAdjustmentSheet(bankrollStore: bankrollStore, currentTotalBankroll: totalBankroll)
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
    let onAdjustBankroll: () -> Void
    
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
                // Bankroll header with inline edit button
                HStack(alignment: .center, spacing: 6) {
                    Text("Bankroll")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.7))

                    // Inline edit button (moved from value row)
                    Button(action: onAdjustBankroll) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.horizontal, 2)
                
                HStack(alignment: .center, spacing: 0) {
                    Text("$\(Int(totalProfit))")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                }
                
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
            
            // Edit Bankroll button underneath chart
            HStack {
                Button(action: onAdjustBankroll) {
                    Text("Edit Bankroll")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16) // Space between chart and button
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
    let totalHoursPlayed: Double // New
    let averageSessionLength: Double // New
    
    var body: some View {
        VStack(spacing: 12) { // Reduced spacing between rows of cards
            HStack(spacing: 12) { // Reduced spacing between cards in a row
                // Win Rate
                EnhancedStatCard(
                    title: "Win Rate",
                    value: winRate,
                    suffix: "%",
                    isPercentage: true,
                    iconName: "chart.pie.fill", // Added icon
                    accentColor: Color(hex: "34D399") // Greenish
                )
                
                // Average Profit
                EnhancedStatCard(
                    title: "Avg. Profit",
                    value: averageProfit,
                    prefix: "$",
                    subtext: "/ session", // More concise
                    iconName: "dollarsign.arrow.circlepath", // Added icon
                    accentColor: Color(hex: "60A5FA") // Bluish
                )
            }
            
            HStack(spacing: 12) {
                // Total Sessions
                EnhancedStatCard(
                    title: "Total Sessions",
                    value: Double(totalSessions),
                    subtext: "Played",
                    iconName: "list.star", // Added icon
                    accentColor: Color(hex: "FBBF24") // Amber/Yellow
                )
                
                // Best Session
                EnhancedStatCard(
                    title: "Best Session",
                    value: bestSession?.profit ?? 0,
                    prefix: "$",
                    subtext: "Profit",
                    iconName: "star.fill", // Added icon
                    accentColor: Color(hex: "EC4899") // Pinkish
                )
            }
             HStack(spacing: 12) {
                // Total Hours Played
                EnhancedStatCard(
                    title: "Hours Played",
                    value: totalHoursPlayed,
                    suffix: " hrs",
                    iconName: "hourglass",
                    accentColor: Color(hex: "A78BFA") // Purplish
                )
                
                // Average Session Length
                EnhancedStatCard(
                    title: "Avg. Length",
                    value: averageSessionLength,
                    suffix: " hrs",
                    iconName: "timer",
                    accentColor: Color(hex: "2DD4BF") // Tealish
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
    let iconName: String // New: System icon name
    let accentColor: Color // New: Color for icon and subtle accents

    private var formattedValue: String {
        if isPercentage {
            return String(format: "%.1f", value)
        } else {
            // Format as integer if it's a whole number, else one decimal place
            return value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { // Overall card content
            HStack { // Header: Icon and Title
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.75))
                Spacer()
            }
            
            Spacer() // Pushes value to center/bottom

            HStack(alignment: .firstTextBaseline) { // Value and Suffix (if any)
                Text("\(prefix)\(formattedValue)")
                    .font(.system(size: 26, weight: .bold, design: .rounded)) // Main value text
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.leading, -2) // Snug suffix
                }
            }

            if !subtext.isEmpty {
                Text(subtext)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.8))
            }
            
            Spacer() // Pushes subtext to bottom if no percentage circle

            if isPercentage { // Circular progress for percentage
                ZStack {
                    Circle() // Track
                        .stroke(accentColor.opacity(0.15), lineWidth: 7)
                    Circle() // Progress
                        .trim(from: 0, to: min(CGFloat(value / 100), 1.0))
                        .stroke(
                            LinearGradient(gradient: Gradient(colors: [accentColor, accentColor.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: value)
                    Text("\(formattedValue)%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60) // Adjust size as needed
                .padding(.top, 4) // Space for the circle
                Spacer()
            }
        }
        .padding(14) // Inner padding for card content
        .frame(maxWidth: .infinity, minHeight: 130) // Ensure cards have a good minimum height
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.30) // Slightly less transparent material
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.15)) // Darker overlay for more depth

                RoundedRectangle(cornerRadius: 20) // Subtle highlight/border
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                accentColor.opacity(0.5),
                                accentColor.opacity(0.2),
                                Color.white.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Highlight Stats Carousel
struct HighlightStatsCarousel: View {
    let highestCashoutToBuyInRatio: (ratio: Double, session: Session)?
    let pokerPersona: (category: DashboardView.TimeOfDayCategory, dominantHours: String)
    let topLocation: (location: String, count: Int)?

    @State private var selectedPageIndex = 0

    struct CarouselItem: Identifiable {
        let id = UUID()
        let type: HighlightType
        var title: String
        var iconName: String
        var accentColor: Color
        var detail1: String? = nil
        var detail2: String? = nil
        var detail3: String? = nil
        var value: String
    }

    enum HighlightType {
        case multiplier
        case persona
        case location
    }

    private var carouselItems: [CarouselItem] {
        var items: [CarouselItem] = []

        if let ratioData = highestCashoutToBuyInRatio {
            items.append(CarouselItem(
                type: .multiplier,
                title: "Best Multiplier",
                iconName: "flame.fill",
                accentColor: .pink,
                detail1: "Buy-in: $\\(Int(ratioData.session.buyIn).formattedWithCommas)",
                detail2: "Cash-out: $\\(Int(ratioData.session.cashout).formattedWithCommas)",
                value: String(format: "%.1fx ROI", ratioData.ratio)
            ))
        }

        items.append(CarouselItem(
            type: .persona,
            title: "Your Grind Style",
            iconName: pokerPersona.category.icon,
            accentColor: pokerPersona.category.color,
            detail1: pokerPersona.category.rawValue,
            detail2: pokerPersona.dominantHours,
            value: "" // Main value can be part of details here
        ))

        if let locData = topLocation {
            items.append(CarouselItem(
                type: .location,
                title: "Hot Spot",
                iconName: "mappin.and.ellipse",
                accentColor: .indigo,
                detail1: locData.location,
                detail2: "Played \\(locData.count)x",
                value: "" // Main value can be part of details here
            ))
        }
        return items.filter { $0.title != "N/A" } // Filter out empty/default states
    }
    
    private func formatValue(_ value: String, type: HighlightType) -> Text {
        if type == .multiplier {
            return Text(value).font(.system(size: 38, weight: .bold, design: .rounded))
        }
        return Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)) // Default for others if value is used
    }


    var body: some View {
        VStack(spacing: 0) {
            if carouselItems.isEmpty {
                Text("More stats available as you log sessions.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Material.ultraThinMaterial.opacity(0.2))
                    )
                    .padding(.horizontal, 16)

            } else {
                TabView(selection: $selectedPageIndex) {
                    ForEach(carouselItems.indices, id: \.self) { index in
                        let item = carouselItems[index]
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: item.iconName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(item.accentColor)
                                Text(item.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.bottom, 5)

                            if !item.value.isEmpty {
                                formatValue(item.value, type: item.type)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            
                            if let detail1 = item.detail1, !detail1.isEmpty {
                                Text(detail1)
                                    .font(.system(size: item.type == .persona && item.value.isEmpty ? 22 : 15, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.85))
                            }
                            if let detail2 = item.detail2, !detail2.isEmpty {
                                Text(detail2)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundColor(Color.gray)
                            }
                            if let detail3 = item.detail3, !detail3.isEmpty {
                                Text(detail3)
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(Color.gray.opacity(0.9))
                            }
                            Spacer()
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Material.ultraThinMaterial.opacity(0.35))
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.black.opacity(0.25)) // Slightly darker base
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [item.accentColor.opacity(0.6), item.accentColor.opacity(0.2), Color.white.opacity(0.05)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                                // Inner subtle glow
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(item.accentColor)
                                    .blur(radius: 40)
                                    .opacity(0.15)
                                    .blendMode(.overlay)

                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                        .padding(.horizontal, 16) // Padding for each tab item
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Hide default dots
                .frame(height: 180) // Explicit height for TabView content area

                // Custom Page Indicator
                HStack(spacing: 8) {
                    ForEach(carouselItems.indices, id: \.self) { index in
                        Circle()
                            .fill(selectedPageIndex == index ? Color.white : Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .animation(.spring(), value: selectedPageIndex)
                    }
                }
                .padding(.top, 10)
            }
        }
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


// Section header with hands


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
    @ObservedObject var bankrollStore: BankrollStore
    @EnvironmentObject private var userService: UserService
    @State private var showingDeleteAlert = false
    @State private var selectedSession: Session? = nil
    @State private var showEditSheet = false
    @State private var editBuyIn = ""
    @State private var editCashout = ""
    @State private var editHours = ""
    @State private var isCalendarExpanded: Bool = true // Calendar starts expanded
    @State private var selectedDate: Date? = nil
    @State private var currentMonth = Date()
    
    // Combined sessions and transactions grouped by time periods
    private var groupedItems: (today: [SessionOrTransaction], lastWeek: [SessionOrTransaction], older: [SessionOrTransaction]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        
        var today: [SessionOrTransaction] = []
        var lastWeek: [SessionOrTransaction] = []
        var older: [SessionOrTransaction] = []
        
        // Convert sessions to SessionOrTransaction
        let sessionItems = sessionStore.sessions.map { SessionOrTransaction.session($0) }
        
        // Convert bankroll transactions to SessionOrTransaction
        let transactionItems = bankrollStore.transactions.map { SessionOrTransaction.transaction($0) }
        
        // Combine and sort by date (newest first)
        let allItems = (sessionItems + transactionItems).sorted { item1, item2 in
            switch (item1, item2) {
            case let (.session(s1), .session(s2)):
                return s1.startDate > s2.startDate
            case let (.transaction(t1), .transaction(t2)):
                return t1.timestamp > t2.timestamp
            case let (.session(s), .transaction(t)):
                return s.startDate > t.timestamp
            case let (.transaction(t), .session(s)):
                return t.timestamp > s.startDate
            }
        }
        
        for item in allItems {
            let itemDate: Date
            switch item {
            case .session(let session):
                itemDate = session.startDate
            case .transaction(let transaction):
                itemDate = transaction.timestamp
            }
            
            if calendar.isDate(itemDate, inSameDayAs: now) {
                today.append(item)
            } else if itemDate >= oneWeekAgo && itemDate < startOfToday {
                lastWeek.append(item)
            } else {
                older.append(item)
            }
        }
        
        return (today, lastWeek, older)
    }
    
    // Get items for a specific date
    private func itemsForDate(_ date: Date) -> [SessionOrTransaction] {
        let calendar = Calendar.current
        let sessionItems = sessionStore.sessions.filter { session in
            calendar.isDate(session.startDate, inSameDayAs: date)
        }.map { SessionOrTransaction.session($0) }
        
        let transactionItems = bankrollStore.transactions.filter { transaction in
            calendar.isDate(transaction.timestamp, inSameDayAs: date)
        }.map { SessionOrTransaction.transaction($0) }
        
        return (sessionItems + transactionItems).sorted { item1, item2 in
            switch (item1, item2) {
            case let (.session(s1), .session(s2)):
                return s1.startDate > s2.startDate
            case let (.transaction(t1), .transaction(t2)):
                return t1.timestamp > t2.timestamp
            case let (.session(s), .transaction(t)):
                return s.startDate > t.timestamp
            case let (.transaction(t), .session(s)):
                return t.timestamp > s.startDate
            }
        }
    }
    
    // Calculate monthly profit including bankroll adjustments
    private func monthlyProfit(_ date: Date) -> Double {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        let sessionProfit = sessionStore.sessions.filter { session in
            let sessionMonth = calendar.component(.month, from: session.startDate)
            let sessionYear = calendar.component(.year, from: session.startDate)
            return sessionMonth == month && sessionYear == year
        }.reduce(0) { $0 + $1.profit }
        
        let bankrollProfit = bankrollStore.transactions.filter { transaction in
            let transactionMonth = calendar.component(.month, from: transaction.timestamp)
            let transactionYear = calendar.component(.year, from: transaction.timestamp)
            return transactionMonth == month && transactionYear == year
        }.reduce(0) { $0 + $1.amount }
        
        return sessionProfit + bankrollProfit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Root VStack of SessionsTab
            // The old compact calendar toggle button is removed from here.
            
            ScrollView {
                VStack(spacing: 22) {
                    // Calendar View - always part of the layout, its content visibility is handled internally
                    LuxuryCalendarView(
                        sessions: sessionStore.sessions,
                        currentMonth: $currentMonth,
                        selectedDate: $selectedDate,
                        monthlyProfit: monthlyProfit(currentMonth),
                        isExpanded: $isCalendarExpanded // Pass binding
                    )
                    .padding(.top, 20) // Increased top padding for LuxuryCalendarView component
                    .padding(.horizontal, 8) 
                    
                    // Selected Date Items
                    if let selectedDate = selectedDate, !itemsForDate(selectedDate).isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            // Date header
                            let formatter = DateFormatter()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(formatter.string(from: selectedDate))")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    let itemsCount = itemsForDate(selectedDate).count
                                    Text("\(itemsCount) \(itemsCount == 1 ? "item" : "items")")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.gray.opacity(0.8))
                                }
                                
                                Spacer()
                                
                                // Daily profit summary (sessions + bankroll adjustments)
                                let dailyProfit = itemsForDate(selectedDate).reduce(0) { total, item in
                                    switch item {
                                    case .session(let session):
                                        return total + session.profit
                                    case .transaction(let transaction):
                                        return total + transaction.amount
                                    }
                                }
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
                            
                            // Items for selected date with animation
                            VStack(spacing: 12) {
                                ForEach(Array(itemsForDate(selectedDate).enumerated()), id: \.element.id) { index, item in
                                    switch item {
                                    case .session(let session):
                                        EnhancedSessionSummaryRow(
                                            session: session,
                                            onSelect: {
                                                selectedSession = session
                                            },
                                            onDelete: {
                                                selectedSession = session
                                                showingDeleteAlert = true
                                            }
                                        )
                                    case .transaction(let transaction):
                                        BankrollTransactionRow(transaction: transaction)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.vertical, 8)
                        .background(
                            ZStack { // Applying GlassyInputField style
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.2)
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.01))
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5) // Subtle border
                            }
                            // .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2) // Remove or make very subtle
                        )
                        .padding(.horizontal, 16)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    
                    // Today's items
                    if !groupedItems.today.isEmpty && (selectedDate == nil || !Calendar.current.isDate(selectedDate!, inSameDayAs: Date())) {
                        EnhancedItemsSection(title: "Today", items: groupedItems.today, 
                                                onSelect: { session in
                                                    selectedSession = session
                                                }, 
                                                onDelete: { session in
                            selectedSession = session
                            showingDeleteAlert = true
                        })
                        .padding(.horizontal, 16)
                    }
                    
                    // Last week's items
                    if !groupedItems.lastWeek.isEmpty {
                        EnhancedItemsSection(title: "Last Week", items: groupedItems.lastWeek, 
                                                onSelect: { session in
                                                    selectedSession = session
                                                }, 
                                                onDelete: { session in
                            selectedSession = session
                            showingDeleteAlert = true
                        })
                        .padding(.horizontal, 16)
                    }
                    
                    // Older items
                    if !groupedItems.older.isEmpty {
                        EnhancedItemsSection(title: "All Time", items: groupedItems.older, 
                                                onSelect: { session in
                                                    selectedSession = session
                                                }, 
                                                onDelete: { session in
                            selectedSession = session
                            showingDeleteAlert = true
                        })
                        .padding(.horizontal, 16)
                    }
                    
                    // Empty state
                    if sessionStore.sessions.isEmpty && bankrollStore.transactions.isEmpty {
                        EmptySessionsView()
                            .padding(32)
                    }
                }
                .padding(.bottom, 16)
            }
            // .padding(.top, 40) // Remove this, top padding applied to root VStack
        }
        .padding(.top, 50) // Apply 50 points of top padding to the root VStack of SessionsTab
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Session"),
                message: Text("Are you sure you want to delete this session? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let sessionToDelete = selectedSession {
                        Task {
                            // Call the existing deleteSession method in SessionStore
                            sessionStore.deleteSession(sessionToDelete.id) { error in
                                if let error = error {
                                    // Handle error (e.g., show another alert or log)
                                    print("Error deleting session: \(error.localizedDescription)")
                                } else {
                                    // Optionally, refresh or handle UI changes post-deletion if needed
                                    // (SessionStore likely updates its `sessions` array which should reflect in UI)
                                    print("Session \(sessionToDelete.id) deleted successfully.")
                                }
                                self.selectedSession = nil // Clear selection
                            }
                        }
                    }
                },
                secondaryButton: .cancel() {
                    self.selectedSession = nil // Clear selection on cancel
                }
            )
        }
        .sheet(isPresented: $showEditSheet) {
            if let sessionToEdit = selectedSession {
                EditSessionSheetView(
                    session: sessionToEdit,
                    sessionStore: sessionStore,
                    stakeService: StakeService()
                )
                .environmentObject(userService)
                // onSave and onCancel are handled internally by EditSessionSheetView
            } else {
                // Fallback or error view if selectedSession is nil, though this should not happen if sheet is presented
                Text("Error: No session selected for editing.")
            }
        }
        // Sheet for viewing session details
        .sheet(item: $selectedSession, onDismiss: { selectedSession = nil }) { session in
            SessionDetailView(session: session)
                .environmentObject(sessionStore)
                .environmentObject(userService)
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
}

// MARK: - Session or Transaction enum
enum SessionOrTransaction: Identifiable {
    case session(Session)
    case transaction(BankrollTransaction)
    
    var id: String {
        switch self {
        case .session(let session):
            return "session_\(session.id)"
        case .transaction(let transaction):
            return "transaction_\(transaction.id)"
        }
    }
}

extension SessionOrTransaction {
    var date: Date {
        switch self {
        case .session(let session):
            return session.startDate
        case .transaction(let transaction):
            return transaction.timestamp
        }
    }
    
    var amount: Double {
        switch self {
        case .session(let session):
            return session.profit
        case .transaction(let transaction):
            return transaction.amount
        }
    }
}

// MARK: - Bankroll Transaction Row
struct BankrollTransactionRow: View {
    let transaction: BankrollTransaction
    
    private func formatMoney(_ amount: Double) -> String {
        return "$\(abs(Int(amount)))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"  // Shorter date format
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"  // Time format
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with bankroll info and amount
            HStack(alignment: .center) {
                // Bankroll adjustment info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bankroll Adjustment")
                        .font(.plusJakarta(.body, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(.white)
                    
                    if let note = transaction.note, !note.isEmpty {
                        Text(note)
                            .font(.plusJakarta(.footnote, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.8))
                            .lineLimit(2)
                    } else {
                        Text("Manual adjustment")
                            .font(.plusJakarta(.footnote, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Amount and time
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatMoney(transaction.amount))
                        .font(.plusJakarta(.title3, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(transaction.amount >= 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .padding(.bottom, 2)
                    
                    // Date and time in one line
                    HStack(spacing: 6) {
                        Text(formatDate(transaction.timestamp))
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                        
                        Text("•")
                            .font(.plusJakarta(.caption)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.5))
                        
                        Text(formatTime(transaction.timestamp))
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(
            ZStack { // Applying GlassyInputField style to transaction rows
                RoundedRectangle(cornerRadius: 12)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.01))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5) // Subtle border
            }
        )
        .contentShape(Rectangle())
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

// MARK: - Enhanced section header
struct EnhancedItemsSection: View {
    let title: String
    let items: [SessionOrTransaction]
    let onSelect: (Session) -> Void
    let onDelete: (Session) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.85))
                
                Spacer()
                
                Text("\(items.count) items")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .padding(.horizontal, 8)
            
            // Items in this section
            VStack(spacing: 12) {
                ForEach(items) { item in
                    switch item {
                    case .session(let session):
                        EnhancedSessionSummaryRow(
                            session: session,
                            onSelect: { onSelect(session) },
                            onDelete: { onDelete(session) }
                        )
                    case .transaction(let transaction):
                        BankrollTransactionRow(transaction: transaction)
                    }
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
    @Binding var isExpanded: Bool // Binding to control expanded/collapsed state
    
    // Animation states
    @State private var isChangingMonth = false // Used for brief header animations
    @State private var monthTransitionDirection: Double = 1 
    @State private var isGridAnimated = true // Grid is initially visible, then animated for changes
    @State private var swipeOffset: CGFloat = 0 

    // New states for premium swipe animation
    @State private var gridContentOffset: CGFloat = 0
    @State private var gridContentOpacity: Double = 1.0

    private let calendarCollapsedHeight: CGFloat = 55  
    
    private var calendarExpandedHeight: CGFloat {
        let rows = numberOfWeeksInCurrentMonthGrid()
        var height: CGFloat = 0
        height += 25 // Approx for Header (font + vPadding)
        height += 5  // Approx for Divider area (divider height + its vPadding)
        height += 30 // Approx for Weekday symbols (font + its vPadding .bottom(8))
        height += 6  // Approx for main VStack spacing (2*2) and spacing around weekday list (2)
        if rows == 5 { 
            height += 25 // INCREASED Conditional extra top padding for 5-row months
        }
        
        height += CGFloat(rows) * 40.0 + CGFloat(max(0, rows - 1)) * 1.0 
        return max(calendarCollapsedHeight, height) 
    }

    private func numberOfWeeksInCurrentMonthGrid() -> Int {
        return (daysInMonth().count + 6) / 7 // Standard way to calculate rows in a 7-column grid
    }

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdaySymbols = [
        ("M", "Monday"),
        ("T", "Tuesday"), 
        ("W", "Wednesday"), 
        ("T", "Thursday"),
        ("F", "Friday"),
        ("S", "Saturday"),
        ("S", "Sunday")
    ] // Ultra minimal day indicators with full names for unique IDs
    
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
        VStack(spacing: 3) { // Cell internal spacing, increased from 2 to 3 for a bit more room
            // Month header: Month Year + Profit | Spacer | Chevron Button
            HStack {
                Text("\(monthHeader)")
                    .font(.plusJakarta(.headline, weight: .bold)) 
                    .foregroundColor(.white)
                
                if monthlyProfit != 0 && isExpanded { 
                    Text(formatCurrency(monthlyProfit))
                        .font(.plusJakarta(.subheadline, weight: .semibold)) 
                        .foregroundColor(monthlyProfit > 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .padding(.leading, 8) // Space between month and profit
                }
                
                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        if isExpanded {
                            isGridAnimated = false 
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { 
                                isGridAnimated = true
                            }
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down") // Changed to plain chevron
                        .font(.system(size: 20, weight: .medium)) // Adjusted size for plain chevron
                        .foregroundColor(.white.opacity(0.9)) 
                }
                .buttonStyle(PlainButtonStyle()) 
            }
            .padding(.top, 5)
            .padding(.horizontal, 15) 
            .padding(.top, 2)      // Keep the original 2 points for header spacing

            if isExpanded { 
                Divider()
                    .background(Color.gray.opacity(0.25))
                    .padding(.horizontal, 15) 
                    .padding(.bottom, 2) // Divider bottom padding
            }

            if isExpanded {
                VStack(spacing: 2) { // VStack for weekdays and grid spacing
                    // Days of the week header
                    HStack(spacing: 0) {
                        ForEach(weekdaySymbols, id: \.1) { day in
                            Text(day.0)
                                .font(.plusJakarta(.caption, weight: .bold)) 
                                .foregroundColor(.white) 
                                .frame(maxWidth: .infinity)
                                .opacity(isGridAnimated ? 1 : 0) // Keep this for initial appear and expand/collapse
                                .animation(.easeOut(duration: 0.3).delay(isGridAnimated ? 0.2 : 0), value: isGridAnimated)
                        }
                    }
                    .padding(.bottom, 8) 
                    .padding(.top, numberOfWeeksInCurrentMonthGrid() == 5 ? 25 : 0) // INCREASED Conditional top padding
                    
                    // Calendar grid container for offset and opacity animations
                    Group {
                        LazyVGrid(columns: columns, spacing: 1) { 
                            ForEach(Array(0..<daysInMonth().count), id: \.self) { index in
                                if let date = daysInMonth()[index] {
                                    let dailyProfit = profitForDate(date)
                                    let hasSession = sessionsForDate(date).count > 0
                                    
                                    MinimalistCalendarCell(
                                        date: date,
                                        dailyProfit: dailyProfit,
                                        isSelected: selectedDate != nil && Calendar.current.isDate(date, inSameDayAs: selectedDate!),
                                        hasSession: hasSession,
                                        // isAnimated controls individual cell pop-in, tied to grid visibility
                                        isAnimated: gridContentOpacity == 1.0 && isExpanded, 
                                        animationDelay: Double(index % 7) * 0.02 + Double(index / 7) * 0.04 
                                    )
                                    .onTapGesture {
                                        hapticFeedback(style: .light)
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            if selectedDate != nil && Calendar.current.isDate(date, inSameDayAs: selectedDate!) {
                                                selectedDate = nil
                                            } else if hasSession {
                                                selectedDate = date
                                            }
                                        }
                                    }
                                    // Removed old per-cell offset/opacity tied to isChangingMonth
                                } else {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit) 
                                        .frame(minHeight: 34) // Match cell minHeight
                                }
                            }
                        }
                    }
                    .offset(x: gridContentOffset)
                    .opacity(gridContentOpacity)
                    // .animation on this group might conflict with withAnimation in changeMonth
                }
                .padding(.horizontal, 6)
                .opacity(isExpanded ? (isGridAnimated && gridContentOpacity == 1.0 ? 1 : 0) : 0) // Overall visibility for expand/collapse
                .animation(.easeInOut(duration: 0.4), value: isGridAnimated) 
                .animation(.easeInOut(duration: 0.4), value: gridContentOpacity)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top))) 
            }
        }
        .padding(.top, 5) // Add 5 points of top padding to move the entire calendar down
        .frame(height: isExpanded ? calendarExpandedHeight : calendarCollapsedHeight) 
        .background(
            ZStack { 
                RoundedRectangle(cornerRadius: 20)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.01))
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5) 
            }
        )
        .offset(x: swipeOffset) 
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Make visual feedback even more subtle or disable if it causes issues
                    let subtleTranslation = value.translation.width / 4 // Increased divisor more
                    self.swipeOffset = max(-30, min(30, subtleTranslation)) // Clamped further
                }
                .onEnded { value in
                    withAnimation(.easeInOut(duration: 0.2)) { self.swipeOffset = 0 } 
                    let horizontalTranslation = value.translation.width
                    let swipeThreshold: CGFloat = 50 // Minimum distance for a swipe to register

                    if horizontalTranslation < -swipeThreshold { // Swiped left (next month)
                        changeMonth(by: 1)
                    } else if horizontalTranslation > swipeThreshold { // Swiped right (previous month)
                        changeMonth(by: -1)
                    }
                }
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
    
    // Extracted month changing logic into a function for use by gestures
    private func changeMonth(by amount: Int) {
        hapticFeedback(style: .light)
        let screenWidth = UIScreen.main.bounds.width // Get screen width for offset

        let oldMonth = currentMonth
        let newMonth = Calendar.current.date(byAdding: .month, value: amount, to: currentMonth) ?? currentMonth

        if oldMonth != newMonth {
            // 1. Animate old grid out
            withAnimation(.easeInOut(duration: 0.25)) {
                gridContentOpacity = 0
                gridContentOffset = amount > 0 ? -screenWidth / 2 : screenWidth / 2 // Slide out in swipe direction
                isChangingMonth = true // For header text effects if any
                monthTransitionDirection = amount > 0 ? 1 : -1
            }

            // 2. After slide out, update data and prepare new grid for slide in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { // Match out-animation duration
                currentMonth = newMonth
                isChangingMonth = false // Reset header effect trigger
                
                // Instantly move new grid to the opposite side, off-screen, and keep it transparent
                gridContentOffset = amount > 0 ? screenWidth / 2 : -screenWidth / 2
                // gridContentOpacity is already 0

                // 3. Animate new grid in
                DispatchQueue.main.async { // Ensure this is in the next render pass
                    withAnimation(.easeInOut(duration: 0.35)) {
                        gridContentOpacity = 1.0
                        gridContentOffset = 0
                    }
                }
            }
        } else {
            // If month didn't change (e.g. boundary), ensure grid is visible
            if gridContentOpacity == 0 {
                withAnimation(.easeInOut(duration: 0.35)) {
                    gridContentOpacity = 1.0
                    gridContentOffset = 0
                }
            }
        }
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
        // Cells will be mostly transparent; color cues come from text/indicators
        return Color.clear // Base background is clear
    }

    private var dayForegroundColor: Color {
        if isSelected {
            return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        } else if isToday {
            return .white
        } else if hasSession {
            return .white.opacity(0.85)
        }
        return .gray.opacity(0.6)
    }

    private var profitIndicatorColor: Color? {
        guard hasSession else { return nil }
        if dailyProfit > 0 {
            return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        } else if dailyProfit < 0 {
            return .red
        }
        return Color.gray.opacity(0.7) // Neutral for break-even sessions
    }
    
    private func formattedProfitForCell(_ amount: Double) -> String {
        let prefix = amount >= 0 ? "+" : "-"
        let absAmount = abs(Int(amount))
        return "\(prefix)$\(absAmount)"
    }
    
    var body: some View {
        VStack(spacing: 3) { 
            Text(dayNumber)
                .font(.plusJakarta(.caption, weight: isSelected ? .bold : (isToday ? .semibold : .medium))) // Day number font
                .foregroundColor(dayForegroundColor)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
            
            if hasSession {
                Text(formattedProfitForCell(dailyProfit))
                    .font(.plusJakarta(.caption2, weight: .semibold)) // Profit text font
                    .foregroundColor(profitIndicatorColor ?? .clear) 
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 0) // Reduced top padding for profit text
            } else {
                Text(" ") 
                    .font(.plusJakarta(.caption2, weight: .semibold)) 
                    .padding(.top, 0) // Match profit text top padding
                    .hidden() 
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34) // Adjusted cell minHeight
        .padding(.vertical, 1) // Adjusted cell vertical padding
        .background(cellColor) 
        .cornerRadius(6) // Cell corner radius
        .overlay(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.7)), lineWidth: 1.5)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            Color.white.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [2]) 
                        )
                }
            }
        )
        .scaleEffect(isAnimated ? 1.0 : 0.8)
        .opacity(isAnimated ? 1.0 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1 + animationDelay), value: isAnimated)
        .scaleEffect(isSelected ? 1.03 : 1.0) // Keep subtle selection scale
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
                        .font(.plusJakarta(.body, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(.white)
                    
                    Text(session.stakes)
                        .font(.plusJakarta(.footnote, weight: .medium)) // Using Plus Jakarta Sans
                        .foregroundColor(Color.gray.opacity(0.8))
                }
                
                Spacer()
                
                // Profit amount
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatMoney(session.profit))
                        .font(.plusJakarta(.title3, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(session.profit >= 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .padding(.bottom, 2)
                    
                    // Date and hours in one line
                    HStack(spacing: 6) {
                        Text(formatDate(session.startDate))
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                        
                        Text("•")
                            .font(.plusJakarta(.caption)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.5))
                        
                        Text("\(String(format: "%.1f", session.hoursPlayed))h")
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(
            ZStack { // Applying GlassyInputField style to session rows
                RoundedRectangle(cornerRadius: 12)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.01))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5) // Subtle border
            }
        )
        .contentShape(Rectangle()) 
        .onTapGesture {
            hapticFeedback(style: .light)
            onSelect()
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
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




