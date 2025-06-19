import SwiftUI
import FirebaseAuth

struct StandaloneHomeGameBar: View {
    let game: HomeGame
    var currentUserId: String = Auth.auth().currentUser?.uid ?? ""
    var onTap: () -> Void

    private var subtitle: String {
        if game.creatorId == currentUserId {
            return "You're hosting"
        } else {
            return "Tap to join"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "house.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    if game.smallBlind != nil || game.bigBlind != nil {
                        Text(game.stakesDisplay)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)))
                    }
                }
                
                Spacer()
                
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 30/255, green: 32/255, blue: 40/255),
                        Color(red: 22/255, green: 24/255, blue: 30/255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 5, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 12)
    }
}

// Preview
struct StandaloneHomeGameBar_Previews: PreviewProvider {
    static var previews: some View {
        // Sample HomeGame for preview
        let sampleGame = HomeGame(
            id: "previewGame123",
            title: "Epic Poker Night Showdown Long Title That Might Truncate",
            createdAt: Date(),
            creatorId: "user123",
            creatorName: "The Host",
            groupId: nil, // Standalone
            status: .active,
            players: [],
            buyInRequests: [],
            cashOutRequests: [],
            gameHistory: [],
            smallBlind: 1.0,
            bigBlind: 2.0
        )
        
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            StandaloneHomeGameBar(game: sampleGame, onTap: {

            })
        }
    }
} 