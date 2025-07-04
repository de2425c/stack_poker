import SwiftUI

struct TournamentStatsSection: View {
    let sessions: [Session]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tournament Stats")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Tournament ROI Card
                    PokerStatCard(
                        suit: .hearts,
                        rank: "A",
                        title: "Tournament ROI",
                        value: tournamentROI,
                        subtitle: tournamentROISubtitle,
                        gradient: [Color.red.opacity(0.8), Color.pink.opacity(0.6)]
                    )
                    
                    // Hourly Rate Card
                    PokerStatCard(
                        suit: .clubs,
                        rank: "K",
                        title: "Hourly Rate",
                        value: hourlyRateText,
                        subtitle: hourlyRateSubtitle,
                        gradient: [Color(red: 64/255, green: 156/255, blue: 255/255), Color(red: 100/255, green: 180/255, blue: 255/255)]
                    )
                    
                    // Longest Session Card
                    PokerStatCard(
                        suit: .diamonds,
                        rank: "Q",
                        title: "Longest Session",
                        value: longestSessionText,
                        subtitle: longestSessionSubtitle,
                        gradient: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)]
                    )
                    
                    // Biggest Win Card
                    PokerStatCard(
                        suit: .spades,
                        rank: "J",
                        title: "Biggest Win",
                        value: biggestWinText,
                        subtitle: biggestWinSubtitle,
                        gradient: [Color.green.opacity(0.8), Color.teal.opacity(0.6)]
                    )
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    // MARK: - Computed Properties for Stats
    
    private var tournamentROI: String {
        guard !sessions.isEmpty else { return "0%" }
        
        let totalBuyIn = sessions.reduce(0) { $0 + $1.buyIn }
        let totalCashout = sessions.reduce(0) { $0 + $1.cashout }
        
        guard totalBuyIn > 0 else { return "0%" }
        
        let roi = ((totalCashout - totalBuyIn) / totalBuyIn) * 100
        return "\(String(format: "%.0f", roi))%"
    }
    
    private var tournamentROISubtitle: String {
        guard !sessions.isEmpty else { return "" }
        
        let totalProfit = sessions.reduce(0) { $0 + $1.profit }
        return "$\(String(format: "%.0f", totalProfit))"
    }
    
    private var hourlyRateText: String {
        guard !sessions.isEmpty else { return "$0/hr" }
        
        let totalProfit = sessions.reduce(0) { $0 + $1.profit }
        let totalHours = sessions.reduce(0) { $0 + $1.hoursPlayed }
        
        guard totalHours > 0 else { return "$0/hr" }
        
        let rate = totalProfit / totalHours
        return "$\(String(format: "%.0f", rate))/hr"
    }
    
    private var hourlyRateSubtitle: String {
        guard !sessions.isEmpty else { return "" }
        
        let totalHours = sessions.reduce(0) { $0 + $1.hoursPlayed }
        return "\(String(format: "%.0f", totalHours))h played"
    }
    
    private var longestSessionText: String {
        guard !sessions.isEmpty else { return "0h" }
        
        let longest = sessions.max(by: { $0.hoursPlayed < $1.hoursPlayed })?.hoursPlayed ?? 0
        let hours = Int(longest)
        let minutes = Int((longest - Double(hours)) * 60)
        
        return "\(hours)h \(minutes)m"
    }
    
    private var longestSessionSubtitle: String {
        guard !sessions.isEmpty else { return "" }
        
        let longestSession = sessions.max(by: { $0.hoursPlayed < $1.hoursPlayed })
        guard let session = longestSession else { return "" }
        
        return "at \(session.gameName)"
    }
    
    private var biggestWinText: String {
        guard !sessions.isEmpty else { return "$0" }
        
        let biggestWin = sessions.max(by: { $0.profit < $1.profit })?.profit ?? 0
        return "$\(String(format: "%.0f", biggestWin))"
    }
    
    private var biggestWinSubtitle: String {
        guard !sessions.isEmpty else { return "" }
        
        let biggestWinSession = sessions.max(by: { $0.profit < $1.profit })
        guard let session = biggestWinSession else { return "" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: session.startDate)
    }
}

#Preview {
    let sampleSessions = [
        Session(id: "1", data: [
            "userId": "preview",
            "gameType": "TOURNAMENT",
            "gameName": "WSOP Main Event",
            "stakes": "$10,000",
            "startDate": Date(),
            "startTime": Date(),
            "endTime": Date(),
            "hoursPlayed": 12.5,
            "buyIn": 10000.0,
            "cashout": 25000.0,
            "profit": 15000.0,
            "createdAt": Date()
        ])
    ]
    
    TournamentStatsSection(sessions: sampleSessions)
        .background(Color.black)
} 