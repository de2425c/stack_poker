import Foundation

// Poker hand evaluator to determine the best 5-card hand from 7 cards
struct HandEvaluator {
    // Card ranks in descending order
    static let cardRanks: [Character: Int] = [
        "A": 14, "K": 13, "Q": 12, "J": 11, "T": 10,
        "9": 9, "8": 8, "7": 7, "6": 6, "5": 5, "4": 4, "3": 3, "2": 2
    ]
    
    static let cardSuits: [Character: String] = [
        "s": "♠", "h": "♥", "d": "♦", "c": "♣"
    ]
    
    // Hand rankings (higher is better)
    enum HandRank: Int, Comparable {
        case highCard = 0
        case pair = 1
        case twoPair = 2
        case threeOfAKind = 3
        case straight = 4
        case flush = 5
        case fullHouse = 6
        case fourOfAKind = 7
        case straightFlush = 8
        case royalFlush = 9
        
        static func < (lhs: HandRank, rhs: HandRank) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        // String representation of the hand
        var description: String {
            switch self {
            case .highCard: return "High Card"
            case .pair: return "Pair"
            case .twoPair: return "Two Pair"
            case .threeOfAKind: return "Three of a Kind"
            case .straight: return "Straight"
            case .flush: return "Flush"
            case .fullHouse: return "Full House"
            case .fourOfAKind: return "Four of a Kind"
            case .straightFlush: return "Straight Flush"
            case .royalFlush: return "Royal Flush"
            }
        }
    }
    
    // Represents a poker card
    struct Card: Comparable {
        let rank: Character
        let suit: Character
        
        var rankValue: Int {
            return HandEvaluator.cardRanks[rank] ?? 0
        }
        
        // Parse a card string like "Ah" or "Ts"
        init?(from cardString: String) {
            guard cardString.count == 2 else { return nil }
            self.rank = cardString.first!
            self.suit = cardString.last!
        }
        
        // For sorting cards by rank
        static func < (lhs: Card, rhs: Card) -> Bool {
            return lhs.rankValue < rhs.rankValue
        }
        
        // For comparing card equality
        static func == (lhs: Card, rhs: Card) -> Bool {
            return lhs.rank == rhs.rank && lhs.suit == rhs.suit
        }
    }
    
    // Structure to represent a hand evaluation
    struct HandEvaluation: Comparable {
        let rank: HandRank
        let cards: [Card]
        let tiebreakers: [Int]
        
        // For comparing hand rankings
        static func < (lhs: HandEvaluation, rhs: HandEvaluation) -> Bool {
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            
            // Compare tiebreakers in order
            for (lhsValue, rhsValue) in zip(lhs.tiebreakers, rhs.tiebreakers) {
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue
                }
            }
            
            // Hands are identical in rank
            return false
        }
        
        var description: String {
            let rankDesc = rank.description
            let cardsDesc = cards.map { "\($0.rank)\($0.suit)" }.joined(separator: " ")
            return "\(rankDesc) (\(cardsDesc))"
        }
        
        // Human-readable description of the hand
        var humanReadableDescription: String {
            switch rank {
            case .highCard:
                let highCard = cards.max { $0.rankValue < $1.rankValue }!
                return "High Card \(formatCardRank(highCard.rank))"
                
            case .pair:
                let pairRank = tiebreakers[0]
                return "Pair of \(formatCardRankFromValue(pairRank))s"
                
            case .twoPair:
                let highPairRank = tiebreakers[0]
                let lowPairRank = tiebreakers[1]
                return "Two Pair, \(formatCardRankFromValue(highPairRank))s and \(formatCardRankFromValue(lowPairRank))s"
                
            case .threeOfAKind:
                let tripRank = tiebreakers[0]
                return "Three of a Kind, \(formatCardRankFromValue(tripRank))s"
                
            case .straight:
                let highCard = cards.max { $0.rankValue < $1.rankValue }!
                return "Straight, \(formatCardRank(highCard.rank)) High"
                
            case .flush:
                let highCard = cards.max { $0.rankValue < $1.rankValue }!
                return "Flush, \(formatCardRank(highCard.rank)) High"
                
            case .fullHouse:
                let tripRank = tiebreakers[0]
                let pairRank = tiebreakers[1]
                return "Full House, \(formatCardRankFromValue(tripRank))s over \(formatCardRankFromValue(pairRank))s"
                
            case .fourOfAKind:
                let quadRank = tiebreakers[0]
                return "Four of a Kind, \(formatCardRankFromValue(quadRank))s"
                
            case .straightFlush:
                let highCard = cards.max { $0.rankValue < $1.rankValue }!
                return "Straight Flush, \(formatCardRank(highCard.rank)) High"
                
            case .royalFlush:
                return "Royal Flush"
            }
        }
        
