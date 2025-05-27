import Foundation

// MARK: - Main Models
struct ParsedHandHistory: Codable {
    let raw: RawHandHistory
    
    /// Calculates the accurate hero PnL regardless of the stored value
    var accurateHeroPnL: Double {
        return PokerCalculator.calculateHandHistoryPnL(hand: raw)
    }
}

struct RawHandHistory: Codable {
    let gameInfo: GameInfo
    let players: [Player]
    let streets: [Street]
    let pot: Pot
    let showdown: Bool?
    
    enum CodingKeys: String, CodingKey {
        case gameInfo = "game_info"
        case players, streets, pot
        case showdown
    }
}

// MARK: - Game Info
struct GameInfo: Codable {
    let tableSize: Int
    let smallBlind: Double
    let bigBlind: Double
    let ante: Double?
    let straddle: Double?
    let dealerSeat: Int
    
    enum CodingKeys: String, CodingKey {
        case tableSize = "table_size"
        case smallBlind = "small_blind"
        case bigBlind = "big_blind"
        case ante
        case straddle
        case dealerSeat = "dealer_seat"
    }
}

// MARK: - Player
struct Player: Codable, Identifiable {
    let id = UUID()
    let name: String
    let seat: Int
    let stack: Double
    let position: String?
    let isHero: Bool
    let cards: [String]?
    let finalHand: String?
    let finalCards: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name, seat, stack, position
        case isHero = "is_hero"
        case cards
        case finalHand = "final_hand"
        case finalCards = "final_cards"
    }
}

// MARK: - Street
struct Street: Codable {
    let name: String
    let cards: [String]
    let actions: [Action]
}

// MARK: - Action
struct Action: Codable {
    let playerName: String
    let action: String
    let amount: Double
    let cards: [String]?
    
    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case action, amount, cards
    }
}

// MARK: - Pot
struct Pot: Codable {
    let amount: Double
    let distribution: [PotDistribution]?
    let heroPnl: Double
    
    enum CodingKeys: String, CodingKey {
        case amount, distribution
        case heroPnl = "hero_pnl"
    }
    
    /// Gets the accurate hero PnL from the parent hand if needed
    /// This requires the parent hand context to calculate properly
    func getAccurateHeroPnL(in hand: RawHandHistory) -> Double {
        return PokerCalculator.calculateHandHistoryPnL(hand: hand)
    }
}

// MARK: - PotDistribution
struct PotDistribution: Codable {
    let playerName: String
    let amount: Double
    let hand: String
    let cards: [String]
    
    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case amount, hand, cards
    }
}

struct SavedHand: Identifiable {
    let id: String  // Firestore document ID
    let hand: ParsedHandHistory
    let timestamp: Date
    var sessionId: String? = nil  // Optional session ID to tag hands to sessions
    
    /// Convenient access to the accurate hero PnL
    var heroPnL: Double {
        return hand.accurateHeroPnL
    }

    /// Computed property for a brief hand summary string (e.g., "AsKc vs QdJd" or "AsKc vs ??")
    var handSummary: String {
        guard let heroPlayer = hand.raw.players.first(where: { $0.isHero }),
              let heroCards = heroPlayer.cards, !heroCards.isEmpty else {
            return "Hand vs ??" // Fallback if hero cards are missing
        }
        let heroCardsString = heroCards.joined(separator: "")

        // Check for showdown scenario first
        if let showdown = hand.raw.showdown, showdown {
            // Try to find an opponent in the pot distribution who won or chopped and showed cards
            if let opponentInPot = hand.raw.pot.distribution?.first(where: { $0.playerName != heroPlayer.name && $0.amount > 0 && !$0.cards.isEmpty }) {
                let opponentCardsString = opponentInPot.cards.joined(separator: "")
                return "\(heroCardsString) vs \(opponentCardsString)"
            } 
            // If not found in pot distribution, check players array for shown final cards
            else if let opponentPlayer = hand.raw.players.first(where: { !$0.isHero && $0.finalCards != nil && !($0.finalCards?.isEmpty ?? true) }) {
                if let opponentCards = opponentPlayer.finalCards, !opponentCards.isEmpty {
                    let opponentCardsString = opponentCards.joined(separator: "")
                    return "\(heroCardsString) vs \(opponentCardsString)"
                }
            }
            // If still no opponent cards found in showdown, show ??
            return "\(heroCardsString) vs ??"
        }
        
        // If not a showdown, or if we couldn't determine opponent cards in showdown
        return "\(heroCardsString) vs ??" 
    }
} 
