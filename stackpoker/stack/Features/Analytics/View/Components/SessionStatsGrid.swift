import SwiftUI

struct SessionStatsGrid: View {
    let session: Session
    @EnvironmentObject private var sessionStore: SessionStore
    
    private var durationText: String {
        let hours = Int(session.hoursPlayed)
        let minutes = Int((session.hoursPlayed - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }
    
    private var hourlyRateText: String {
        guard session.hoursPlayed > 0 else { return "$0/hr" }
        let rate = session.profit / session.hoursPlayed
        return "$\(String(format: "%.0f", abs(rate)))/hr"
    }
    
    private var hourlyRateColor: Color {
        guard session.hoursPlayed > 0 else { return .white }
        let rate = session.profit / session.hoursPlayed
        return rate >= 0 ? .green : .red
    }
    
    private var currentStreakData: (text: String, color: Color, label: String) {
        let recentSessions = sessionStore.sessions.prefix(10)
        guard !recentSessions.isEmpty else { return ("No data", .white, "streak") }
        
        var currentStreak = 0
        var isWinStreak = true
        
        for session in recentSessions {
            if session.profit > 0 {
                if isWinStreak || currentStreak == 0 {
                    currentStreak += 1
                    isWinStreak = true
                } else {
                    break
                }
            } else if session.profit < 0 {
                if !isWinStreak || currentStreak == 0 {
                    currentStreak += 1
                    isWinStreak = false
                } else {
                    break
                }
            } else {
                break
            }
        }
        
        if currentStreak == 0 {
            return ("No streak", .white.opacity(0.6), "current")
        }
        
        let label = isWinStreak ? "winning" : "losing"
        let color: Color = isWinStreak ? .green : .red
        return ("\(currentStreak)", color, label)
    }
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            // Duration
            ModernStatCard(
                icon: "clock.fill",
                title: "Duration",
                value: durationText,
                valueColor: .white
            )
            
            // Buy-in
            ModernStatCard(
                icon: "dollarsign.circle.fill",
                title: "Buy-in",
                value: "$\(Int(session.buyIn))",
                valueColor: .white
            )
            
            // Hourly Rate
            ModernStatCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Hourly Rate",
                value: hourlyRateText,
                valueColor: hourlyRateColor
            )
            
            // Current Streak
            ModernStatCard(
                icon: "flame.fill",
                title: "Current \(currentStreakData.label)",
                value: currentStreakData.text,
                valueColor: currentStreakData.color
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

struct ModernStatCard: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .white
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.3)
                
                Spacer()
            }
            
            HStack {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(valueColor)
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

#Preview {
    let sampleData: [String: Any] = [
        "userId": "preview",
        "gameType": "CASH GAME",
        "gameName": "Bellagio",
        "stakes": "$2/$5",
        "startDate": Date(),
        "startTime": Date(),
        "endTime": Date().addingTimeInterval(4.33 * 3600),
        "hoursPlayed": 4.33,
        "buyIn": 500.0,
        "cashout": 925.0,
        "profit": 425.0,
        "createdAt": Date()
    ]
    
    SessionStatsGrid(session: Session(id: "preview", data: sampleData))
        .environmentObject(SessionStore(userId: "preview"))
        .background(Color.black)
} 