        // Format card rank for display
        private func formatCardRank(_ rank: Character) -> String {
            switch rank {
            case "T": return "10"
            case "J": return "Jack"
            case "Q": return "Queen"
            case "K": return "King"
            case "A": return "Ace"
            default: return String(rank)
            }
        }
        
        private func formatCardRankFromValue(_ value: Int) -> String {
            switch value {
            case 14: return "Ace"
            case 13: return "King"
            case 12: return "Queen"
            case 11: return "Jack"
            case 10: return "10"
            default: return String(value)
            }
        }
    }
    
    // Evaluate the best 5-card hand from the given cards
    static func evaluateBestHand(cards: [String]) -> HandEvaluation? {
        print("hello")
        // Convert string cards to Card objects
        let parsedCards = cards.compactMap { Card(from: $0) }
        guard parsedCards.count >= 5 else { return nil }
        
        // Get all possible 5-card combinations from the available cards
        let combinations = getCombinations(cards: parsedCards, k: 5)
        
        var bestHand: HandEvaluation?
        var bestCombo: [Card] = []
        
        for combo in combinations {
            let evaluation = evaluateHand(cards: combo)
            print("[HandEval] Combo: \(combo.map { "\($0.rank)\($0.suit)" }.joined(separator: ", ")) => \(evaluation.rank) | Tiebreakers: \(evaluation.tiebreakers)")
            if bestHand == nil || evaluation > bestHand! {
                bestHand = evaluation
                bestCombo = combo
            }
        }
        if let bestHand = bestHand {
            print("[HandEval] BEST: \(bestCombo.map { "\($0.rank)\($0.suit)" }.joined(separator: ", ")) => \(bestHand.rank) | Tiebreakers: \(bestHand.tiebreakers)")
        }
        return bestHand
    }
    
    // Evaluate a specific 5-card hand
    private static func evaluateHand(cards: [Card]) -> HandEvaluation {
        let sortedCards = cards.sorted(by: >)

        // 1. Royal Flush
        if let straightFlush = checkStraightFlush(cards: sortedCards), straightFlush.tiebreakers[0] == 14 {
            return HandEvaluation(rank: .royalFlush, cards: straightFlush.cards, tiebreakers: straightFlush.tiebreakers)
        }
        // 2. Straight Flush
        if let straightFlush = checkStraightFlush(cards: sortedCards) {
            return straightFlush
        }
        // 3. Four of a Kind
        if let fourOfAKind = checkFourOfAKind(cards: sortedCards) {
            return fourOfAKind
        }
        // 4. Full House
        if let fullHouse = checkFullHouse(cards: sortedCards) {
            return fullHouse
        }
        // 5. Flush
        if let flush = checkFlush(cards: sortedCards) {
            return flush
        }
        // 6. Straight
        if let straight = checkStraight(cards: sortedCards) {
            return straight
        }
        // 7. Three of a Kind
        if let threeOfAKind = checkThreeOfAKind(cards: sortedCards) {
            return threeOfAKind
        }
        // 8. Two Pair
        if let twoPair = checkTwoPair(cards: sortedCards) {
            return twoPair
        }
        // 9. One Pair
        if let pair = checkPair(cards: sortedCards) {
            return pair
        }
        // 10. High Card
        return checkHighCard(cards: sortedCards)
    }
    
    // Generate all combinations of k cards from n cards
    private static func getCombinations(cards: [Card], k: Int) -> [[Card]] {
        var result: [[Card]] = []
        var temp: [Card] = Array(repeating: cards[0], count: k)
        
        // Recursive helper
        func combine(start: Int, index: Int) {
            if index == k {
                result.append(temp)
                return
            }
            
            for i in start..<cards.count {
                temp[index] = cards[i]
                combine(start: i + 1, index: index + 1)
            }
        }
        
        combine(start: 0, index: 0)
        return result
    }
    
    // Check for a royal flush
    private static func checkRoyalFlush(cards: [Card]) -> HandEvaluation? {
        // Royal flush is a straight flush with an ace high
        if let straightFlush = checkStraightFlush(cards: cards),
           straightFlush.tiebreakers[0] == 14 {
            return HandEvaluation(rank: .royalFlush, cards: cards, tiebreakers: [])
        }
        return nil
    }
    
    // Check for a straight flush
    private static func checkStraightFlush(cards: [Card]) -> HandEvaluation? {
        // Group cards by suit
        let suits = Dictionary(grouping: cards, by: { $0.suit })
        for suitCards in suits.values {
            if suitCards.count >= 5 {
                if let straight = checkStraight(cards: suitCards) {
                    return HandEvaluation(rank: .straightFlush, cards: straight.cards, tiebreakers: straight.tiebreakers)
                }
            }
        }
        return nil
    }
    
    // Check for four of a kind
    private static func checkFourOfAKind(cards: [Card]) -> HandEvaluation? {
        let rankCounts = getRankCounts(cards: cards)
        for (rank, count) in rankCounts {
            if count == 4 {
                // Get the four cards
                let quads = cards.filter { $0.rankValue == rank }
                // Find the highest kicker (the 5th card)
                let kicker = cards.filter { $0.rankValue != rank }.max(by: { $0.rankValue < $1.rankValue })
                if quads.count == 4, let kicker = kicker {
                    return HandEvaluation(
                        rank: .fourOfAKind,
                        cards: quads + [kicker],
                        tiebreakers: [rank, kicker.rankValue]
                    )
                }
            }
        }
        return nil
    }
    
    // Check for a full house
    private static func checkFullHouse(cards: [Card]) -> HandEvaluation? {
        let rankCounts = getRankCounts(cards: cards)
        let trips = rankCounts.filter { $0.value == 3 }.map { $0.key }.sorted(by: >)
        let pairs = rankCounts.filter { $0.value >= 2 }.map { $0.key }.sorted(by: >)
        for tripRank in trips {
            for pairRank in pairs where pairRank != tripRank {
                // Get the three cards for trips
                let tripCards = cards.filter { $0.rankValue == tripRank }.prefix(3)
                // Get the two cards for pair
                let pairCards = cards.filter { $0.rankValue == pairRank }.prefix(2)
                if tripCards.count == 3 && pairCards.count == 2 {
                    return HandEvaluation(
                        rank: .fullHouse,
                        cards: Array(tripCards) + Array(pairCards),
                        tiebreakers: [tripRank, pairRank]
                    )
                }
            }
        }
        return nil
    }
    
    // Check for a flush
    private static func checkFlush(cards: [Card]) -> HandEvaluation? {
        let suits = Dictionary(grouping: cards, by: { $0.suit })
        for suitCards in suits.values {
            if suitCards.count >= 5 {
                let bestFlush = suitCards.sorted(by: { $0.rankValue > $1.rankValue }).prefix(5)
                let rankValues = bestFlush.map { $0.rankValue }
                return HandEvaluation(
                    rank: .flush,
                    cards: Array(bestFlush),
                    tiebreakers: rankValues
                )
            }
        }
        return nil
    }
    
    // Check for a straight
    private static func checkStraight(cards: [Card]) -> HandEvaluation? {
        // Map all card ranks to their integer values (Ace as both 14 and 1 for wheel)
        var rankToCard: [Int: Card] = [:]
        for card in cards.sorted(by: { $0.rankValue > $1.rankValue }) {
            if rankToCard[card.rankValue] == nil {
                rankToCard[card.rankValue] = card
            }
        }
        // Add Ace as 1 for wheel straight if present
        if rankToCard[14] != nil {
            let aceLowCard = rankToCard[14]!
            rankToCard[1] = aceLowCard
        }
        let uniqueRanks = rankToCard.keys.sorted(by: >)
        // Check for any sequence of 5 consecutive values
        for i in 0...(uniqueRanks.count - 5) {
            let window = Array(uniqueRanks[i..<(i+5)])
            var isConsecutive = true
            for j in 0..<4 {
                if window[j] - window[j+1] != 1 {
                    isConsecutive = false
                    break
                }
            }
            if isConsecutive {
                let straightCards = window.map { rankToCard[$0]! }
                return HandEvaluation(
                    rank: .straight,
                    cards: straightCards,
                    tiebreakers: [window[0]] // high card of the straight
                )
            }
        }
        return nil
    }
    
    // Check for three of a kind
    private static func checkThreeOfAKind(cards: [Card]) -> HandEvaluation? {

        let rankCounts = getRankCounts(cards: cards)
        let trips = rankCounts.filter { $0.value == 3 }.map { $0.key }.sorted(by: >)
        for tripRank in trips {
            let tripCards = cards.filter { $0.rankValue == tripRank }.prefix(3)
            let kickers = cards.filter { $0.rankValue != tripRank }.sorted(by: { $0.rankValue > $1.rankValue }).prefix(2)
            if tripCards.count == 3 && kickers.count == 2 {
                return HandEvaluation(
                    rank: .threeOfAKind,
                    cards: Array(tripCards) + Array(kickers),
                    tiebreakers: [tripRank] + kickers.map { $0.rankValue }
                )
            }
        }
        return nil
    }
    
    // Check for two pair
    private static func checkTwoPair(cards: [Card]) -> HandEvaluation? {
        let rankCounts = getRankCounts(cards: cards)
        let pairs = rankCounts.filter { $0.value == 2 }.map { $0.key }.sorted(by: >)
        if pairs.count >= 2 {
            let highPair = pairs[0]
            let lowPair = pairs[1]
            let highPairCards = cards.filter { $0.rankValue == highPair }.prefix(2)
            let lowPairCards = cards.filter { $0.rankValue == lowPair }.prefix(2)
            let kicker = cards.filter { $0.rankValue != highPair && $0.rankValue != lowPair }.max(by: { $0.rankValue < $1.rankValue })
            if highPairCards.count == 2 && lowPairCards.count == 2, let kicker = kicker {
                return HandEvaluation(
                    rank: .twoPair,
                    cards: Array(highPairCards) + Array(lowPairCards) + [kicker],
                    tiebreakers: [highPair, lowPair, kicker.rankValue]
                )
            }
        }
        return nil
    }
    
    // Check for a pair
    private static func checkPair(cards: [Card]) -> HandEvaluation? {
        let rankCounts = getRankCounts(cards: cards)
        let pairs = rankCounts.filter { $0.value == 2 }.map { $0.key }.sorted(by: >)
        for pairRank in pairs {
            let pairCards = cards.filter { $0.rankValue == pairRank }.prefix(2)
            let kickers = cards.filter { $0.rankValue != pairRank }.sorted(by: { $0.rankValue > $1.rankValue }).prefix(3)
            if pairCards.count == 2 && kickers.count == 3 {
                return HandEvaluation(
                    rank: .pair,
                    cards: Array(pairCards) + Array(kickers),
                    tiebreakers: [pairRank] + kickers.map { $0.rankValue }
                )
            }
        }
        return nil
    }
    
    // Check for high card
    private static func checkHighCard(cards: [Card]) -> HandEvaluation {
        let bestCards = cards.sorted(by: { $0.rankValue > $1.rankValue }).prefix(5)
        let rankValues = bestCards.map { $0.rankValue }
        return HandEvaluation(
            rank: .highCard,
            cards: Array(bestCards),
            tiebreakers: rankValues
        )
    }
    
    // Helper to count occurrences of each rank
    private static func getRankCounts(cards: [Card]) -> [Int: Int] {
        var rankCounts: [Int: Int] = [:]
        
        for card in cards {
            rankCounts[card.rankValue, default: 0] += 1
        }
        
        return rankCounts
    }
    
    // Get a formatted description of the best hand from card strings
    static func getHandDescription(cards: [String]) -> String {
        guard let bestHand = evaluateBestHand(cards: cards) else {
            return "Invalid Hand"
        }
        
        return bestHand.humanReadableDescription
    }
    
    // Determine the winner between multiple hands
    static func determineWinner(hands: [(playerName: String, cards: [String])]) -> [(playerName: String, handDescription: String, winner: Bool)] {
        var results: [(playerName: String, evaluation: HandEvaluation?, handDescription: String)] = []
        
        // Evaluate each player's hand
        for (playerName, cards) in hands {
            let evaluation = evaluateBestHand(cards: cards)
            let handDescription = evaluation?.humanReadableDescription ?? "Invalid Hand"
            results.append((playerName, evaluation, handDescription))
        }
        
        // Find the best hand(s)
        var bestEvaluation: HandEvaluation?
        for result in results {
            if let evaluation = result.evaluation {
                if bestEvaluation == nil || evaluation > bestEvaluation! {
                    bestEvaluation = evaluation
                }
            }
        }
        
        // Mark winners and return results
        return results.map { (playerName, evaluation, handDescription) in
            let isWinner = evaluation != nil && bestEvaluation != nil && (evaluation! >= bestEvaluation!)
            return (playerName, handDescription, isWinner)
        }
    }
} 

