import SwiftUI

struct PokerCardStatsSection: View {
    let sessions: [Session]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cash Game Stats")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Best Location Card
                    PokerStatCard(
                        suit: .hearts,
                        rank: "A",
                        title: "Best Location",
                        value: bestLocation,
                        subtitle: bestLocationSubtitle,
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
    
    private var bestLocation: String {
        guard !sessions.isEmpty else { return "No data" }
        
        let locationCounts = Dictionary(grouping: sessions, by: { $0.gameName })
            .mapValues { sessionGroup in
                sessionGroup.reduce(0) { $0 + $1.profit }
            }
        
        guard let best = locationCounts.max(by: { $0.value < $1.value }) else {
            return "No data"
        }
        
        return best.key.count > 8 ? String(best.key.prefix(8)) + "..." : best.key
    }
    
    private var bestLocationSubtitle: String {
        guard !sessions.isEmpty else { return "" }
        
        let locationCounts = Dictionary(grouping: sessions, by: { $0.gameName })
            .mapValues { sessionGroup in
                sessionGroup.reduce(0) { $0 + $1.profit }
            }
        
        guard let best = locationCounts.max(by: { $0.value < $1.value }) else {
            return ""
        }
        
        return "$\(String(format: "%.0f", best.value))"
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

// MARK: - Poker Card Component

struct PokerStatCard: View {
    let suit: CardSuit
    let rank: String
    let title: String
    let value: String
    let subtitle: String
    let gradient: [Color]
    
    var body: some View {
        VStack(spacing: 0) {
            // Card header with rank and suit
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rank)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Image(systemName: suit.symbolName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                // Corner rank/suit (mirrored)
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: suit.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .rotationEffect(.degrees(180))
                    
                    Text(rank)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Centered stats content
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .multilineTextAlignment(.center)
                
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            
            // Bottom spacer to match top
            Spacer()
                .frame(height: 48) // Match the top padding + header height
        }
        .frame(width: 160, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: gradient),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
}

enum CardSuit {
    case hearts, diamonds, clubs, spades
    
    var symbolName: String {
        switch self {
        case .hearts: return "heart.fill"
        case .diamonds: return "diamond.fill"
        case .clubs: return "club.fill"
        case .spades: return "spade.fill"
        }
    }
}

#Preview {
    let sampleSessions = [
        Session(id: "1", data: [
            "userId": "preview",
            "gameType": "CASH GAME",
            "gameName": "The Mirage",
            "stakes": "$2/$5",
            "startDate": Date(),
            "startTime": Date(),
            "endTime": Date(),
            "hoursPlayed": 8.5,
            "buyIn": 500.0,
            "cashout": 1200.0,
            "profit": 700.0,
            "createdAt": Date()
        ])
    ]
    
    PokerCardStatsSection(sessions: sampleSessions)
        .background(Color.black)
} 