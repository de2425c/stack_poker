import SwiftUI
import Foundation

class AnalyticsViewModel: ObservableObject {
    // Dependencies
    let sessionStore: SessionStore
    let bankrollStore: BankrollStore
    let userId: String
    
    // Analytics specific state (copied from ProfileView lines 58-80)
    @Published var selectedTimeRange = 1 // Default to 1W (index 1) for Analytics
    @Published var selectedCarouselIndex = 0 // For carousel page selection
    @Published var selectedGraphTab = 0 // 0 = Bankroll, 1 = Profit, 2 = Monthly
    @Published var isCustomizingStats = false
    @Published var selectedStats: [PerformanceStat] = []
    @Published var isDraggingAny = false
    @Published var showFilterSheet = false
    @Published var analyticsFilter = AnalyticsFilter()
    @Published var isMainGraphsCollapsed = false
    
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"]
    
    init(sessionStore: SessionStore, bankrollStore: BankrollStore, userId: String) {
        self.sessionStore = sessionStore
        self.bankrollStore = bankrollStore
        self.userId = userId
        loadSelectedStats()
    }

    
    // MARK: - Analytics Helper Properties (copied from ProfileView)
    
    @MainActor
    var filteredSessions: [Session] {
        sessionStore.sessions.filter { sessionMatchesFilter($0) }
    }
    
    @MainActor
    var totalBankroll: Double {
        let sessionProfit = filteredSessions.reduce(0) { $0 + adjustedProfit(for: $1) }
        return sessionProfit + bankrollStore.bankrollSummary.currentTotal
    }
    
    @MainActor
    var selectedTimeRangeProfit: Double {
        let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
        return filteredSessions.reduce(0) { $0 + adjustedProfit(for: $1) }
    }
    
