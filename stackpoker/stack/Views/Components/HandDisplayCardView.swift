import SwiftUI
import Kingfisher

struct HandDisplayCardView: View {
    let hand: ParsedHandHistory
    var onReplayTap: (() -> Void)?
    let location: String?
    let createdAt: Date
    var showReplayInFeed: Bool = false // Default to false, meaning replay button IS shown
                                      // Will be set to TRUE from FeedView to HIDE it.

    private var hero: Player? {
        hand.raw.players.first(where: { $0.isHero })
    }

    private var opponent: Player? {
        hand.raw.players.first(where: { !$0.isHero })
    }

    private var heroPnl: Double {
        hand.accurateHeroPnL
    }

    private var pnlText: String {
        let pnlIntValue = Int(heroPnl)
        if pnlIntValue >= 0 {
            return "Won $\(pnlIntValue)"
        } else {
            return "Lost $\(abs(pnlIntValue))"
        }
    }
    
    private var potSizeBB: Int {
        let bb = hand.raw.gameInfo.bigBlind
        guard bb > 0 else { return 0 }
        return Int(hand.raw.pot.amount / bb)
    }

    private var heroCardsDisplay: String {
        let firstCard = hero?.cards?.first.map { formatCardString($0) } ?? "?"
        let secondCard = hero?.cards?.dropFirst().first.map { formatCardString($0) } ?? "?"
        return firstCard + secondCard
    }

    private var opponentCardsDisplay: String {
        guard hand.raw.showdown == true || heroPnl > 0,
              let opp = opponent,
              let oppCards = opp.finalCards ?? opp.cards,
              !oppCards.isEmpty else {
            return "??" // Keep two characters for spacing if opponent cards are unknown
        }
        let firstCard = oppCards.first.map { formatCardString($0) } ?? "?"
        let secondCard = oppCards.dropFirst().first.map { formatCardString($0) } ?? "?"
        return firstCard + secondCard
    }
    
    private var handVsHandText: String {
        let heroStr = heroCardsDisplay
        let oppStr = opponentCardsDisplay
        return heroStr + " vs " + oppStr + " - " + String(potSizeBB) + "BB Pot"
    }
    
    private var timeAndLocationText: String {
        let timePart = createdAt.timeAgo()
        let locPart = location ?? "Unknown Location"
        return timePart + " at " + locPart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Conditionally hide the header if showReplayInFeed is true
            if !showReplayInFeed {
                HStack(alignment: .center, spacing: 0) { 
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 4, height: 60) 
                        .background(Color.clear) // Ensure this decorative element doesn't block transparency

                    VStack(alignment: .leading, spacing: 6) { 
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(heroPnl >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                            Text(pnlText)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(heroPnl >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                        }

                        Text(handVsHandText) 
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Text(timeAndLocationText) 
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 12)
                    .background(Color.clear) // Ensure this VStack is transparent

                    Spacer()

                    if !showReplayInFeed {
                        Button(action: { 
                            print("Replay button tapped in HandDisplayCardView")
                            onReplayTap?() 
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 24))
                                Text("REPLAY")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .padding(.horizontal, 16)
                        }
                        .background(Color.clear) // Ensure button background is transparent
                    }
                }
                .frame(height: 80) 
                .background(Color.clear) // Ensure this HStack container is transparent
            } else {
                HStack(alignment: .center, spacing: 0) { 
                     Rectangle()
                        .fill(heroPnl >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.red) 
                        .frame(width: 4, height: 40) 
                        .padding(.trailing, 12)
                        .background(Color.clear) // Ensure this decorative element doesn't block transparency

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pnlText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(heroPnl >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)

                        Text(handVsHandText) 
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .background(Color.clear) // Ensure this VStack is transparent
                    Spacer() 
                }
                .frame(height: 60) 
                .padding(.vertical, 10) 
                .background(Color.clear) // Ensure this HStack container is transparent
            }
        }
        .padding(.horizontal) 
        .background(Color.clear) // Explicitly set the root VStack background to clear
    }

    private func formatCardString(_ cardString: String?) -> String {
        guard let cardStr = cardString, !cardStr.isEmpty else { return "?" } // Return single '?' for unknown card
        // Return only the first character (rank)
        return String(cardStr.prefix(1)).uppercased()
    }
}

// Color extension for hex should be defined globally once.
// If not, ensure it's here or accessible.
// extension Color {
//     init(hex: String) { ... } 
// }






