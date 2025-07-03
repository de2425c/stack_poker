import SwiftUI

struct CollapsibleLatestSession: View {
    let session: Session
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Row - Always Visible
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Session")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Text(session.gameName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$\(String(format: "%.0f", session.profit))")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(session.profit >= 0 ? .green : .red)
                        
                        Text(formatDuration(session.hoursPlayed))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded Details
            if isExpanded {
                VStack(spacing: 20) {
                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                    
                    // Details Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 24) {
                        StatDetail(label: "Stakes", value: session.stakes)
                        StatDetail(label: "Buy-in", value: "$\(String(format: "%.0f", session.buyIn))")
                        StatDetail(label: "Cash-out", value: "$\(String(format: "%.0f", session.cashout))")
                        StatDetail(label: "Hourly", value: "$\(String(format: "%.0f", session.profit / session.hoursPlayed))")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.02))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60
        
        if hrs > 0 {
            return "\(hrs)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

struct StatDetail: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.3)
            
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let sampleSession = Session(id: "1", data: [
        "userId": "preview",
        "gameType": "CASH GAME",
        "gameName": "Bellagio 2/5",
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
    
    CollapsibleLatestSession(session: sampleSession)
        .background(Color.black)
} 