import Foundation

// MARK: - Main Models
struct ParsedHandHistory: Codable {
    let raw: RawHandHistory
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
    let dealerSeat: Int
    
    enum CodingKeys: String, CodingKey {
        case tableSize = "table_size"
        case smallBlind = "small_blind"
        case bigBlind = "big_blind"
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
} 
