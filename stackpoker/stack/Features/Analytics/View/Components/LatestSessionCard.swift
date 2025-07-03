import SwiftUI

struct LatestSessionCard: View {
    let session: Session
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            LatestSessionHeader(session: session)
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 20)
            
            // Stats Grid
            SessionStatsGrid(session: session)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.01)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: Color.black.opacity(0.4),
            radius: 32,
            x: 0,
            y: 16
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
    
    LatestSessionCard(session: Session(id: "preview", data: sampleData))
        .padding()
        .background(Color.black)
} 