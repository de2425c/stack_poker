import SwiftUI

/// A highly visual component for displaying live poker session data in posts and feeds
struct LiveSessionStatusView: View {
    // Session details
    let gameName: String
    let stakes: String
    let chipAmount: Double
    let buyIn: Double
    let elapsedTime: TimeInterval
    let isLive: Bool
    
    // Optional parameters
    var lastAction: String? = nil
    var isCompact: Bool = false
    
    // Computed properties
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
    
    // Colors
    private let accentColor = Color(red: 123/255, green: 255/255, blue: 99/255)
    private let darkGray = Color(red: 30/255, green: 32/255, blue: 36/255)
    private let darkerGray = Color(red: 22/255, green: 24/255, blue: 28/255)
    private let lightText = Color.white.opacity(0.9)
    private let subtleText = Color.gray.opacity(0.8)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with pulse effect
            HStack {
                // Live indicator with pulse animation
                HStack(spacing: 6) {
                    Circle()
                        .fill(isLive ? accentColor : Color.orange)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(isLive ? accentColor : Color.orange, lineWidth: 2)
                                .scaleEffect(isLive ? 1.5 : 1.0)
                                .opacity(isLive ? 0 : 0.5)
                                .animation(
                                    isLive ? Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                                    value: isLive
                                )
                        )
                    
                    Text(isLive ? "LIVE SESSION" : "SESSION")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isLive ? accentColor : Color.orange)
                }
                
                Spacer()
                
                // Game info
                Text("\(gameName) (\(stakes))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(lightText)
            }
            
            if !isCompact {
                // Divider with gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [accentColor.opacity(0.7), accentColor.opacity(0.1)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                
                // Stack and PnL section
                HStack(alignment: .top) {
                    // Stack without chip icon
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STACK")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(subtleText)
                        
                        Text("$\(Int(chipAmount))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(lightText)
                    }
                    .frame(minWidth: 100, alignment: .leading)
                    
                    // Profit/Loss with visual indicator but no icon
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PROFIT/LOSS")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(subtleText)
                        
                        Text(formattedProfit)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isProfitable ? accentColor : .red)
                    }
                    .frame(minWidth: 100, alignment: .leading)
                    
                    Spacer()
                    
                    // Session time
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("SESSION TIME")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(subtleText)
                        
                        Text(formattedTime)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(lightText)
                    }
                }
                
                // Last action (if provided)
                if let action = lastAction {
                    HStack(spacing: 8) {
                        Text("Last Action:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(subtleText)
                        
                        Text(action)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(lightText)
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            } else {
                // Compact view for session stats
                HStack(spacing: 24) {
                    // Stack without circle
                    Text("$\(Int(chipAmount))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(lightText)
                    
                    // P/L without arrow icon
                    Text(formattedProfit)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isProfitable ? accentColor : .red)
                    
                    // Time
                    Text(formattedTime)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(lightText)
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            ZStack(alignment: .bottomTrailing) {
                // Main background
                RoundedRectangle(cornerRadius: 14)
                    .fill(darkGray)
                
                // Subtle decorative elements
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 60))
                    .foregroundColor(darkerGray)
                    .offset(x: 20, y: 20)
                    .opacity(0.3)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [accentColor.opacity(0.7), accentColor.opacity(0.1)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Preview
struct LiveSessionStatusView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(red: 18/255, green: 20/255, blue: 24/255)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Full view
                LiveSessionStatusView(
                    gameName: "Bellagio",
                    stakes: "$5/$10",
                    chipAmount: 2450,
                    buyIn: 2000,
                    elapsedTime: 7200,
                    isLive: true,
                    lastAction: "Added $500 to stack"
                )
                
                // Compact view
                LiveSessionStatusView(
                    gameName: "Aria",
                    stakes: "$2/$5",
                    chipAmount: 800,
                    buyIn: 1000,
                    elapsedTime: 3600,
                    isLive: false,
                    isCompact: true
                )
            }
            .padding()
        }
    }
} 