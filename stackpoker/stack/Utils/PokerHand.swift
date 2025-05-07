import Foundation

// Represents a poker card
struct PokerCard: Comparable, Hashable {
    let rank: Rank
    let suit: Suit

    // Simplified parsing from string like "As", "Td", "9c"
    init?(fromString string: String) {
        guard string.count == 2 else { return nil }
        guard let rank = Rank(string.prefix(1)) else { return nil }
        guard let suit = Suit(string.suffix(1)) else { return nil }
        self.rank = rank
        self.suit = suit
    }
    
    static func < (lhs: PokerCard, rhs: PokerCard) -> Bool {
        return lhs.rank < rhs.rank
    }
}

// Card Ranks (Ace high for now)
enum Rank: Int, Comparable, CaseIterable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

    init?(_ char: String.SubSequence) {
        switch char {
        case "2": self = .two
        case "3": self = .three
        case "4": self = .four
        case "5": self = .five
        case "6": self = .six
        case "7": self = .seven
        case "8": self = .eight
        case "9": self = .nine
        case "T": self = .ten
        case "J": self = .jack
        case "Q": self = .queen
        case "K": self = .king
        case "A": self = .ace
        default: return nil
        }
    }
    
    static func < (lhs: Rank, rhs: Rank) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// Card Suits
enum Suit: String, CaseIterable {
    case spades = "s", hearts = "h", diamonds = "d", clubs = "c"
    
    init?(_ char: String.SubSequence) {
        self.init(rawValue: String(char))
    }
}

// Represents the type of poker hand
enum HandRank: Int, Comparable {
    case highCard = 0
    case pair
    case twoPair
    case threeOfAKind
    case straight
    case flush
    case fullHouse
    case fourOfAKind
    case straightFlush
    case royalFlush
    
    static func < (lhs: HandRank, rhs: HandRank) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// Represents a evaluated 5-card poker hand
struct EvaluatedHand: Comparable {
    let rank: HandRank
    let highCards: [Rank] // Ranks determining the hand strength (e.g., [King, King, Ace, 5, 3] for K pair)
    
    static func < (lhs: EvaluatedHand, rhs: EvaluatedHand) -> Bool {
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        // Basic kicker comparison (needs refinement for complex ties)
        for i in 0..<min(lhs.highCards.count, rhs.highCards.count) {
            if lhs.highCards[i] != rhs.highCards[i] {
                return lhs.highCards[i] < rhs.highCards[i]
            }
        }
        return false // Tie
    }
} 