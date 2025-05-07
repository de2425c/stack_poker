import Foundation
import Combine
import SwiftUI // Needed for Binding

// ObservableObject to hold the state for the hand entry wizard
class HandEntryViewModel: ObservableObject {
    @Published var tableSize: Int = 6
    @Published var smallBlind: Double = 1
    @Published var bigBlind: Double = 2
    
    @Published var players: [PlayerEntry] = [
        // Start with Hero
        PlayerEntry(name: "Hero", position: "SB", stack: 200, isHero: true, card1: nil, card2: nil)
    ]
    
    @Published var flopCard1: String? = nil
    @Published var flopCard2: String? = nil
    @Published var flopCard3: String? = nil
    @Published var turnCard: String? = nil
    @Published var riverCard: String? = nil
    
    @Published var preflopActions: [ActionEntry] = []
    @Published var flopActions: [ActionEntry] = []
    @Published var turnActions: [ActionEntry] = []
    @Published var riverActions: [ActionEntry] = []
    
    @Published var foldedPlayerPositions: Set<String> = []
    
    // --- Computed Properties for Card Selection ---
    var usedCards: Set<String> {
        var cards = Set<String>()
        for player in players {
            if let card1 = player.card1 { cards.insert(card1) }
            if let card2 = player.card2 { cards.insert(card2) }
        }
        if let card = flopCard1 { cards.insert(card) }
        if let card = flopCard2 { cards.insert(card) }
        if let card = flopCard3 { cards.insert(card) }
        if let card = turnCard { cards.insert(card) }
        if let card = riverCard { cards.insert(card) }
        return cards
    }
    let cardRanks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]
    let cardSuits = ["h", "d", "c", "s"]
    
    // --- Position Helpers ---
    func positions(for size: Int) -> [String] {
        switch size {
        case 2: return ["SB", "BB"]
        case 6: return ["SB", "BB", "UTG", "MP", "CO", "BTN"]
        case 9: return ["SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "HJ", "CO", "BTN"]
        default: 
            // Fallback to 6-max for unknown table sizes
            return ["SB", "BB", "UTG", "MP", "CO", "BTN"]
        }
    }
    
    func availablePositions(for currentPlayerId: UUID?) -> [String] {
        let allPositions = positions(for: tableSize)
        let currentPosition = players.first { $0.id == currentPlayerId }?.position
        let usedPositions = players.compactMap { $0.position }.filter { $0 != currentPosition }
        return allPositions.filter { !usedPositions.contains($0) }
    }
    
    func getPlayer(by id: UUID) -> Binding<PlayerEntry>? {
        if let index = players.firstIndex(where: { $0.id == id }) {
            return Binding(get: { self.players[index] }, set: { self.players[index] = $0 })
        }
        return nil
    }
    
    // --- Action Helpers ---
    func determineNextPlayerPosition(lastActionPos: String?, currentStreetActions: [ActionEntry]) -> String {
        // Find active players (have position, not folded)
        let activePlayers = players.filter { $0.position != nil && !foldedPlayerPositions.contains($0.position!) }
        guard !activePlayers.isEmpty else { return "" } // Should not happen if hand is live

        let allPositions = positions(for: tableSize)
        let activePositionsOrdered = allPositions.filter { pos in activePlayers.contains(where: { $0.position == pos }) }
        guard !activePositionsOrdered.isEmpty else { return activePlayers.first?.position ?? "" } 

        if let lastPos = lastActionPos, let lastIndex = activePositionsOrdered.firstIndex(of: lastPos) {
            let nextIndex = (lastIndex + 1) % activePositionsOrdered.count
            return activePositionsOrdered[nextIndex]
        } else {
            // No last action, determine starting player based on street
            let bbIndex = allPositions.firstIndex(of: "BB") ?? 1
            let firstToActIndex = (bbIndex + 1) % allPositions.count
             var searchIndex = firstToActIndex
             var loopCounter = 0
             while !activePositionsOrdered.contains(allPositions[searchIndex]) && loopCounter < allPositions.count {
                 searchIndex = (searchIndex + 1) % allPositions.count
                 loopCounter += 1
             }
             return activePositionsOrdered.contains(allPositions[searchIndex]) ? allPositions[searchIndex] : activePositionsOrdered.first ?? ""
        }
    }
    
    // MARK: - Action Calculation Helpers
    
    struct BetState {
        var highestBet: Double = 0
        var betCount: Int = 0       // How many bets/raises this street
        var lastAggressor: String? = nil // Position of last bet/raise
        var playerInvestments: [String: Double] = [:] // Position -> Amount invested this street
    }

    func getCurrentBetState(for streetActions: [ActionEntry]) -> BetState {
        var state = BetState()
        // Add initial blinds for preflop calculation
        if streetActions.isEmpty { // Approximation: Assume preflop if no actions yet
             if let sbPlayer = players.first(where: { $0.position == "SB" }) {
                 state.playerInvestments[sbPlayer.position!] = smallBlind
                 state.highestBet = max(state.highestBet, smallBlind)
             }
             if let bbPlayer = players.first(where: { $0.position == "BB" }) {
                 state.playerInvestments[bbPlayer.position!] = bigBlind
                 state.highestBet = max(state.highestBet, bigBlind)
                 state.lastAggressor = bbPlayer.position // BB is technically the first "bet"
             }
        }

        for action in streetActions {
            let playerPos = action.playerName
            let currentInvestment = state.playerInvestments[playerPos] ?? 0
            
            switch action.action.lowercased() {
                case "bets":
                    let amountToAdd = max(0, action.amount - currentInvestment)
                    state.playerInvestments[playerPos] = action.amount
                    state.highestBet = action.amount
                    state.lastAggressor = playerPos
                    state.betCount += 1
                case "raises":
                    let amountToAdd = max(0, action.amount - currentInvestment)
                    state.playerInvestments[playerPos] = action.amount
                    state.highestBet = action.amount
                    state.lastAggressor = playerPos
                    state.betCount += 1
                case "calls":
                    let callAmount = max(0, state.highestBet - currentInvestment)
                    state.playerInvestments[playerPos] = currentInvestment + callAmount
                // Add blind posts if they appear as actions explicitly
                case "posts small blind":
                     state.playerInvestments[playerPos] = action.amount
                     state.highestBet = max(state.highestBet, action.amount)
                     // Don't count blinds as aggressive actions usually
                case "posts big blind":
                     state.playerInvestments[playerPos] = action.amount
                     state.highestBet = max(state.highestBet, action.amount)
                     if state.betCount == 0 { state.lastAggressor = playerPos } // Set BB as aggressor if no other bets
                case "folds", "checks":
                    break
                 default:
                      break
            }
        }
        return state
    }
    
    func calculateCallAmount(for streetActions: [ActionEntry], playerPosition: String) -> Double {
        // No actions = no call amount (except preflop SB to BB)
        if streetActions.isEmpty && isStreetPreflop(streetActions) {
            // Special case: first action preflop is UTG facing BB
            return bigBlind
        } else if streetActions.isEmpty {
            // No actions in non-preflop street
            return 0
        }
        
        // Track the current highest bet or raise
        var currentBet: Double = 0
        
        // For preflop, start with BB as the initial bet amount
        if isStreetPreflop(streetActions) {
            currentBet = bigBlind
        }
        
        // Find the highest bet or raise in the street
        for action in streetActions {
            if action.action == "bets" || action.action == "raises" {
                currentBet = max(currentBet, action.amount)
            } else if action.action == "posts" && action.amount > currentBet {
                // A post can also set the current bet amount
                // This is especially important for blinds
                currentBet = action.amount
            }
        }
        
        // Calculate player's current investment
        var playerInvestment: Double = 0
        
        // Initial blind investments
        if isStreetPreflop(streetActions) {
            if playerPosition == "SB" {
                playerInvestment = smallBlind
            } else if playerPosition == "BB" {
                playerInvestment = bigBlind
            }
        }
        
        // Add any bets/calls the player has already made
        for action in streetActions {
            if action.playerName == playerPosition {
                if action.action == "bets" || action.action == "raises" || action.action == "calls" {
                    playerInvestment = action.amount
                } else if action.action == "posts" {
                    // Explicit blind post - overrides initial blind investment
                    playerInvestment = action.amount
                }
            }
        }
        
        // Call amount is the difference between current bet and player's investment
        return max(0, currentBet - playerInvestment)
    }
    
    func getLegalActions(for streetActions: [ActionEntry], playerPosition: String) -> [String] {
        // Fundamental betting rules:
        // - When there's an open bet: players can fold, call, or raise
        // - When no bet is open: players can check or bet
        
        // Check if there's an outstanding bet in the current betting round
        let hasBet = hasOutstandingBet(actions: streetActions)
        
        // Preflop always has a bet (blinds), unless we're on a later betting round
        let isPreflop = isStreetPreflop(streetActions)
        let isPreflopFirstRound = isPreflop && !hasResetBettingRound(actions: streetActions)
        
        if hasBet || isPreflopFirstRound {
            // Facing a bet (or preflop first round with blinds)
            return ["folds", "calls", "raises"] // Order matters: fold, call, raise
        } else {
            // No outstanding bet - can check or bet
            return ["checks", "bets"]
        }
    }
    
    // Helper to check if there's an outstanding bet that hasn't been called by everyone
    private func hasOutstandingBet(actions: [ActionEntry]) -> Bool {
        // If there are no actions, there's no bet
        if actions.isEmpty { return false }
        
        // Find the last betting round (starts after last bet/raise)
        var lastBetRaiseIndex = -1
        for (index, action) in actions.enumerated().reversed() {
            // Consider posts as bets for this calculation
            if action.action == "bets" || action.action == "raises" || action.action == "posts" {
                lastBetRaiseIndex = index
                break
            }
        }
        
        // If no bets/raises found, there's no outstanding bet
        if lastBetRaiseIndex == -1 { return false }
        
        // We have a bet/raise - now check if it's been completely called
        
        // Get all unique players who haven't folded
        let activePlayers = getActivePlayers(actions: actions)
        
        // Get actions after the last bet/raise
        let actionsAfterBet = Array(actions[(lastBetRaiseIndex+1)...])
        
        // Players who have responded to the bet
        let respondedPlayers = Set(actionsAfterBet.map { $0.playerName })
        
        // If any active player hasn't responded, there's still an outstanding bet
        return !respondedPlayers.isSuperset(of: activePlayers)
    }
    
    // Helper to get active (non-folded) players
    private func getActivePlayers(actions: [ActionEntry]) -> Set<String> {
        // Track folded players in this action set
        let foldedPlayers = Set(actions.filter { $0.action == "folds" }.map { $0.playerName })
        
        // All players who acted
        let allPlayers = Set(actions.map { $0.playerName })
        
        // Return players who haven't folded
        return allPlayers.subtracting(foldedPlayers)
    }
    
    // Helper to check if we've reset the betting round (everyone acted on a bet)
    private func hasResetBettingRound(actions: [ActionEntry]) -> Bool {
        // Find the last bet/raise
        guard let lastBetRaiseIndex = actions.lastIndex(where: { 
            $0.action == "bets" || $0.action == "raises" || $0.action == "posts" 
        }) else {
            return false
        }
        
        // Get actions after this bet/raise
        let actionsAfterBet = Array(actions[(lastBetRaiseIndex+1)...])
        
        // Find the active players before the bet
        let activePlayers = getActivePlayers(actions: Array(actions[0...lastBetRaiseIndex]))
        
        // Players who acted after the bet
        let playersActedAfterBet = Set(actionsAfterBet.map { $0.playerName })
        
        // Check if all active players (minus the bettor) acted after the bet
        // Remove the bettor from active players since they don't need to act again
        let expectedToAct = activePlayers.subtracting([actions[lastBetRaiseIndex].playerName])
        return playersActedAfterBet.isSuperset(of: expectedToAct)
    }
    
    // Helper to identify if given actions are from preflop
    private func isStreetPreflop(_ actions: [ActionEntry]) -> Bool {
        // If checking preflopActions themselves
        if actions.count == 0 && preflopActions.count == 0 {
            return true // First action on preflop
        }
        
        // If this is a specific street's actions array
        if actions.isEmpty {
            // First action on street - check if street type is preflop
            // Simple hack: Since we don't have street type directly accessible,
            // assume based on board cards - preflop has no board cards
            return flopCard1 == nil // If no flop cards, we're on preflop
        }
        
        // Alternatively, check if the actions exist in preflopActions
        if !actions.isEmpty {
            let actionIds = Set(actions.map { $0.id })
            let preflopIds = Set(preflopActions.map { $0.id })
            return !actionIds.isDisjoint(with: preflopIds) // If any IDs match, it's preflop
        }
        
        return false
    }
    
}

// Helper structs remain the same but might not be needed directly by Views
struct PlayerEntry: Identifiable {
    var id = UUID()
    var name: String
    var position: String?
    var stack: Double
    var isHero: Bool
    var card1: String?
    var card2: String?
}

struct ActionEntry: Identifiable, Equatable {
    var id = UUID()
    var playerName: String // This is the position
    var action: String
    var amount: Double
    
    // Equatable conformance based on ID
    static func == (lhs: ActionEntry, rhs: ActionEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - UI Components
// ... existing code ... 
