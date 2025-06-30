import SwiftUI

struct CashGameCard: View {
    let game: CashGame
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Game name
                Text(game.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Stakes display
                Text(game.stakes)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    .lineLimit(1)
                
                // Location if available
                if let location = game.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? 
                          Color(red: 30/255, green: 50/255, blue: 40/255) : 
                          Color(red: 30/255, green: 33/255, blue: 36/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ?
                            Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.7) :
                            Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? 
                    Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.3) :
                    Color.black.opacity(0.1), 
                radius: 3, 
                y: 2
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}



// For use in previews
struct CashGameCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                CashGameCard(
                    game: CashGame(
                        userId: "preview",
                        name: "Bellagio",
                        smallBlind: 1,
                        bigBlind: 2,
                        straddle: nil,
                        location: "Table 5"
                    ),
                    isSelected: false,
                    action: {}
                )
                
                CashGameCard(
                    game: CashGame(
                        userId: "preview",
                        name: "Home Game",
                        smallBlind: 1,
                        bigBlind: 3,
                        straddle: 6,
                        location: nil
                    ),
                    isSelected: true,
                    action: {}
                )
            }
            .padding()
        }
    }
} 
