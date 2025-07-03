import SwiftUI

struct CashGameAnalyticsHeader: View {
    let sessions: [Session]
    
    // Calculate monthly profit for current month
    private var monthlyProfit: Double {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        return sessions.filter { session in
            let sessionMonth = calendar.component(.month, from: session.startDate)
            let sessionYear = calendar.component(.year, from: session.startDate)
            return sessionMonth == currentMonth && sessionYear == currentYear
        }.reduce(0) { $0 + $1.profit }
    }
    
    // Calculate total profit from all cash game sessions
    private var totalProfit: Double {
        sessions.reduce(0) { $0 + $1.profit }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Hero Number - Total Profit
            Text("$\(String(format: "%.0f", totalProfit))")
                .font(.system(size: 72, weight: .thin))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Monthly Context
            HStack(spacing: 4) {
                Text("$\(String(format: "%.0f", monthlyProfit))")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(monthlyProfit >= 0 ? .green : .red)
                
                Text("this month")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    let sampleSessions = [
        Session(id: "1", data: [
            "userId": "preview",
            "gameType": "CASH GAME",
            "gameName": "Bellagio",
            "stakes": "$2/$5",
            "startDate": Date(),
            "startTime": Date(),
            "endTime": Date(),
            "hoursPlayed": 4.5,
            "buyIn": 500.0,
            "cashout": 925.0,
            "profit": 425.0,
            "createdAt": Date()
        ])
    ]
    
    CashGameAnalyticsHeader(sessions: sampleSessions)
        .background(Color.black)
} 

