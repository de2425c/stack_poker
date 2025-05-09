import SwiftUI

/// A view that displays standardized session information for posts created during a live session
struct SessionPostSummaryView: View {
    let gameName: String
    let stakes: String
    let chipAmount: Double
    let buyIn: Double
    let elapsedTime: TimeInterval
    
    private var profit: Double {
        chipAmount - buyIn
    }
    
    private var isProfitable: Bool {
        profit >= 0
    }
    
    private var formattedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private var formattedProfit: String {
        let amount = abs(Int(profit))
        return isProfitable ? "+$\(amount)" : "-$\(amount)"
    }
    
    // MARK: - Colors
    private let accentColor = Color(red: 123/255, green: 255/255, blue: 99/255)
    private let backgroundColor = Color(red: 30/255, green: 32/255, blue: 36/255)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            
            Divider()
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 4)
            
            gameInfoView
            sessionStatsView
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Text("Live Session")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            liveBadge
        }
    }
    
    private var liveBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 10))
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.2))
        )
        .foregroundColor(accentColor)
    }
    
    private var gameInfoView: some View {
        HStack(spacing: 16) {
            infoField(title: "Game", value: gameName)
            infoField(title: "Stakes", value: stakes)
            Spacer()
        }
    }
    
    private var sessionStatsView: some View {
        HStack(spacing: 16) {
            infoField(title: "Stack", value: "$\(Int(chipAmount))")
            
            infoField(
                title: "P/L",
                value: formattedProfit,
                valueColor: isProfitable ? accentColor : .red
            )
            
            infoField(title: "Session Time", value: formattedTime)
            
            Spacer()
        }
    }
    
    private func infoField(
        title: String,
        value: String,
        valueColor: Color = .white
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Preview
struct SessionPostSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(red: 20/255, green: 22/255, blue: 26/255)
                .ignoresSafeArea()
            
            SessionPostSummaryView(
                gameName: "Wynn Poker Room",
                stakes: "$2/$5",
                chipAmount: 1250.0,
                buyIn: 1000.0,
                elapsedTime: 7200 // 2 hours
            )
            .padding()
        }
    }
} 