    @MainActor
    func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let preFiltered = filteredSessions
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return preFiltered.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneYearAgo }
        default: // All
            return preFiltered
        }
    }
    
    @MainActor
    var winRate: Double {
        let totalSessions = filteredSessions.count
        if totalSessions == 0 { return 0 }
        let winningSessions = filteredSessions.filter { adjustedProfit(for: $0) > 0 }.count
        return Double(winningSessions) / Double(totalSessions) * 100
    }
    
    @MainActor
    var averageProfit: Double {
        let totalSessions = filteredSessions.count
        if totalSessions == 0 { return 0 }
        let sessionProfitOnly = filteredSessions.reduce(0) { $0 + adjustedProfit(for: $1) }
        return sessionProfitOnly / Double(totalSessions)
    }
    
    @MainActor
    var totalSessions: Int {
        filteredSessions.count
    }
    
    @MainActor
    var bestSession: (profit: Double, id: String)? {
        let sessionWithMaxProfit = filteredSessions.max { adjustedProfit(for: $0) < adjustedProfit(for: $1) }
        if let session = sessionWithMaxProfit {
            return (adjustedProfit(for: session), session.id)
        }
        return nil
    }
    
    @MainActor
    var totalHoursPlayed: Double {
        filteredSessions.reduce(0) { $0 + $1.hoursPlayed }
    }
    
    @MainActor
    var averageSessionLength: Double {
        if totalSessions == 0 { return 0 }
        return totalHoursPlayed / Double(totalSessions)
    }
    
    @MainActor
    func monthlyProfitCurrent() -> Double {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        let sessionProfit = filteredSessions.filter { session in
            calendar.component(.month, from: session.startDate) == month && calendar.component(.year, from: session.startDate) == year
        }.reduce(0) { $0 + adjustedProfit(for: $1) }
        
        let bankrollProfit = bankrollStore.transactions.filter { txn in
            calendar.component(.month, from: txn.timestamp) == month && calendar.component(.year, from: txn.timestamp) == year
        }.reduce(0) { $0 + $1.amount }
        
        return sessionProfit + bankrollProfit
    }
    
    func getTimeRangeLabel(for index: Int) -> String {
        guard index >= 0 && index < timeRanges.count else { return "selected period" }
        let range = timeRanges[index]
        switch range {
        case "24H": return "day"
        case "1W": return "week"
        case "1M": return "month"
        case "6M": return "6 months"
        case "1Y": return "year"
        case "All": return "ever"
        default: return "selected period"
        }
    }
    
    // MARK: - Staking-Adjusted Analytics Helper Functions
    
    func adjustedProfit(for session: Session) -> Double {
        return analyticsFilter.showRawProfits ? session.profit : session.effectiveProfit
    }
    
    func ensureAdjustedProfitsCalculated() {
        Task {
            await sessionStore.ensureAllSessionsHaveAdjustedProfits()
        }
    }
    
    // MARK: - Session Filter Logic
    
    @MainActor
    func sessionMatchesFilter(_ session: Session) -> Bool {
        // Game type
        if analyticsFilter.gameType == .cash && !session.gameType.lowercased().contains("cash") {
            return false
        }
        if analyticsFilter.gameType == .tournament && !session.gameType.lowercased().contains("tournament") {
            return false
        }

        // Stake level
        let level = stakeLevel(for: session)
        if analyticsFilter.stakeLevel != .all && analyticsFilter.stakeLevel != level {
            return false
        }

        // Location
        if let desired = analyticsFilter.location {
            if session.gameName.trimmingCharacters(in: .whitespaces) != desired { return false }
        }

        // Session length
        switch analyticsFilter.sessionLength {
        case .under2:
            if session.hoursPlayed >= 2 { return false }
        case .twoToFour:
            if session.hoursPlayed < 2 || session.hoursPlayed > 4 { return false }
        case .over4:
            if session.hoursPlayed <= 4 { return false }
        default:
            break
        }

        // Custom date range
        if let startDate = analyticsFilter.customStartDate {
            if session.startDate < startDate {
                return false
            }
        }
        
        if let endDate = analyticsFilter.customEndDate {
            if session.startDate > endDate {
                return false
            }
        }

        return true
    }
    
    private func stakeLevel(for session: Session) -> StakeLevelFilter {
        let digits = session.stakes.replacingOccurrences(of: " $", with: "")
        let comps = digits.replacingOccurrences(of: "$", with: "").split(separator: "/")
        guard comps.count == 2, let bb = Double(comps[1]), bb > 0 else {
            return .all
        }
        switch bb {
        case ..<1: return .micro
        case ..<3: return .low
        case ..<10: return .mid
        default: return .high
        }
    }
    
    // MARK: - Additional Analytics Properties (copied from ProfileView)
    
    @MainActor
    var dollarPerHour: Double {
        if totalHoursPlayed == 0 { return 0 }
        let sessionProfitOnly = filteredSessions.reduce(0) { $0 + adjustedProfit(for: $1) }
        return sessionProfitOnly / totalHoursPlayed
    }
    
    @MainActor
    var bbPerHour: Double {
        // Calculate BB/hour with weighted average for mixed stakes
        let cashGameSessions = filteredSessions.filter {
            $0.gameType.lowercased().contains("cash")
        }
        
        guard !cashGameSessions.isEmpty else { return 0 }
        
        // Group sessions by stakes level for proper weighted calculation
        var stakeGroups: [String: (totalBB: Double, totalHours: Double)] = [:]
        
        for session in cashGameSessions {
            guard session.hoursPlayed > 0 else { continue }
            
            // Parse big blind from stakes using enhanced parser
            guard let bigBlind = parseBigBlindFromStakes(session.stakes), bigBlind > 0 else { 
                continue 
            }
            
            // Convert session profit to BB won for this session - use adjusted profit
            let bbWonThisSession = adjustedProfit(for: session) / bigBlind
            
            // Group by stakes level
            let stakesKey = session.stakes
            if var group = stakeGroups[stakesKey] {
                group.totalBB += bbWonThisSession
                group.totalHours += session.hoursPlayed
                stakeGroups[stakesKey] = group
            } else {
                stakeGroups[stakesKey] = (bbWonThisSession, session.hoursPlayed)
            }
        }
        
        guard !stakeGroups.isEmpty else { return 0 }
        
        // Calculate weighted average BB/hour across all stake levels
        var totalWeightedBBPerHour: Double = 0
        var totalWeight: Double = 0
        
        for (_, group) in stakeGroups {
            guard group.totalHours > 0 else { continue }
            let bbPerHourForStake = group.totalBB / group.totalHours
            totalWeightedBBPerHour += bbPerHourForStake * group.totalHours
            totalWeight += group.totalHours
        }
        
        guard totalWeight > 0 else { return 0 }
        
        return totalWeightedBBPerHour / totalWeight
    }
    
    @MainActor
    var longestWinningStreak: Int {
        guard !filteredSessions.isEmpty else { return 0 }
        
        let sortedSessions = filteredSessions.sorted { $0.startDate < $1.startDate }
        var currentStreak = 0
        var maxStreak = 0
        
        for session in sortedSessions {
            if adjustedProfit(for: session) > 0 {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        
        return maxStreak
    }
    
    @MainActor
    var longestLosingStreak: Int {
        guard !filteredSessions.isEmpty else { return 0 }
        
        let sortedSessions = filteredSessions.sorted { $0.startDate < $1.startDate }
        var currentStreak = 0
        var maxStreak = 0
        
        for session in sortedSessions {
            if adjustedProfit(for: session) < 0 {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        
        return maxStreak
    }
    
    @MainActor
    var bestLocationByProfit: (location: String, profit: Double)? {
        guard !filteredSessions.isEmpty else { return nil }
        
        let locationProfits = Dictionary(grouping: filteredSessions) { session in
            return parseLocationFromGameName(session.gameName)
        }.mapValues { sessions in sessions.reduce(0) { $0 + adjustedProfit(for: $1) } }
        
        guard let (location, profit) = locationProfits.max(by: { $0.value < $1.value }) else { return nil }
        return (location, profit)
    }
    
    @MainActor
    var bestStakeByProfit: (stake: String, profit: Double)? {
        guard !filteredSessions.isEmpty else { return nil }
        
        let stakeProfits = Dictionary(grouping: filteredSessions, by: { $0.stakes })
            .mapValues { sessions in sessions.reduce(0) { $0 + adjustedProfit(for: $1) } }
        
        guard let (stake, profit) = stakeProfits.max(by: { $0.value < $1.value }) else { return nil }
        return (stake, profit)
    }
    
    @MainActor
    var profitStandardDeviation: Double {
        guard filteredSessions.count > 1 else { return 0 }
        
        let profits = filteredSessions.map { adjustedProfit(for: $0) }
        let mean = profits.reduce(0, +) / Double(profits.count)
        let variance = profits.map { pow($0 - mean, 2) }.reduce(0, +) / Double(profits.count - 1)
        
        return sqrt(variance)
    }
    
    @MainActor
    var tournamentROI: Double {
        let tournamentSessions = filteredSessions.filter { 
            $0.gameType.lowercased().contains("tournament") || $0.gameType.lowercased().contains("mtt") || $0.gameType.lowercased().contains("sng")
        }
        
        guard !tournamentSessions.isEmpty else { return 0 }
        
        let totalBuyins = tournamentSessions.reduce(0) { $0 + $1.buyIn }
        let totalAdjustedProfit = tournamentSessions.reduce(0) { $0 + adjustedProfit(for: $1) }
        
        guard totalBuyins > 0 else { return 0 }
        
        // Calculate ROI based on adjusted profit rather than raw cashout
        return (totalAdjustedProfit / totalBuyins) * 100
    }
    
    // MARK: - Stat Value Calculation
    
    @MainActor
    func getStatValue(for stat: PerformanceStat) -> String {
        switch stat {
        case .avgProfit:
            return "$\(Int(averageProfit).formattedWithCommas)"
        case .bestSession:
            return "$\(Int(bestSession?.profit ?? 0).formattedWithCommas)"
        case .sessions:
            return "\(totalSessions)"
        case .hours:
            return "\(Int(totalHoursPlayed))"
        case .avgSessionLength:
            return String(format: "%.1f", averageSessionLength)
        case .dollarPerHour:
            return "$\(Int(dollarPerHour).formattedWithCommas)"
        case .bbPerHour:
            let bbHr = bbPerHour
            if bbHr == 0 {
                return "No data"
            } else if abs(bbHr) < 0.1 {
                return String(format: "%.2f", bbHr)
            } else {
                return String(format: "%.1f", bbHr)
            }
        case .longestWinStreak:
            return "\(longestWinningStreak)"
        case .longestLoseStreak:
            return "\(longestLosingStreak)"
        case .bestLocation:
            return bestLocationByProfit?.location ?? "No data"
        case .bestStake:
            return bestStakeByProfit?.stake ?? "No data"
        case .standardDeviation:
            return "$\(Int(profitStandardDeviation).formattedWithCommas)"
        case .tournamentROI:
            let roi = tournamentROI
            if roi == 0 {
                return "No data"
            } else {
                return String(format: "%.1f%%", roi)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Parses location name from gameName by removing stakes information
    private func parseLocationFromGameName(_ gameName: String) -> String {
        let cleaned = gameName.trimmingCharacters(in: .whitespaces)
        
        // Remove common stakes patterns: $X/$Y, $X/$Y/$Z, NLX, PLOX, etc.
        let stakesPatterns = [
            #"\$\d+/\$\d+(/\$\d+)?"#,  // $1/$2 or $1/$2/$5
            #"NL\d+"#,                  // NL200, NL100
            #"PLO\d+"#,                 // PLO100, PLO200
            #"FL\d+"#,                  // FL200
            #"\d+/\d+"#,                // 1/2, 2/5
            #"\(\$\d+\)"#               // ($1) ante notation
        ]
        
        var result = cleaned
        for pattern in stakesPatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Clean up extra spaces and common separators
        result = result.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-.,"))
            .trimmingCharacters(in: .whitespaces)
        
        return result.isEmpty ? cleaned : result
    }
    
    /// Parses the big blind value from various stakes string formats
    /// Supports: "$1/$2", "$1/$2/$5", "$2/$5 ($1)", "1/2", "NL200", etc.
    private func parseBigBlindFromStakes(_ stakesString: String) -> Double? {
        let stakes = stakesString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle empty stakes
        guard !stakes.isEmpty else { return nil }
        
        // Method 1: Standard format "$X/$Y" or "X/Y"
        if let bb = parseStandardStakesFormat(stakes) {
            return bb
        }
        
        // Method 2: Online format "NL200", "PLO100", etc.
        if let bb = parseOnlineStakesFormat(stakes) {
            return bb
        }
        
        // Method 3: Tournament format - return nil as tournaments don't have BB/hour
        if stakes.lowercased().contains("tournament") {
            return nil
        }
        
        // Method 4: Try to extract any number as last resort
        return extractNumberFromStakes(stakes)
    }
    
    private func parseStandardStakesFormat(_ stakes: String) -> Double? {
        // Clean the stakes string
        let cleanedStakes = stakes
            .replacingOccurrences(of: " $", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        // Handle straddle format: "$1/$2/$5" or with ante: "$1/$2 ($0.50)"
        let baseStakes = cleanedStakes.components(separatedBy: "(")[0] // Remove ante part
        let components = baseStakes.split(separator: "/")
        
        // Need at least small/big blind
        guard components.count >= 2 else { return nil }
        
        // Extract big blind (second component)
        let bigBlindString = String(components[1])
        return Double(bigBlindString)
    }
    
    private func parseOnlineStakesFormat(_ stakes: String) -> Double? {
        // Handle formats like "NL200", "PLO100", "6-max NL100"
        let pattern = #"(?:NL|PLO|FL)?(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        
        if let match = regex?.firstMatch(in: stakes, options: [], range: NSRange(stakes.startIndex..., in: stakes)),
           let range = Range(match.range(at: 1), in: stakes) {
            let numberString = String(stakes[range])
            // Online stakes are typically in big blinds (e.g., NL200 = $1/$2, so BB = 2)
            if let number = Double(numberString) {
                return number / 100.0 // Convert from cents to dollars
            }
        }
        
        return nil
    }
    
    private func extractNumberFromStakes(_ stakes: String) -> Double? {
        // Last resort: extract the largest number found
        let pattern = #"(\d+(?:\.\d+)?)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        
        var largestNumber: Double = 0
        
        if let regex = regex {
            let matches = regex.matches(in: stakes, options: [], range: NSRange(stakes.startIndex..., in: stakes))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: stakes),
                   let number = Double(String(stakes[range])) {
                    largestNumber = max(largestNumber, number)
                }
            }
        }
        
        return largestNumber > 0 ? largestNumber : nil
    }
    
    // MARK: - Selected Stats Persistence
    
    func saveSelectedStats() {
        let statsStrings = selectedStats.map { $0.rawValue }
        UserDefaults.standard.set(statsStrings, forKey: "selectedStats_\(userId)")
    }
    
    private func loadSelectedStats() {
        if let savedStatsStrings = UserDefaults.standard.object(forKey: "selectedStats_\(userId)") as? [String] {
            let savedStats = savedStatsStrings.compactMap { PerformanceStat(rawValue: $0) }
            if !savedStats.isEmpty {
                selectedStats = savedStats
            } else {
                selectedStats = [.avgProfit, .bestSession, .sessions, .hours, .avgSessionLength, .dollarPerHour]
            }
        } else {
            selectedStats = [.avgProfit, .bestSession, .sessions, .hours, .avgSessionLength, .dollarPerHour]
        }
    }
    
    // Get top 5 most common games from user's sessions
    func getTop5MostCommonGames() -> [String] {
        let gameFrequency = sessionStore.sessions
            .map { $0.gameName.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { counts, game in
                counts[game, default: 0] += 1
            }
        
        return gameFrequency
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
} 