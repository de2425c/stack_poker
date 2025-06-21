import SwiftUI
import PhotosUI

struct SessionResultShareView: View {
    let sessionDetails: (buyIn: Double, cashout: Double, profit: Double, duration: String, gameName: String, stakes: String, sessionId: String)?
    let isTournament: Bool
    let onShareToFeed: () -> Void
    let onShareToSocials: () -> Void
    let onDone: () -> Void
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)
                
                Spacer()
            }
            
            VStack(spacing: 40) {
                // Title based on profit/loss
                if let details = sessionDetails {
                    let isWin = details.profit >= 0
                    Text(isWin ? "Share your win! 🎉" : "Share your loss 😔")
                        .font(.plusJakarta(.title, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                }
                
                Spacer()
                
                // Session Card - tap to share to socials
                if let details = sessionDetails {
                    Button(action: onShareToSocials) {
                        FinishedSessionCardView(
                            gameName: details.gameName,
                            stakes: details.stakes,
                            date: Date(),
                            duration: details.duration,
                            buyIn: details.buyIn,
                            cashOut: details.cashout,
                            isBackgroundTransparent: false
                        )
                    }
                    
                    Text("Tap card to share to socials")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 16)
                }
                
                Spacer()
                
                // Bottom Buttons
                VStack(spacing: 16) {
                    Button(action: onShareToFeed) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Share to Feed")
                                .font(.plusJakarta(.body, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.blue)
                        )
                    }
                    
                    Button(action: onDone) {
                        Text("Done")
                            .font(.plusJakarta(.body, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }

        }
    

}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    SessionResultShareView(
        sessionDetails: (
            buyIn: 100.0,
            cashout: 500.0,
            profit: 400.0,
            duration: "3h 45m",
            gameName: "Wynn",
            stakes: "$2/$5",
            sessionId: "preview"
        ),
        isTournament: false,
        onShareToFeed: {},
        onShareToSocials: {},
        onDone: {}
    )
} 