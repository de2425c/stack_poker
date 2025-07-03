import SwiftUI

struct LatestSessionHeader: View {
    let session: Session
    
    private var timeAgo: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(session.endTime)
        
        if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            return "Today"
        }
    }
    
    private var durationText: String {
        let hours = Int(session.hoursPlayed)
        let minutes = Int((session.hoursPlayed - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }
    
    private var profitText: String {
        return "$\(String(format: "%.0f", abs(session.profit)))"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Title row
            HStack {
                Text("Latest Session")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            // Session info row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(session.gameName) \(session.stakes)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(timeAgo) • \(durationText)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(profitText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(session.profit >= 0 ? Color.green : Color.red)
                    
                    Text(session.profit >= 0 ? "profit" : "loss")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
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
    
    LatestSessionHeader(session: Session(id: "preview", data: sampleData))
        .background(Color.black)
} 