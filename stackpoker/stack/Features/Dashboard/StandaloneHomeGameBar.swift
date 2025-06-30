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
            HStack(spacing: 12) {
                Image(systemName: "house.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        
                        if game.smallBlind != nil || game.bigBlind != nil {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            
                            Text(game.stakesDisplay)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.9)))
                        }
                    }
                }
                
                Spacer()
                
                Text("ACTIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .padding(.top, (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 0)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 32/255, green: 34/255, blue: 42/255),
                        Color(red: 26/255, green: 28/255, blue: 34/255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
        }
        .buttonStyle(PlainButtonStyle())
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