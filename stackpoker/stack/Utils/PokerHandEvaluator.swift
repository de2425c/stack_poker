import Foundation

struct PokerHandEvaluator {
    
    // Main function to evaluate the best 5-card hand from 7 cards
    static func evaluateHand(holeCards: [PokerCard], boardCards: [PokerCard]) -> EvaluatedHand? {
        let allSevenCards = holeCards + boardCards
        guard allSevenCards.count == 7 else { return nil } // Or 5 or 6 if board not complete?

        var bestHand: EvaluatedHand? = nil

        // Iterate through all combinations of 5 cards from 7
        let combinations = combinations(elements: allSevenCards, k: 5)
        
        for fiveCardCombo in combinations {
            if let evaluated = evaluateFiveCardHand(cards: fiveCardCombo) {
                if bestHand == nil || evaluated > bestHand! {
                    bestHand = evaluated
                }
            }
        }
        
        return bestHand
    }

    // Evaluate a specific 5-card hand
    private static func evaluateFiveCardHand(cards: [PokerCard]) -> EvaluatedHand? {
        guard cards.count == 5 else { return nil }
        let sortedCards = cards.sorted(by: >) // Sort descending by rank
        let ranks = sortedCards.map { $0.rank }
        let suits = Set(sortedCards.map { $0.suit })
        let rankCounts = Dictionary(grouping: ranks, by: { $0 }).mapValues { $0.count }
        
        let isFlush = suits.count == 1
        let isStraight = isStraight(ranks: ranks)
        
        // Check for Straight Flush / Royal Flush
        if isStraight && isFlush {
            let rank = (ranks.first == .ace && ranks.last == .ten) ? HandRank.royalFlush : HandRank.straightFlush
            return EvaluatedHand(rank: rank, highCards: [ranks.first!]) // Highest card determines straight flush rank
        }
        
        // Check for Four of a Kind
        if let fourRank = rankCounts.first(where: { $0.value == 4 })?.key {
            let kicker = ranks.first { $0 != fourRank }!
            return EvaluatedHand(rank: .fourOfAKind, highCards: [fourRank, kicker])
        }
        
        // Check for Full House
        if let threeRank = rankCounts.first(where: { $0.value == 3 })?.key,
           let pairRank = rankCounts.first(where: { $0.value == 2 })?.key {
            return EvaluatedHand(rank: .fullHouse, highCards: [threeRank, pairRank])
        }
        
        // Check for Flush
        if isFlush {
            return EvaluatedHand(rank: .flush, highCards: ranks) // Use all 5 cards as kickers
        }
        
        // Check for Straight
        if isStraight {
             return EvaluatedHand(rank: .straight, highCards: [ranks.first!])
        }
        
        // Check for Three of a Kind
        if let threeRank = rankCounts.first(where: { $0.value == 3 })?.key {
            let kickers = ranks.filter { $0 != threeRank }.sorted(by: >)
            return EvaluatedHand(rank: .threeOfAKind, highCards: [threeRank] + kickers)
        }
        
        // Check for Two Pair
        let pairs = rankCounts.filter { $0.value == 2 }.keys.sorted(by: >)
        if pairs.count == 2 {
            let kicker = ranks.first { !pairs.contains($0) }!
            return EvaluatedHand(rank: .twoPair, highCards: [pairs[0], pairs[1], kicker])
        }
        
        // Check for Pair
        if let pairRank = pairs.first {
            let kickers = ranks.filter { $0 != pairRank }.sorted(by: >)
             return EvaluatedHand(rank: .pair, highCards: [pairRank] + kickers)
        }
        
        // High Card
        return EvaluatedHand(rank: .highCard, highCards: ranks)
    }

    // Helper to check for a straight
    private static func isStraight(ranks: [Rank]) -> Bool {
        // Check for Ace-low straight (A, 2, 3, 4, 5)
        if Set(ranks) == Set([.ace, .two, .three, .four, .five]) {
            // A bit tricky for comparison, maybe return a special rank?
            // For now, just detect it. The main eval should handle A-5 vs 6-high.
            return true 
        }
        // Check for standard straight
        for i in 0..<(ranks.count - 1) {
            if ranks[i].rawValue != ranks[i+1].rawValue + 1 {
                return false
            }
        }
        return true
    }
    
    // Helper for combinations (n choose k)
    private static func combinations<T>(elements: [T], k: Int) -> [[T]] {
        guard k >= 0 && k <= elements.count else { return [] }
        guard k > 0 else { return [[]] }
        guard k < elements.count else { return [elements] }
        
        if k == 1 {
            return elements.map { [$0] }
        }
        
        var result: [[T]] = []
        let firstElement = elements[0]
        let remainingElements = Array(elements.dropFirst())
        
        // Combinations that include the first element
        let combinationsWithFirst = combinations(elements: remainingElements, k: k - 1)
        for combo in combinationsWithFirst {
            result.append([firstElement] + combo)
        }
        
        // Combinations that do not include the first element
        result += combinations(elements: remainingElements, k: k)
        
        return result
    }
} 