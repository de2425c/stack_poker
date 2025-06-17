import Foundation
import Combine
import SwiftUI

// MARK: - LLM Parsing Models
struct LLMParsedResponse: Codable {
    let players: [LLMPlayerDetail]?
    let preflop: LLMStreetDetail?
    let flop: LLMStreetDetail?
    let turn: LLMStreetDetail?
    let river: LLMStreetDetail?
}

struct LLMPlayerDetail: Codable {
    let position: String
    var cards: String? // Keep as String?

    // Add custom decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(String.self, forKey: .position)
        
        // Try to decode 'cards' as a String. If it's not a string (e.g., an empty array),
        // this will fail, and we'll catch it and set cards to nil.
        do {
            cards = try container.decodeIfPresent(String.self, forKey: .cards)
        } catch {
            // If decoding as String fails (e.g. it's an array like `[]` or another type),
            // set cards to nil.
            cards = nil
        }
    }
    
    // Add CodingKeys if not already present, or ensure they are compatible
    enum CodingKeys: String, CodingKey {
        case position
        case cards
    }
}

struct LLMStreetDetail: Codable {
    let cards: [String]? // e.g., ["T", "7", "2"] or ["Ts", "7d", "2c"] - will need robust parsing
    let actions: [LLMActionDetail]?
}

struct LLMActionDetail: Codable {
    let position: String // Position of the player making the action
    let action: String   // e.g., "raise", "call", "bet", "fold", "check"
    let amount: String?  // e.g., "15" or "0" or null
}

class NewHandEntryViewModel: ObservableObject {
    // Session ID for associating the hand
    let sessionId: String?

    // Stakes
    @Published var smallBlind: Double = 1.0 {
        didSet {
            // Ensure small blind is never negative, but allow 0 for deletion
            if smallBlind < 0 {
                smallBlind = 0
            }
        }
    }
    @Published var bigBlind: Double = 2.0 {
        didSet {
            // Ensure big blind is never negative, but allow 0 for deletion
            if bigBlind < 0 {
                bigBlind = 0
            }
        }
    }
    @Published var straddle: Double? = nil
    @Published var ante: Double? = nil

    // Table Info
    @Published var tableSize: Int = 6 {
        didSet {
            if !availablePositions.contains(heroPosition) {
                heroPosition = availablePositions.first ?? "BTN"
            }
            setupInitialPlayers() 
            // When table size changes, preflop blinds and first actor might change
            updatePreflopStateAndFirstActor()
        }
    }
    @Published var effectiveStackType: EffectiveStackType = .dollars // Default to dollars
    @Published var effectiveStackAmount: Double = 100
    @Published var hasAnte: Bool = false
    @Published var hasStraddle: Bool = false

    // Hero Info
    @Published var heroPosition: String = "BTN" {
        didSet {
            if oldValue != heroPosition {
                 setupInitialPlayers()
                 // Hero position change can affect first actor if hero was SB/BB/UTG
                 updatePreflopStateAndFirstActor()
            }
        }
    }
    @Published var heroCard1: String? = nil
    @Published var heroCard2: String? = nil

    // Other Players
    @Published var players: [PlayerInput] = [] {
        didSet {

            
            // Check if active players have changed
            let oldActive = oldValue.filter({ $0.isActive }).map({ $0.position })
            let newActive = players.filter({ $0.isActive }).map({ $0.position })
            
            if oldActive != newActive {

                
                // Reset all action queues when active players change
                resetActionQueues()
                
                // If active players change (especially SB/BB), update blinds and first actor
                updatePreflopStateAndFirstActor()
            } else if oldValue.map({ $0.isActive }) != players.map({ $0.isActive }) {
                // This is a backup check in case array order changes

                resetActionQueues()
                updatePreflopStateAndFirstActor()
            }
        }
    }

    // Board Cards
    @Published var flopCard1: String? = nil { didSet { if oldValue != flopCard1 { setupNextStreetIfReady(.flop) } } }
    @Published var flopCard2: String? = nil { didSet { if oldValue != flopCard2 { setupNextStreetIfReady(.flop) } } }
    @Published var flopCard3: String? = nil { didSet { if oldValue != flopCard3 { setupNextStreetIfReady(.flop) } } }
    @Published var turnCard: String? = nil { didSet { if oldValue != turnCard && turnCard != nil { setupNextStreetIfReady(.turn) } } }
    @Published var riverCard: String? = nil { didSet { if oldValue != riverCard && riverCard != nil { setupNextStreetIfReady(.river) } } }

    // Actions for each street
    @Published var preflopActions: [ActionInput] = [] { 
        didSet { 

            updatePotDisplay()
            determineNextPlayerAndUpdateState() 
        } 
    }
    @Published var flopActions: [ActionInput] = [] { 
        didSet { 

            updatePotDisplay()
            determineNextPlayerAndUpdateState() 
        } 
    }
    @Published var turnActions: [ActionInput] = [] { 
        didSet { 

            updatePotDisplay()
            determineNextPlayerAndUpdateState() 
        } 
    }
    @Published var riverActions: [ActionInput] = [] { 
        didSet { 

            updatePotDisplay()
            determineNextPlayerAndUpdateState() 
        } 
    }

    // Pot display properties
    @Published var currentPotPreflop: Double = 0
    @Published var currentPotFlop: Double = 0
    @Published var currentPotTurn: Double = 0
    @Published var currentPotRiver: Double = 0

    // State for the single, unified action input UI
    @Published var currentActionStreet: StreetIdentifier = .preflop
    @Published var pendingActionInput: ActionInput? = nil // New: Holds the action being built

    @Published var legalActionsForPendingPlayer: [PokerActionType] = []
    @Published var callAmountForPendingPlayer: Double = 0
    @Published var minBetRaiseAmountForPendingPlayer: Double = 0

    // Error Message
    @Published var errorMessage: String? = nil
    
    // Available positions based on table size
    var availablePositions: [String] {
        switch tableSize {
        case 2: return ["SB", "BB"] // UTG/BTN is SB in 2-handed
        case 3: return ["BTN", "SB", "BB"]
        case 4: return ["BTN", "SB", "BB", "UTG"]
        case 5: return ["BTN", "SB", "BB", "UTG", "CO"]
        case 6: return ["BTN", "SB", "BB", "UTG", "MP", "CO"]
        // Corrected 7-9 max positions based on common poker conventions (UTG+1, UTG+2 or MP1/MP2/LJ, HJ, CO, BTN)
        case 7: return ["BTN", "SB", "BB", "UTG", "MP", "HJ", "CO"] // UTG, MP, HJ, CO, BTN, SB, BB
        case 8: return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "HJ", "CO"] // UTG, UTG+1, MP, HJ, CO, BTN, SB, BB
        case 9: return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP1", "MP2", "HJ", "CO"] // UTG, UTG+1, MP1, MP2, HJ, CO, BTN, SB, BB
        default: return ["BTN", "SB", "BB", "UTG", "MP", "CO"] // Default to 6-max
        }
    }
    let cardRanks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]
    let cardSuits = ["h", "d", "c", "s"]
    var allCards: [String] { cardRanks.flatMap { rank in cardSuits.map { suit in rank + suit } } }
    var usedCards: Set<String> {
        var cards = Set<String>()
        if let hc1 = heroCard1 { cards.insert(hc1) }
        if let hc2 = heroCard2 { cards.insert(hc2) }
        
        // Add all player cards
        for player in players {
            if player.isActive {
                if let c1 = player.card1 { cards.insert(c1) }
                if let c2 = player.card2 { cards.insert(c2) }
            }
        }
        
        // Add all board cards
        if let fc1 = flopCard1 { cards.insert(fc1) }
        if let fc2 = flopCard2 { cards.insert(fc2) }
        if let fc3 = flopCard3 { cards.insert(fc3) }
        if let tc = turnCard { cards.insert(tc) }
        if let rc = riverCard { cards.insert(rc) }
        return cards
    }
    var usedCardsExcludingHeroHand: Set<String> {
        var cards = Set<String>()
        // DO NOT add heroCard1 and heroCard2 here
        
        // Add cards from other players (villains)
        for player in players {
            if !player.isHero { // Only villain cards
                if let c1 = player.card1 { cards.insert(c1) }
                if let c2 = player.card2 { cards.insert(c2) }
            }
        }
        
        // Add board cards
        if let fc1 = flopCard1 { cards.insert(fc1) }
        if let fc2 = flopCard2 { cards.insert(fc2) }
        if let fc3 = flopCard3 { cards.insert(fc3) }
        if let tc = turnCard { cards.insert(tc) }
        if let rc = riverCard { cards.insert(rc) }
        
        return cards
    }

    // Reentrancy guard for posting blinds
    private var isPostingBlinds = false

    // Add properties to track betting round status
    @Published var waitingForNextStreetCards: Bool = false
    @Published var nextStreetNeeded: StreetIdentifier? = nil

    // Add a PlayerActionQueue to manage action order properly
    class PlayerActionQueue {
        private var allOrderedPositionsInHand: [String] // Static for the street: all players who started this street.
        var activePlayerPositionsInHand: Set<String> // Dynamic: subset of allOrderedPositionsInHand who haven't folded on THIS street yet.
        
        private var currentPlayerQueue: [String] // Dynamic queue for who is next up in the current betting round.
        private var currentBetAmountOnStreet: Double
        private var playerBetsOnStreet: [String: Double] // Tracks total bet by each player ON THIS STREET.
        private var playersWhoHaveActedInCurrentBettingRound: Set<String> // Who acted since last bet/raise or start of street.

        var debugQueueState: String {
            return "AllStreetStarters=\(allOrderedPositionsInHand.sorted()), StillInStreet=\(activePlayerPositionsInHand.sorted()), CurrentBet=\(currentBetAmountOnStreet), PlayerBets=\(playerBetsOnStreet), ActedThisRound=\(playersWhoHaveActedInCurrentBettingRound.sorted()), CurrentPlayerTurnQ=\(currentPlayerQueue)"
        }

        // orderedPositionsWhoStartedStreet: ALL players who are dealt into this street, in order.
        //                                   For preflop, this is all table positions.
        //                                   For postflop, this is players who didn't fold on previous streets.
        init(orderedPositionsWhoStartedStreet: [String]) {
            self.allOrderedPositionsInHand = orderedPositionsWhoStartedStreet
            self.activePlayerPositionsInHand = Set(orderedPositionsWhoStartedStreet) // Initially, all who started the street are active for it.
            self.currentPlayerQueue = orderedPositionsWhoStartedStreet // Initial turn order is everyone who started the street.
            
            self.currentBetAmountOnStreet = 0
            self.playerBetsOnStreet = [:]
            self.playersWhoHaveActedInCurrentBettingRound = Set()

            for pos in self.allOrderedPositionsInHand {
                playerBetsOnStreet[pos] = 0
            }


        }

        var isComplete: Bool {
            if activePlayerPositionsInHand.count <= 1 {

                return true
            }
            
            // Check if all players who are still active in the hand have acted in the current betting round
            // AND their current bet on the street matches the currentBetAmountOnStreet.
            let unactedPlayers = activePlayerPositionsInHand.filter { !playersWhoHaveActedInCurrentBettingRound.contains($0) }
            if !unactedPlayers.isEmpty {

                return false
            }

            // All active players have acted. Now check if their bets match.
            let betsNotMatched = activePlayerPositionsInHand.filter { (playerBetsOnStreet[$0] ?? -1) != currentBetAmountOnStreet }
            if !betsNotMatched.isEmpty {

                 return false
            }
            

            return true
        }

        func nextPlayer() -> String? {
            if isComplete { // Rely on isComplete

                return nil
            }

            // Iterate through currentPlayerQueue to find the next valid player
            // This loop handles cases where players at the front might have folded or already acted sufficiently
            // in a previous iteration but the overall round isn't complete yet.
            var tempQueue = currentPlayerQueue
            while let next = tempQueue.first {
                tempQueue.removeFirst() // Consume from temp
                
                // If player folded this street, skip.
                if !activePlayerPositionsInHand.contains(next) {

                    currentPlayerQueue.removeAll(where: { $0 == next }) // Ensure removed from main queue too
                    continue
                }

                // If player has acted and their bet matches current amount, they don't need to act now
                // unless action was re-opened (which clears playersWhoHaveActedInCurrentBettingRound for others)
                if playersWhoHaveActedInCurrentBettingRound.contains(next) && (playerBetsOnStreet[next] ?? -1) == currentBetAmountOnStreet {

                    // Move to back of currentPlayerQueue if they are still in it
                    if let idx = currentPlayerQueue.firstIndex(of: next) {
                        currentPlayerQueue.remove(at: idx)
                        currentPlayerQueue.append(next)
                    }
                    continue
                }
                

                return next // Found a player who needs to act
            }
            
            // If loop finishes, means no one in currentPlayerQueue needs to act, implies completion.
            // This state should ideally be caught by isComplete earlier.

            return nil
        }
        
        func processAction(player: String, action: PokerActionType, betAmount: Double? = nil, isBlindOrStraddle: Bool = false) {



            // Player is acting. Add to playersWhoHaveActedInCurrentBettingRound ONLY IF IT'S A VOLUNTARY ACTION.
            // Blind posts and straddle posts are forced and do not count as a player's voluntary action
            // for the purpose of closing the betting round if unraised.
            if !isBlindOrStraddle {
                playersWhoHaveActedInCurrentBettingRound.insert(player)
            }
            
            let originalQueueBeforeAction = currentPlayerQueue
            currentPlayerQueue.removeAll { $0 == player }

            switch action {
            case .fold:
                activePlayerPositionsInHand.remove(player)
                // Do not add back to currentPlayerQueue

            
            case .check: // This is always a voluntary action
                playerBetsOnStreet[player] = playerBetsOnStreet[player] ?? 0 // Should match currentBetAmountOnStreet
                currentPlayerQueue.append(player) 


            case .call: // Also always voluntary
                let amountCalled = currentBetAmountOnStreet 
                playerBetsOnStreet[player] = amountCalled
                currentPlayerQueue.append(player)


            case .bet, .raise: // Can be voluntary or a blind/straddle post
                let totalBetByPlayerThisStreet = betAmount ?? 0
                playerBetsOnStreet[player] = totalBetByPlayerThisStreet
                let oldBetAmountOnStreet = currentBetAmountOnStreet
                currentBetAmountOnStreet = totalBetByPlayerThisStreet 
                

                
                // If this bet/raise increases the amount to call, the action is re-opened for other players.
                if totalBetByPlayerThisStreet > oldBetAmountOnStreet {

                    playersWhoHaveActedInCurrentBettingRound.removeAll() // Clear for everyone
                    // The current player (actor) is only re-added if their action was voluntary (not a blind/straddle post)
                    if !isBlindOrStraddle {
                        playersWhoHaveActedInCurrentBettingRound.insert(player)
                    }
                } 
                // If it's the first bet on the street (e.g. SB posting, or first bettor post-flop)
                // and oldBetAmountOnStreet was 0, this is covered by totalBetByPlayerThisStreet > oldBetAmountOnStreet.
                // In that case, playersWhoHaveActedInCurrentBettingRound is cleared.
                // If it was a blind post, player is not added. If voluntary, player is added. This is correct.
                
                currentPlayerQueue.append(player) 

            }
            
            // Specific handling for blind/straddle AMOUNTS if they were posted as .bet
            // This ensures playerBetsOnStreet and currentBetAmountOnStreet correctly reflect the blind/straddle
            // The .bet/.raise path above should have already set these, but this is a safeguard.
            if isBlindOrStraddle { 
                 let postedAmount = betAmount ?? 0
                 // Ensure playerBetsOnStreet is correctly set for the blind/straddle poster
                 playerBetsOnStreet[player] = postedAmount 
                 // Ensure currentBetAmountOnStreet reflects the highest posted blind/straddle
                 currentBetAmountOnStreet = max(currentBetAmountOnStreet, postedAmount)

            }


        }
        
        func hasPlayerFolded(_ position: String) -> Bool {
            return !activePlayerPositionsInHand.contains(position)
        }
        
        var activePlayerCount: Int {
            return activePlayerPositionsInHand.count
        }
        
        var currentBet: Double {
            return currentBetAmountOnStreet
        }
        
        func getPlayerBetOnStreet(position: String) -> Double {
            return playerBetsOnStreet[position] ?? 0
        }
    }

    // Add property for action queues
    private var preflopActionQueue: PlayerActionQueue?
    private var flopActionQueue: PlayerActionQueue?
    private var turnActionQueue: PlayerActionQueue?
    private var riverActionQueue: PlayerActionQueue?

    // LLM Parsing Properties
    @Published var llmInputText: String = ""
    @Published var isParsingLLM: Bool = false
    @Published var llmError: String? = nil
    @Published var showingLLMParsingSection: Bool = false // To toggle visibility

    let pokerPositions = ["SB", "BB", "UTG", "UTG+1", "MP1", "MP2", "HJ", "CO", "BTN"] // ViewModel's internal reference
    private var cancellables = Set<AnyCancellable>() // For subscribers

    init(sessionId: String? = nil) { // Add sessionId to init, default to nil
        self.sessionId = sessionId // Store sessionId

        // Initialize players before calling functions that depend on them
        self.players = initialPlayers()
        updateAvailablePositions() // Ensure this exists or is handled
        
        // Post blinds and setup first actor after basic setup
        // Defer UI-related or complex logic if possible
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePreflopStateAndFirstActor()
        }
        
        setupSubscribers() // Setup reactive subscriptions
        determineNextPlayerAndUpdateState() // Initial determination of who acts
    }

    // Placeholder for updateAvailablePositions if it was more than just the computed property
    // For now, the computed `availablePositions` should suffice for player initialization.
    func updateAvailablePositions() {
        // This function might have updated UI-specific state for position pickers.
        // If `players` array and `heroPosition` are the source of truth for available positions,
        // the computed `availablePositions` property might be sufficient.
        // For the errors reported, ensuring it's callable is the first step.
        // Logic to update a specific @Published property for a picker could go here if needed.
        objectWillChange.send()
    }

    func setupSubscribers() {
        // Example: React to table size or hero position changes if they affect more than PlayerInput array
        $tableSize
            .dropFirst()
            .sink { [weak self] _ in
                self?.setupInitialPlayers() // Re-setup players
                self?.updatePreflopStateAndFirstActor() // Re-evaluate blinds and first actor
            }
            .store(in: &cancellables)

        $heroPosition
            .dropFirst()
            .sink { [weak self] _ in
                self?.setupInitialPlayers() // Re-setup players
                self?.updatePreflopStateAndFirstActor() // Re-evaluate blinds and first actor
            }
            .store(in: &cancellables)
        
        // Add other necessary subscribers here, for example, to recalculate effective stack amounts
        Publishers.CombineLatest($effectiveStackType, $effectiveStackAmount)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.updatePlayerStacksBasedOnEffectiveStack()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest($smallBlind, $bigBlind)
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main) // Debounce to avoid rapid updates
            .sink { [weak self] _, _ in
                self?.updatePlayerStacksBasedOnEffectiveStack() // If stacks depend on BB
                self?.updatePreflopStateAndFirstActor()     // Blinds changed, re-post and find first actor
            }
            .store(in: &cancellables)
    }

    // Initial player setup based on table size and hero position
    func initialPlayers() -> [PlayerInput] {
        let currentHeroPos = self.heroPosition
        let stackAmount = effectiveStackType == .bigBlinds ? effectiveStackAmount * bigBlind : effectiveStackAmount
        
        let createdPlayers = availablePositions.map {
            PlayerInput(position: $0, 
                        isActive: $0 == currentHeroPos, 
                        stack: stackAmount, 
                        heroPosition: currentHeroPos)
        }
        return createdPlayers
    }

    // The LLM processing will then activate the ones involved.
    func setupInitialPlayers() {
        let currentHeroPos = self.heroPosition
        let stackAmount = effectiveStackType == .bigBlinds ? effectiveStackAmount * bigBlind : effectiveStackAmount
        
        players = availablePositions.map {
            PlayerInput(position: $0, 
                        isActive: $0 == currentHeroPos, // Hero is active by default
                        stack: stackAmount, 
                        heroPosition: currentHeroPos)
        }
        // Ensure all non-hero players start as inactive. LLM data will activate them later.
        for i in 0..<players.count {
            if !players[i].isHero {
                players[i].isActive = false
            }
        }
        updatePlayerStacksBasedOnEffectiveStack()
        updateAvailablePositions() 
    }
    
    func updatePlayerStacksBasedOnEffectiveStack() {
        for i in 0..<players.count {
            let stackAmount = effectiveStackType == .bigBlinds ? effectiveStackAmount * bigBlind : effectiveStackAmount
            players[i].stack = stackAmount
        }
    }
    
    private func updatePreflopStateAndFirstActor() {

        
        // Debug print the current player state before posting blinds

        for player in players {

        }
        


        
        postBlinds(forceQueueRefresh: true) // This will set preflopActions with a fresh queue
        // determineNextPlayerAndUpdateState() will be called by preflopActions.didSet
    }

    // Posts blinds and sets initial preflop state. NO OTHER FOLDS HERE.
    private func postBlinds(forceQueueRefresh: Bool = false) {

        if isPostingBlinds && !forceQueueRefresh { // Allow forced refresh even if already posting (e.g. during init)

            return
        }
        isPostingBlinds = true
        defer { isPostingBlinds = false }

        var actualBlindActions: [ActionInput] = []
        if players.first(where: { $0.position == "SB" }) != nil {
            actualBlindActions.append(ActionInput(playerName: "SB", actionType: .bet, amount: smallBlind, isSystemAction: true))
        }
        if players.first(where: { $0.position == "BB" }) != nil {
            actualBlindActions.append(ActionInput(playerName: "BB", actionType: .bet, amount: bigBlind, isSystemAction: true))
        }

        // NEW: Handle optional straddle (third blind)
        if hasStraddle, let straddleAmount = straddle, straddleAmount > 0 {
            // Determine the typical straddle position: UTG (first to act preflop)
            // If UTG isn't available (e.g. 3-max), fallback to the first non-blind position in preflop order
            let preflopOrder = getPreflopActionOrder()
            if let straddlePos = preflopOrder.first(where: { pos in pos != "SB" && pos != "BB" && players.contains(where: { $0.position == pos }) }) {
                actualBlindActions.append(ActionInput(playerName: straddlePos, actionType: .bet, amount: straddleAmount, isSystemAction: true))
            }
        }

        // Get/create the queue. If forced, it will be new.
        let queue = getOrCreateActionQueue(for: .preflop, force: forceQueueRefresh)


        // Explicitly process these new/current blind actions into the queue.
        // This is crucial if the queue was just reset (force:true) or if blind values changed.
        if forceQueueRefresh || self.preflopActions.filter({ $0.isSystemAction }) != actualBlindActions.filter({ $0.isSystemAction }) {

            // The PlayerActionQueue.processAction with isBlindOrStraddle=true should correctly set/overwrite the playerBetsOnStreet.
            // No need to directly access queue.playerBetsOnStreet["SB"] = 0 from here.

            for blindAction in actualBlindActions {
                queue.processAction(
                    player: blindAction.playerName,
                    action: blindAction.actionType, // .bet
                    betAmount: blindAction.amount,
                    isBlindOrStraddle: true
                )
            }

        }

        // Update the published actions array IF they have changed.
        // This will trigger determineNextPlayerAndUpdateState via its didSet.
        if self.preflopActions != actualBlindActions {

            self.preflopActions = actualBlindActions
        } else if forceQueueRefresh {
            // If actions are the same but queue was forced, still need to determine next player with the fresh queue.

            determineNextPlayerAndUpdateState()
        } else {

        }
    }
    
    // New method to auto-fold all inactive players in preflop
    private func autoFoldAllInactivePlayers() {

        
        // REMOVE THIS METHOD COMPLETELY
        // Instead of auto-folding all inactive players at once, we'll let them fold
        // as they come up in position order through the normal queue processing
        
        // Just reset the queue to make sure inactive players are included


    }
    
    // Central function to determine next player and update all related state
    // Algorithm:
    // 1. Get or create the action queue for the current street (includes ALL players active or not)
    // 2. Find the next player to act from the queue
    // 3. If player is inactive, automatically fold them and display the fold
    // 4. If player is active, create pending action and prompt user
    // 5. When betting round is complete, advance to next street if possible
    func determineNextPlayerAndUpdateState() {

        
        if currentActionStreet == .preflop && preflopActions.isEmpty && !isPostingBlinds {
            // If no preflop actions and not currently posting blinds, post blinds first.
            postBlinds() // This will set actions and then trigger this method again via didSet.
            return
        }


        
        // Get the current queue, always forcing refresh to ensure consistency after potential undo/changes
        let actionQueue = getOrCreateActionQueue(for: currentActionStreet, force: true)

        
        // Clear any previous pending action
        self.pendingActionInput = nil
        
        // Find out who needs to act next
        let nextPlayerPosition = determineNextPlayerToAct(on: currentActionStreet)


        if let playerPos = nextPlayerPosition {
            // Check if this player is inactive - if so, automatically fold them
            let isPlayerActive = players.first(where: { $0.position == playerPos })?.isActive ?? false
            
            if !isPlayerActive {

                // Create a system fold action for the display
                let foldAction = ActionInput(
                    playerName: playerPos, 
                    actionType: .fold, 
                    isSystemAction: true
                )
                
                // Process the fold in the queue
                actionQueue.processAction(player: playerPos, action: .fold)
                
                // Add the fold action to the displayed actions for this street
                addActionInternal(foldAction, to: currentActionStreet)
                
                // Recursively call this method to get the next player
                determineNextPlayerAndUpdateState()
                return
            }
            
            // Regular flow for active player - prompt the user

            let newPendingAction = ActionInput(playerName: playerPos, actionType: .fold)
            self.pendingActionInput = newPendingAction

            
            // Update legal actions and amounts
            self.legalActionsForPendingPlayer = getLegalActions(for: playerPos, on: currentActionStreet)

            
            // If fold isn't legal for some reason, use first legal action
            if !self.legalActionsForPendingPlayer.contains(newPendingAction.actionType) {
                self.pendingActionInput?.actionType = self.legalActionsForPendingPlayer.first ?? .fold

            }
            
            // Calculate call amount and min bet/raise
            self.callAmountForPendingPlayer = calculateAmountToCall(for: playerPos, on: currentActionStreet)
            self.minBetRaiseAmountForPendingPlayer = calculateMinBetRaise(for: playerPos, on: currentActionStreet)


            // Pre-fill amount for call/check
            if self.pendingActionInput?.actionType == .call {
                self.pendingActionInput?.amount = self.callAmountForPendingPlayer

            }
        } else {
            // No more players to act on this street - betting round complete

            self.pendingActionInput = nil

            self.legalActionsForPendingPlayer = []
            
            // If there are actions on this street, advance to the next street
            if !actionsForStreet(currentActionStreet).isEmpty {

                advanceToNextStreetIfNeeded()
            } else {

            }
        }
        
        // Make sure pot amounts are up to date
        updatePotDisplay()
    }
    
    // Called when user commits an action via the UI (e.g. by tapping "Add" on the pending action line)
    func commitPendingAction() {

        
        guard var actionToCommit = pendingActionInput else {

            errorMessage = "No pending action to commit."
            return
        }



        // Validate and finalize amount based on action type before committing
        if actionToCommit.actionType == .bet || actionToCommit.actionType == .raise {
            if actionToCommit.amount ?? 0 < minBetRaiseAmountForPendingPlayer {

                errorMessage = "Amount must be at least \(minBetRaiseAmountForPendingPlayer)."
                return
            }
        } else if actionToCommit.actionType == .call {
            actionToCommit.amount = callAmountForPendingPlayer

        } else if actionToCommit.actionType == .check || actionToCommit.actionType == .fold {
            actionToCommit.amount = nil

        }

        // Get the correct action queue for this street
        let activeQueue = getOrCreateActionQueue(for: currentActionStreet)

        
        // Process the action in the queue with bet amount
        activeQueue.processAction(
            player: actionToCommit.playerName, 
            action: actionToCommit.actionType,
            betAmount: actionToCommit.amount
        )

        // Add the action to the appropriate street
        addActionInternal(actionToCommit, to: currentActionStreet)

        
        // Clear pending action BEFORE determining next player
        self.pendingActionInput = nil 

        
        // Immediately determine next player

        determineNextPlayerAndUpdateState()
        
        // Clear any error message on successful commit
        errorMessage = nil
    }

    // Internal add action, used by commitPendingAction
    private func addActionInternal(_ action: ActionInput, to street: StreetIdentifier) {
        switch street {
        case .preflop: preflopActions.append(action)
        case .flop: flopActions.append(action)
        case .turn: turnActions.append(action)
        case .river: riverActions.append(action)
        }
    }

    // Renamed and simplified: This function is called when a board card is set.
    // Its only job is to check if cards for *that specific street* are complete.
    // If so, it triggers advanceToNextStreetIfNeeded() to see if we can move forward.
    private func setupNextStreetIfReady(_ streetCardWasDealtFor: StreetIdentifier) {


        var cardsNowCompleteForStreet = false
        switch streetCardWasDealtFor {
        case .flop:
            cardsNowCompleteForStreet = flopCard1 != nil && flopCard2 != nil && flopCard3 != nil
            if cardsNowCompleteForStreet {

            }
        case .turn:
            cardsNowCompleteForStreet = turnCard != nil
            if cardsNowCompleteForStreet {

            }
        case .river:
            cardsNowCompleteForStreet = riverCard != nil
            if cardsNowCompleteForStreet {

            }
        case .preflop: // Not applicable for board cards
            return
        }

        if cardsNowCompleteForStreet {
            // If the cards for the street are complete, and we were waiting for them for the *current action street*,
            // we should clear the waiting flags and try to determine the next player again.
            if waitingForNextStreetCards && nextStreetNeeded == streetCardWasDealtFor && currentActionStreet == streetCardWasDealtFor {

                waitingForNextStreetCards = false
                nextStreetNeeded = nil
                // It's possible the queue was already forced for this street but was empty. Re-force to be sure.
                _ = getOrCreateActionQueue(for: currentActionStreet, force: true)
                determineNextPlayerAndUpdateState() 
            } else {
                // Cards for a street are complete. Now, let advanceToNextStreetIfNeeded decide if we can proceed.
                // This is the more common path: e.g., flop cards entered, preflop betting done, now try to move to flop street.

                advanceToNextStreetIfNeeded()
            }
        } else {

            // If cards became incomplete for the current action street we were waiting for, reset waiting state
            if nextStreetNeeded == streetCardWasDealtFor && currentActionStreet == streetCardWasDealtFor {
                 if !waitingForNextStreetCards { // If we weren't already waiting, but now cards are missing

                    waitingForNextStreetCards = true
                    // pendingActionInput = nil // Clear pending action if we can't proceed
                 }
            }
        }
    }

    private func advanceToNextStreetIfNeeded() {

        
        let currentQueue = getOrCreateActionQueue(for: currentActionStreet)
        if !currentQueue.isComplete {

            if pendingActionInput == nil { // If no one is currently prompted, try to prompt.
                 determineNextPlayerAndUpdateState() 
            }
            return
        }



        let streetOrder: [StreetIdentifier] = [.preflop, .flop, .turn, .river]
        guard let currentStreetOrderIndex = streetOrder.firstIndex(of: currentActionStreet) else { 

            return
        }
        
        // Check if hand ended due to folds on current street
        if currentQueue.activePlayerPositionsInHand.count <= 1 && currentActionStreet != .preflop { // Preflop has different conditions for ending (e.g. BB is last to act)

            pendingActionInput = nil
            waitingForNextStreetCards = false
            nextStreetNeeded = nil
            // Hand is over for betting. UI should reflect this. Could show winner or prompt for showdown cards.
            return
        }
        
        // Try to move to the next street in order
        if currentStreetOrderIndex + 1 < streetOrder.count {
            let potentialNextStreet = streetOrder[currentStreetOrderIndex + 1]

            
            var cardsAreSetForThePotentialNextStreet = false
            switch potentialNextStreet {
                case .flop: cardsAreSetForThePotentialNextStreet = flopCard1 != nil && flopCard2 != nil && flopCard3 != nil
                case .turn: cardsAreSetForThePotentialNextStreet = turnCard != nil
                case .river: cardsAreSetForThePotentialNextStreet = riverCard != nil
                default: // Should not happen for .preflop as a next street from here

                    return
            }
            
            if cardsAreSetForThePotentialNextStreet {

                currentActionStreet = potentialNextStreet
                waitingForNextStreetCards = false // Cleared as we are on the new street
                nextStreetNeeded = nil          // Cleared
                _ = getOrCreateActionQueue(for: currentActionStreet, force: true) // Force new queue for the new street
                determineNextPlayerAndUpdateState() // Start action on the new street
            } else {

                pendingActionInput = nil // No one to act on current street (it's complete)
                legalActionsForPendingPlayer = []
                waitingForNextStreetCards = true // Now waiting for cards for this potentialNextStreet
                nextStreetNeeded = potentialNextStreet

            }
        } else {
            // We were on the river and betting is complete, or hand ended earlier.

            pendingActionInput = nil
            legalActionsForPendingPlayer = []
            waitingForNextStreetCards = false
            nextStreetNeeded = nil
            // Hand is over for betting. UI can show showdown, pot, etc.
        }
    }

    // Replace the entire determineNextPlayerToAct function with a simpler, correct version
    func determineNextPlayerToAct(on street: StreetIdentifier) -> String? {

        
        // First, determine the active queue for this street (create if needed)
        let activeQueue = getOrCreateActionQueue(for: street)
        
        // Check if the betting round is complete
        if activeQueue.isComplete {

            return nil // No more action needed
        }
        
        // Get next player from queue
        let nextPlayer = activeQueue.nextPlayer()

        return nextPlayer
    }

    // Add hasPlayerFolded helper function if it was removed
    private func hasPlayerFolded(_ playerPosition: String, on street: StreetIdentifier) -> Bool {
        return actionsForStreet(street).contains { $0.playerName == playerPosition && $0.actionType == .fold }
    }
    
    // Simplified helper to get ONLY active players
    private func getActivePlayersOnly() -> [PlayerInput] {
        return players.filter { $0.isActive }
    }

    // Improved function to auto-fold inactive players automatically
    private func autoFoldInactivePlayers(on street: StreetIdentifier) {
        // Only do auto-folds for preflop
        if street != .preflop {
            return
        }
        
        let actions = actionsForStreet(street)
        let activePositions = players.filter { $0.isActive }.map { $0.position }
        let allPositions = availablePositions
        
        // Auto-fold any position that's not active and hasn't acted yet
        for position in allPositions {
            // Skip if player is active or already has an action
            if activePositions.contains(position) || 
               actions.contains(where: { $0.playerName == position }) {
                continue
            }
            
            // Add a system fold for this inactive player
            let foldAction = ActionInput(playerName: position, actionType: .fold, isSystemAction: true)
            
            // Add directly to the preflop actions array
            if !preflopActions.contains(where: { $0.playerName == position }) {
                preflopActions.append(foldAction)
            }
        }
    }
    
    // Helper to get the player order (active and inactive) for a street
    private func getActiveStreetOrder(for street: StreetIdentifier) -> [String] {
        let streetOrder = street == .preflop ? getPreflopActionOrder() : getPostflopActionOrder()
        let activePositions = players.filter { $0.isActive }.map { $0.position }
        
        // Get all positions, but filter so active positions are first
        return streetOrder.filter { activePositions.contains($0) } + 
               streetOrder.filter { !activePositions.contains($0) }
    }
    
    // Fix getPreflopActionOrder to ensure proper straddle action order
    private func getPreflopActionOrder() -> [String] {
        // Preflop action order is: UTG, MP, CO, BTN, SB, BB
        // BUT if straddle is active, UTG acts as straddle and UTG+1 (or next position) acts first
        let positions = self.availablePositions
        
        // Start with all positions except for blinds
        var nonBlinds = positions.filter { $0 != "SB" && $0 != "BB" }
        
        // Sort in typical UTG-first order
        let standardOrder = ["UTG", "UTG+1", "MP", "MP1", "MP2", "HJ", "CO", "BTN"]
        nonBlinds.sort { pos1, pos2 in
            let idx1 = standardOrder.firstIndex(of: pos1) ?? Int.max
            let idx2 = standardOrder.firstIndex(of: pos2) ?? Int.max
            return idx1 < idx2
        }
        
        // STRADDLE LOGIC: If straddle is active, UTG acts as straddler (like a blind)
        // and UTG+1 (or next available position) acts first
        if hasStraddle && straddle != nil && straddle! > 0 {
            // Find UTG position (straddler)
            if let utgIndex = nonBlinds.firstIndex(of: "UTG") {
                // Remove UTG from action order since they're now acting as a blind
                nonBlinds.remove(at: utgIndex)
                
                // The remaining players in nonBlinds will act first, then blinds + straddler
        var actionOrder = nonBlinds
                
                // Add blinds and straddler in order: SB, BB, UTG (straddler)
        if positions.contains("SB") {
            actionOrder.append("SB")
        }
        if positions.contains("BB") {
            actionOrder.append("BB")
        }
                actionOrder.append("UTG") // UTG acts last as straddler
                
                return actionOrder
            }
        }
        
        // Normal action order (no straddle): UTG first, then blinds last
        var actionOrder = nonBlinds
        if positions.contains("SB") {
            actionOrder.append("SB")
        }
        if positions.contains("BB") {
            actionOrder.append("BB")
        }

        return actionOrder
    }
    
    // Helper for postflop action order (SB first)
    private func getPostflopActionOrder() -> [String] {
        let currentPositions = self.availablePositions
        guard !currentPositions.isEmpty else { return [] }

        // Standard postflop order: SB, BB, UTG, ..., BTN
        let standardPostflopOrder6Max = ["SB", "BB", "UTG", "MP", "CO", "BTN"]
        let standardPostflopOrder9Max = ["SB", "BB", "UTG", "UTG+1", "MP1", "MP2", "HJ", "CO", "BTN"]
        
        // Select appropriate order based on table size
        let baseOrder: [String]
        switch tableSize {
            case 2: baseOrder = ["SB", "BB"] // 2-handed is simple
            case 3: baseOrder = ["SB", "BB", "UTG"] // 3-handed
            case 4: baseOrder = ["SB", "BB", "UTG", "CO"] // 4-handed
            case 5: baseOrder = ["SB", "BB", "UTG", "MP", "CO"] // 5-handed
            case 6: baseOrder = standardPostflopOrder6Max
            case 7: baseOrder = ["SB", "BB", "UTG", "MP", "HJ", "CO", "BTN"]
            case 8: baseOrder = ["SB", "BB", "UTG", "UTG+1", "MP", "HJ", "CO", "BTN"]
            case 9: baseOrder = standardPostflopOrder9Max
            default: baseOrder = standardPostflopOrder6Max
        }
        
        // Filter positions to only include ones available at current table size
        return baseOrder.filter { currentPositions.contains($0) }
    }
    
    // Betting Round Status - simplified
    private func bettingRoundIsOpen(on street: StreetIdentifier) -> Bool {
        return determineNextPlayerToAct(on: street) != nil
    }
    
    private func bettingRoundIsOpenToPlayer(_ playerPosition: String, on street: StreetIdentifier) -> Bool {
        return determineNextPlayerToAct(on: street) == playerPosition
    }
    
    // Helper to get actions for a specific street
    func actionsForStreet(_ street: StreetIdentifier) -> [ActionInput] {
        switch street {
        case .preflop: return preflopActions
        case .flop: return flopActions
        case .turn: return turnActions
        case .river: return riverActions
        }
    }
    
    // Add back the legal actions function
    func getLegalActions(for playerPosition: String, on street: StreetIdentifier) -> [PokerActionType] {
        var legal: [PokerActionType] = [.fold] // Always can fold

        let currentBetToCall = calculateAmountToCall(for: playerPosition, on: street)
        let playerStack = players.first(where: { $0.position == playerPosition })?.stack ?? 0

        // Check/Call logic
        if currentBetToCall == 0 { // No bet to player, can check
            legal.append(.check)
        } else { // There is a bet to player
            if playerStack >= currentBetToCall {
                legal.append(.call)
            }
        }
        
        // Bet/Raise logic
        let canBetOrRaise = playerStack > currentBetToCall // Must have more than call amount to raise
        
        if canBetOrRaise {
            if currentBetToCall == 0 { // No bet yet, can bet
                legal.append(.bet)
            } else { // Facing a bet, can raise
                legal.append(.raise)
            }
        }
        
        return legal.sorted(by: { $0.rawValue < $1.rawValue }) // Consistent order
    }
    
    // Replace complex BetState calculations with direct calculation
    func calculateAmountToCall(for playerPosition: String, on street: StreetIdentifier) -> Double {
        let actions = actionsForStreet(street)
        var highestBet = 0.0
        var playerContribution = 0.0
        
        // For preflop, consider blinds
        if street == .preflop {
            if playerPosition == "SB" {
                playerContribution = smallBlind
            } else if playerPosition == "BB" {
                playerContribution = bigBlind
            }
            highestBet = bigBlind // Start with BB as minimum preflop
        }
        
        // Find highest bet and player's contribution
        for action in actions {
            if (action.actionType == .bet || action.actionType == .raise) && 
                (action.amount ?? 0) > highestBet {
                highestBet = action.amount ?? 0
            }
            
            if action.playerName == playerPosition {
                if action.actionType == .bet || action.actionType == .raise || action.actionType == .call {
                    playerContribution = action.amount ?? 0
                }
            }
        }
        
        return max(0, highestBet - playerContribution)
    }

    // MARK: - Pot Calculation, Hand History Creation, Validation, etc. (largely unchanged for this step)
    func updatePotDisplay() {
        var runningPot = calculateAntePot() // Start with antes if any
        
        // Preflop - calculate net contributions per player
        runningPot += calculateNetContributions(for: preflopActions)
        currentPotPreflop = runningPot
        
        // Flop
        runningPot += calculateNetContributions(for: flopActions)
        currentPotFlop = runningPot
        
        // Turn
        runningPot += calculateNetContributions(for: turnActions)
        currentPotTurn = runningPot
        
        // River
        runningPot += calculateNetContributions(for: riverActions)
        currentPotRiver = runningPot
    }
    
    // Helper function to calculate net contributions per player for a street
    private func calculateNetContributions(for actions: [ActionInput]) -> Double {
        var playerContributions: [String: Double] = [:]
        
        for action in actions {
            switch action.actionType {
            case .bet, .raise:
                // For bets and raises, the amount is the total bet size for that player on this street
                playerContributions[action.playerName] = action.amount ?? 0
            case .call:
                // For calls, we need to determine what they're calling to
                let currentBet = playerContributions.values.max() ?? 0
                playerContributions[action.playerName] = currentBet
            case .fold, .check:
                // Folds and checks don't add money (player keeps whatever they already put in)
                break
            }
        }
        
        // Sum up all player contributions for this street
        return playerContributions.values.reduce(0, +)
    }

    private func calculateAntePot() -> Double {
        guard let anteAmount = self.ante, anteAmount > 0 else { return 0 }
        let activePlayerCount = players.filter { $0.isActive }.count
        return anteAmount * Double(activePlayerCount)
    }

    func createParsedHandHistory() -> ParsedHandHistory? {
        self.errorMessage = nil // Clear previous errors

        // 1. Validate input
        guard validateInputs() else { return nil }

        // 2. Create GameInfo
        let gameInfo = GameInfo(
            tableSize: self.tableSize,
            smallBlind: self.smallBlind,
            bigBlind: self.bigBlind,
            ante: self.hasAnte ? self.ante : nil,
            straddle: self.hasStraddle ? self.straddle : nil,
            dealerSeat: determineDealerSeat() // Implement this helper
        )

        // 3. Create Players array
        let playersArray = createPlayersArrayForHistory() // Implement this helper

        // 4. Create Streets array
        let streetsArray = createStreetsArrayForHistory() // Implement this helper
        
        // 5. Calculate Pot and PnL (Simplified for now, can be expanded)
        // For a true calculation, we'd need to process actions against stacks.
        // This is a placeholder for now, as the full logic is complex.
        let (finalPotAmount, heroPnLAmount, potDistribution) = calculatePotAndDistribution(players: playersArray, streets: streetsArray) 

        let pot = Pot(
            amount: finalPotAmount, 
            distribution: potDistribution, 
            heroPnl: heroPnLAmount
        )
        
        // 6. Determine Showdown (Simplified)
        let showdownOccurred = didShowdownOccur(streets: streetsArray, activePlayers: playersArray.filter { playerInvolvedInHand($0, streets: streetsArray) } ) // Implement this

        // 7. Create RawHandHistory
        let rawHandHistory = RawHandHistory(
            gameInfo: gameInfo,
            players: playersArray,
            streets: streetsArray,
            pot: pot,
            showdown: showdownOccurred
        )

        return ParsedHandHistory(raw: rawHandHistory)
    }

    private func validateInputs() -> Bool {
        if smallBlind <= 0 || bigBlind <= 0 {
            errorMessage = "Blinds must be greater than 0."
            return false
        }
        if heroCard1 == nil || heroCard2 == nil {
            errorMessage = "Hero must have two cards."
            return false
        }
        // Ensure hero has a position
        guard players.contains(where: { $0.isHero && $0.position == heroPosition }) else {
            errorMessage = "Hero position is not set correctly."
            return false
        }
        // Ensure at least two players are active to form a hand
        if players.filter({ $0.isActive }).count < 2 {
            errorMessage = "At least two players must be active in the hand."
            return false
        }
        // Basic preflop action validation
        if preflopActions.filter({ $0.actionType != .fold }).count < 1 && players.filter({$0.isActive}).count > 1 { // if more than 1 active player, need non-fold action
             //This allows scenarios where everyone folds to hero
            if !(preflopActions.allSatisfy({ $0.actionType == .fold }) && players.first(where: {$0.isHero})?.isActive == true) {
                 errorMessage = "Preflop needs at least one action (bet, call, raise) if multiple players are active, or hero is not the only active player."
                 // return false // Temporarily relax this for simpler entries
            }
        }
        return true
    }

    private func determineDealerSeat() -> Int {
        // Players are already ordered by typical poker seating (BTN, SB, BB, UTG...)
        // The ViewModel's `players` array should reflect this order if `availablePositions` is standard.
        if let btnPlayerIndex = players.firstIndex(where: { $0.position == "BTN" }) {
            return btnPlayerIndex + 1 // Seat numbers are 1-indexed
        }
        // Fallback if BTN is not explicitly in the list (e.g. 2-handed where SB is dealer)
        if tableSize == 2, let sbPlayerIndex = players.firstIndex(where: { $0.position == "SB" }) {
             return sbPlayerIndex + 1
        }
        return 1 // Default to seat 1 if no BTN found (should ideally not happen with proper setup)
    }

    private func createPlayersArrayForHistory() -> [Player] {
        var seatCounter = 1
        return self.players.map { pInput -> Player in
            // Get the current cards for this player
            var playerCards: [String]? = nil
            var playerFinalCards: [String]? = nil
            
            if pInput.isHero {
                // For hero, use the heroCard1 and heroCard2 from ViewModel
                let heroCards = [heroCard1, heroCard2].compactMap { $0 }
                playerCards = heroCards.isEmpty ? nil : heroCards
                playerFinalCards = playerCards // Hero cards are both hole cards and final cards
            } else {
                // For villains, use the card1 and card2 from the PlayerInput
                let villainCards = [pInput.card1, pInput.card2].compactMap { $0 }
                playerCards = villainCards.isEmpty ? nil : villainCards
                playerFinalCards = playerCards // Villain cards are both hole cards and final cards
            }
            
            // Calculate adjusted stack after ante deduction
            var adjustedStack = pInput.stack
            if let anteAmount = self.ante, anteAmount > 0, pInput.isActive {
                adjustedStack -= anteAmount
            }
            
            let player = Player(
                name: pInput.name,
                seat: seatCounter, // Assign seat based on order in `players` array
                stack: adjustedStack, // Stack after ante deduction
                position: pInput.position,
                isHero: pInput.isHero,
                cards: playerCards, // Current hole cards from ViewModel state
                finalHand: nil, // To be determined by evaluator or post-processing
                finalCards: playerFinalCards // Same as cards for now, used in hand evaluation
            )
            seatCounter += 1
            return player
        }
    }

    private func createStreetsArrayForHistory() -> [Street] {
        var streets: [Street] = []

        // Preflop
        let preflopMappedActions = mapActionInputsToActions(preflopActions)
        streets.append(Street(name: "preflop", cards: [], actions: preflopMappedActions))

        // Flop - use current ViewModel state for cards
        let currentFlopCards = [flopCard1, flopCard2, flopCard3].compactMap { $0 }
        if !currentFlopCards.isEmpty || !flopActions.isEmpty {
            let flopMappedActions = mapActionInputsToActions(flopActions)
            // Only include flop cards if all 3 are present
            let flopCardsToInclude = currentFlopCards.count == 3 ? currentFlopCards : []
            streets.append(Street(name: "flop", cards: flopCardsToInclude, actions: flopMappedActions))
        }

        // Turn - use current ViewModel state for cards
        if !currentFlopCards.isEmpty, (turnCard != nil || !turnActions.isEmpty) {
            let turnMappedActions = mapActionInputsToActions(turnActions)
            // Include turn card if it exists
            let turnCardsToInclude = turnCard != nil ? [turnCard!] : []
            streets.append(Street(name: "turn", cards: turnCardsToInclude, actions: turnMappedActions))
        }

        // River - use current ViewModel state for cards
        if turnCard != nil, (riverCard != nil || !riverActions.isEmpty) {
            let riverMappedActions = mapActionInputsToActions(riverActions)
            // Include river card if it exists
            let riverCardsToInclude = riverCard != nil ? [riverCard!] : []
            streets.append(Street(name: "river", cards: riverCardsToInclude, actions: riverMappedActions))
        }
        
        return streets
    }
    
    private func mapActionInputsToActions(_ inputs: [ActionInput]) -> [Action] {
        return inputs.map { input in
            // Find the player name from the `players` array based on position string
            let playerName = players.first { $0.position == input.playerName }?.name ?? input.playerName
            
            // Convert action type to the format expected by HandReplayView
            let actionString: String
            switch input.actionType {
            case .fold:
                actionString = "folds"
            case .check:
                actionString = "checks"
            case .call:
                actionString = "calls"
            case .bet:
                // For blinds, use specific blind posting format
                if input.isSystemAction && input.playerName == "SB" {
                    actionString = "posts small blind"
                } else if input.isSystemAction && input.playerName == "BB" {
                    actionString = "posts big blind"
                } else if input.isSystemAction && hasStraddle && input.amount == straddle {
                    actionString = "posts"
                } else {
                    actionString = "bets"
                }
            case .raise:
                actionString = "raises"
            }
            
            return Action(
                playerName: playerName, 
                action: actionString, 
                amount: input.amount ?? 0, 
                cards: nil
            )
        }
    }
    
    // Placeholder for pot calculation logic
    private func calculatePotAndDistribution(players: [Player], streets: [Street]) -> (potAmount: Double, heroPnl: Double, distribution: [PotDistribution]?) {
        // Calculate total pot using the same logic as updatePotDisplay
        var totalPot: Double = 0
        
        // Add antes if any
        if let anteAmount = self.ante, anteAmount > 0 {
            let activePlayerCount = self.players.filter { $0.isActive }.count
            totalPot += anteAmount * Double(activePlayerCount)
        }
        
        // Calculate net contributions per street
        for street in streets {
            totalPot += calculateNetContributionsForStreet(street.actions)
        }
        
        // Determine winner using HandEvaluator if we have a showdown
        let showdownOccurred = didShowdownOccur(streets: streets, activePlayers: players.filter { playerInvolvedInHand($0, streets: streets) })
        
        var distribution: [PotDistribution]? = nil
        var heroPnl: Double = 0
        
        if showdownOccurred {
            // Get active players at showdown (those who didn't fold)
            let foldedPlayers = Set(streets.flatMap { $0.actions }
                .filter { $0.action.lowercased() == "folds" }
                .map { $0.playerName })
            
            let activePlayersAtShowdown = players.filter { !foldedPlayers.contains($0.name) }
            
            if activePlayersAtShowdown.count > 1 {
                // Use HandEvaluator to determine winner
                let communityCards = streets.flatMap { $0.cards }
                var playerHands: [(playerName: String, cards: [String])] = []
                
                for player in activePlayersAtShowdown {
                    var playerCards: [String] = []
                    
                    // Get player's hole cards
                    if let cards = player.cards, !cards.isEmpty {
                        playerCards.append(contentsOf: cards)
                    }
                    
                    // Add community cards
                    playerCards.append(contentsOf: communityCards)
                    
                    if playerCards.count >= 5 { // Need at least 5 cards for evaluation
                        playerHands.append((player.name, playerCards))
                    }
                }
                
                if !playerHands.isEmpty {
                    let results = HandEvaluator.determineWinner(hands: playerHands)
                    let winners = results.filter { $0.winner }
                    
                    if !winners.isEmpty {
                        let winnerShare = totalPot / Double(winners.count)
                        distribution = winners.map { result in
                            PotDistribution(
                                playerName: result.playerName,
                                amount: winnerShare,
                                hand: result.handDescription,
                                cards: playerHands.first { $0.playerName == result.playerName }?.cards.prefix(2).map { String($0) } ?? []
                            )
                        }
                    }
                }
            } else if activePlayersAtShowdown.count == 1 {
                // Only one player left, they win by default
                let winner = activePlayersAtShowdown.first!
                distribution = [PotDistribution(
                    playerName: winner.name,
                    amount: totalPot,
                    hand: "Winner by fold",
                    cards: winner.cards ?? []
                )]
            }
            } else {
            // No showdown - someone won by everyone else folding
            let foldedPlayers = Set(streets.flatMap { $0.actions }
                .filter { $0.action.lowercased() == "folds" }
                .map { $0.playerName })
            
            let remainingPlayers = players.filter { !foldedPlayers.contains($0.name) }
            
            if remainingPlayers.count == 1 {
                let winner = remainingPlayers.first!
                distribution = [PotDistribution(
                    playerName: winner.name,
                    amount: totalPot,
                    hand: "Winner by fold",
                    cards: winner.cards ?? []
                )]
            }
        }
        
        // Calculate hero PnL using PokerCalculator
        if let hero = players.first(where: { $0.isHero }) {
            // Create a temporary RawHandHistory for PnL calculation
            let tempGameInfo = GameInfo(
                tableSize: self.tableSize,
                smallBlind: self.smallBlind,
                bigBlind: self.bigBlind,
                ante: self.hasAnte ? self.ante : nil,
                straddle: self.hasStraddle ? self.straddle : nil,
                dealerSeat: 1
            )
            
            let tempHand = RawHandHistory(
                gameInfo: tempGameInfo,
                players: players,
                streets: streets,
                pot: Pot(amount: totalPot, distribution: distribution, heroPnl: 0),
                showdown: showdownOccurred
            )
            
            heroPnl = PokerCalculator.calculateHandHistoryPnL(hand: tempHand)
        }
        
        return (totalPot, heroPnl, distribution)
    }
    
    // Helper function to calculate net contributions for a street's actions (similar to the one in updatePotDisplay)
    private func calculateNetContributionsForStreet(_ actions: [Action]) -> Double {
        var playerContributions: [String: Double] = [:]
        
        for action in actions {
            switch action.action.lowercased() {
            case "bets", "raises", "posts small blind", "posts big blind", "posts":
                // For bets, raises, and posts, the amount is the total bet size for that player on this street
                playerContributions[action.playerName] = action.amount
            case "calls":
                // For calls, we need to determine what they're calling to
                let currentBet = playerContributions.values.max() ?? 0
                playerContributions[action.playerName] = currentBet
            case "folds", "checks":
                // Folds and checks don't add money (player keeps whatever they already put in)
                break
            default:
                break
            }
        }
        
        // Sum up all player contributions for this street
        return playerContributions.values.reduce(0, +)
    }

    // Improve didShowdownOccur function to better detect showdown scenarios
    private func didShowdownOccur(streets: [Street], activePlayers: [Player]) -> Bool {
        // First check - if only one player remains active, there's no showdown
        if activePlayers.count <= 1 {

            return false
        }
        
        // If there are multiple players with cards shown, it's a showdown
        let playersWithCards = activePlayers.filter { player in
            return player.cards != nil && player.cards!.count >= 2
        }
        
        if playersWithCards.count >= 2 {

            return true
        }
        
        // Check if we've reached the river with multiple active players
        if let riverStreet = streets.first(where: { $0.name == "river" }), !riverStreet.actions.isEmpty {
            let activePlayers = getActivePlayersAtEndOfStreet(streets: streets)
            if activePlayers.count >= 2 {

                return true
            }
        }
        
        // Check the last street's actions - if betting is closed and multiple players remain, it's a showdown
        if let lastStreet = streets.last, !lastStreet.actions.isEmpty {
            // Get players who haven't folded on this street
            let activePlayers = getActivePlayersAtEndOfStreet(streets: streets)
            if activePlayers.count >= 2 {
                // If the last action is a call or check, and there's at least one bet/raise, it's a showdown
                let hasBetOrRaise = lastStreet.actions.contains { $0.action.lowercased() == "bets" || $0.action.lowercased() == "raises" }
                let lastAction = lastStreet.actions.last!
                let isLastActionCallOrCheck = lastAction.action.lowercased() == "calls" || lastAction.action.lowercased() == "checks"
                
                if hasBetOrRaise && isLastActionCallOrCheck {

                    return true
                }
                
                // If all players checked through, it's a showdown
                if lastStreet.actions.allSatisfy({ $0.action.lowercased() == "checks" }) && lastStreet.actions.count >= 2 {

                    return true
                }
            }
        }
        
        // Otherwise, no showdown
        return false
    }
    
    private func playerInvolvedInHand(_ player: Player, streets: [Street]) -> Bool {
        for street in streets {
            if street.actions.contains(where: { $0.playerName == player.name && $0.action.lowercased() != "folds" }) {
                return true // Player made an action other than fold
            }
            if street.actions.contains(where: { $0.playerName == player.name && $0.action.lowercased() == "folds" }) {
                return true // Player folded, so was involved
            }
        }
        // Check if player is SB or BB and posted, even if no other actions
        if player.position == "SB" && preflopActions.contains(where: {$0.playerName == player.name && $0.actionType == .bet && $0.amount == smallBlind}) { return true }
        if player.position == "BB" && preflopActions.contains(where: {$0.playerName == player.name && $0.actionType == .bet && $0.amount == bigBlind}) { return true }
        return false
    }

    // MARK: - Call Amount Calculation
    func calculateMinBetRaise(for playerPosition: String, on street: StreetIdentifier) -> Double {
        let actions = actionsForStreet(street)
        let bigBlindAmount = self.bigBlind

        // Find the amount of the last bet or raise on this street
        let lastBetOrRaiseAction = actions.filter { $0.actionType == .bet || $0.actionType == .raise }.last
        let lastBetOrRaiseAmount = lastBetOrRaiseAction?.amount ?? 0

        // Determine the amount to call for the current player
        let amountToCall = calculateAmountToCall(for: playerPosition, on: street)

        var minRaiseAmount: Double
        if lastBetOrRaiseAmount == 0 { // No previous bet or raise this street (e.g., opening bet)
            minRaiseAmount = bigBlindAmount // Minimum opening bet is typically BB
        } else {
            // There was a previous bet/raise. A raise must be at least the size of the last bet/raise increment.
            // Example: BB is 10. P1 bets 10. P2 raises. Min raise to 20.
            // P1 bets 10. P2 raises to 30 (raise of 20). P3 re-raises. Min raise to 50 (30 + 20).
            let lastRaiseIncrement = lastBetOrRaiseAmount - (actions.filter({ ($0.actionType == .bet || $0.actionType == .raise) && $0.id != lastBetOrRaiseAction?.id }).last?.amount ?? 0)
            let increment = max(lastRaiseIncrement, bigBlindAmount) // Raise must be at least BB
            minRaiseAmount = amountToCall + increment // Total amount for the minimum raise
        }
        // Ensure min bet/raise is at least the big blind
        minRaiseAmount = max(minRaiseAmount, bigBlindAmount)
        
        let playerStack = players.first(where: { $0.position == playerPosition })?.stack ?? 0
        return min(minRaiseAmount, playerStack) // Cannot bet/raise more than stack
    }

    // New: Get used cards excluding a specific player's hand (for villain card selection)
    func usedCardsExcludingPlayer(playerId: UUID) -> Set<String> {
        var cards = Set<String>()

        // Add hero cards
        if let hc1 = heroCard1 { cards.insert(hc1) }
        if let hc2 = heroCard2 { cards.insert(hc2) }

        // Add cards from other players, EXCLUDING the specified player
        for player in players {
            if player.id != playerId {
                if let c1 = player.card1 { cards.insert(c1) }
                if let c2 = player.card2 { cards.insert(c2) }
            }
        }

        // Add board cards
        if let fc1 = flopCard1 { cards.insert(fc1) }
        if let fc2 = flopCard2 { cards.insert(fc2) }
        if let fc3 = flopCard3 { cards.insert(fc3) }
        if let tc = turnCard { cards.insert(tc) }
        if let rc = riverCard { cards.insert(rc) }
        
        return cards
    }
    
    // New: Update a specific player's cards
    func updatePlayerCards(playerId: UUID, card1: String?, card2: String?) {
        if let index = players.firstIndex(where: { $0.id == playerId }) {
            players[index].card1 = card1
            players[index].card2 = card2
            // No need to call determineNextPlayerAndUpdateState directly, as `players.didSet` should handle UI refresh if needed.
            // However, if card changes should affect available usedCards immediately for other pickers, direct updates are fine.
        }
    }

    // Add an undo function to remove the last action
    func undoLastAction() {

        
        var actionsOnThisStreet: [ActionInput]
        switch currentActionStreet {
        case .preflop: actionsOnThisStreet = preflopActions
        case .flop: actionsOnThisStreet = flopActions
        case .turn: actionsOnThisStreet = turnActions
        case .river: actionsOnThisStreet = riverActions
        }
        
        guard let actionToUndo = actionsOnThisStreet.last else {

            return
        }

        // Prevent undoing system-generated actions like initial blinds if they are the only ones, or auto-folds.
        // User should only be able to undo their own manual entries.
        if actionToUndo.isSystemAction {

            // Allow undoing blinds if there are other non-system actions after them, effectively rewinding to before the last player action.
            // However, the current logic is to find the *last* action. If it's a system action, block.
            // This means if user posts blind, then UTG acts, then user wants to undo UTG, that's fine.
            // If only blinds are posted, and user hits undo, it should ideally do nothing or give specific feedback.
            // For now, a simple block on system action as *the last action* is okay.
            return
        }

        let undonePlayerName = actionToUndo.playerName
        let undoneActionType = actionToUndo.actionType
        let undoneAmount = actionToUndo.amount

        // Remove the last action. Its didSet will trigger determineNextPlayerAndUpdateState.
        // determineNextPlayerAndUpdateState will use a forced-rebuilt queue due to prior changes.
        switch currentActionStreet {
        case .preflop:
            if !preflopActions.isEmpty && preflopActions.last?.id == actionToUndo.id { // Ensure we're removing the exact action
                preflopActions.removeLast()
            }
        case .flop:
            if !flopActions.isEmpty && flopActions.last?.id == actionToUndo.id {
                flopActions.removeLast()
            }
        case .turn:
            if !turnActions.isEmpty && turnActions.last?.id == actionToUndo.id {
                turnActions.removeLast()
            }
        case .river:
            if !riverActions.isEmpty && riverActions.last?.id == actionToUndo.id {
                riverActions.removeLast()
            }
        }

        // After the didSet chain from action removal completes and pendingActionInput is set (likely for undonePlayerName):
        // Schedule an update to restore the specific action type and amount.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.pendingActionInput?.playerName == undonePlayerName {

                self.pendingActionInput?.actionType = undoneActionType
                self.pendingActionInput?.amount = undoneAmount

                // It's important that legalActions, callAmount, minBet/Raise are also updated 
                // to reflect the state *as if* this pendingAction (with restored type/amount) is about to be made.
                // determineNextPlayerAndUpdateState would have set these initially, possibly for a default 'fold'.
                // So, we need to recalculate them here based on the restored pending action.
                self.legalActionsForPendingPlayer = self.getLegalActions(for: undonePlayerName, on: self.currentActionStreet)
                self.callAmountForPendingPlayer = self.calculateAmountToCall(for: undonePlayerName, on: self.currentActionStreet)
                self.minBetRaiseAmountForPendingPlayer = self.calculateMinBetRaise(for: undonePlayerName, on: self.currentActionStreet)

                // If the restored action was a call, ensure its amount is the current correct call amount.
                // Or, if it was a bet/raise, ensure it's still valid.
                // For now, primarily restoring. User can adjust if action becomes invalid due to reverted state.
                // The pendingActionInput.amount is already restored. The slider/UI will use this.
            }
        }
    }

    // Helper to get or create action queue for a street
    private func getOrCreateActionQueue(for street: StreetIdentifier, force: Bool = false) -> PlayerActionQueue {


        switch street {
        case .preflop:
            if preflopActionQueue == nil || force {
                let positionsInOrder = getPreflopActionOrder()

                preflopActionQueue = PlayerActionQueue(orderedPositionsWhoStartedStreet: positionsInOrder)
                
                if force { // If forced, replay all existing preflop actions into the new queue.

                    for action in self.preflopActions {
                        let isBlind = action.isSystemAction && (action.playerName == "SB" || action.playerName == "BB") && action.actionType == .bet
                        preflopActionQueue!.processAction(
                            player: action.playerName,
                            action: action.actionType,
                            betAmount: action.amount,
                            isBlindOrStraddle: isBlind
                        )
                    }
                }

            } else {

            }
            return preflopActionQueue!

        case .flop:
            if flopActionQueue == nil || force {

                let postflopStandardOrder = getPostflopActionOrder()
                let preflopFoldedPlayers = Set(preflopActions.filter { $0.actionType == .fold }.map { $0.playerName })
                let playersWhoMadeItToFlop = players
                    .filter { $0.isActive && !preflopFoldedPlayers.contains($0.position) }
                    .map { $0.position }
                let orderedPlayersForFlopStreet = postflopStandardOrder.filter { playersWhoMadeItToFlop.contains($0) }
                flopActionQueue = PlayerActionQueue(orderedPositionsWhoStartedStreet: orderedPlayersForFlopStreet)

                if force { // If forced, replay all existing flop actions

                    for action in self.flopActions {
                        flopActionQueue!.processAction(
                            player: action.playerName,
                            action: action.actionType,
                            betAmount: action.amount,
                            isBlindOrStraddle: false // No blinds on flop
                        )
                    }
                }

            } else {

            }
            return flopActionQueue!

        case .turn:
            if turnActionQueue == nil || force {

                let postflopStandardOrder = getPostflopActionOrder()
                let preflopFoldedPlayers = Set(preflopActions.filter { $0.actionType == .fold }.map { $0.playerName })
                let flopFoldedPlayers = Set(flopActions.filter { $0.actionType == .fold }.map { $0.playerName })
                let cumulativeFoldedPlayers = preflopFoldedPlayers.union(flopFoldedPlayers)
                let playersWhoMadeItToTurn = players
                    .filter { $0.isActive && !cumulativeFoldedPlayers.contains($0.position) }
                    .map { $0.position }
                let orderedPlayersForTurnStreet = postflopStandardOrder.filter { playersWhoMadeItToTurn.contains($0) }
                turnActionQueue = PlayerActionQueue(orderedPositionsWhoStartedStreet: orderedPlayersForTurnStreet)

                if force { // If forced, replay all existing turn actions

                    for action in self.turnActions {
                        turnActionQueue!.processAction(
                            player: action.playerName,
                            action: action.actionType,
                            betAmount: action.amount,
                            isBlindOrStraddle: false // No blinds on turn
                        )
                    }
                }

            } else {

            }
            return turnActionQueue!

        case .river:
            if riverActionQueue == nil || force {

                let postflopStandardOrder = getPostflopActionOrder()
                let preflopFoldedPlayers = Set(preflopActions.filter { $0.actionType == .fold }.map { $0.playerName })
                let flopFoldedPlayers = Set(flopActions.filter { $0.actionType == .fold }.map { $0.playerName })
                let turnFoldedPlayers = Set(turnActions.filter { $0.actionType == .fold }.map { $0.playerName })
                let cumulativeFoldedPlayers = preflopFoldedPlayers.union(flopFoldedPlayers).union(turnFoldedPlayers)
                let playersWhoMadeItToRiver = players
                    .filter { $0.isActive && !cumulativeFoldedPlayers.contains($0.position) }
                    .map { $0.position }
                let orderedPlayersForRiverStreet = postflopStandardOrder.filter { playersWhoMadeItToRiver.contains($0) }
                riverActionQueue = PlayerActionQueue(orderedPositionsWhoStartedStreet: orderedPlayersForRiverStreet)

                if force { // If forced, replay all existing river actions

                    for action in self.riverActions {
                        riverActionQueue!.processAction(
                            player: action.playerName,
                            action: action.actionType,
                            betAmount: action.amount,
                            isBlindOrStraddle: false // No blinds on river
                        )
                    }
                }

            } else {

            }
            return riverActionQueue!
        }
    }

    // Helper to get non-folded positions (players who haven't folded yet)
    private func getNonFoldedPositions(from previousStreet: StreetIdentifier) -> [String] {
        // Get all positions
        let allPositions = self.availablePositions
        
        // Get all folded players from the previous street(s)
        let foldedPlayers = getPlayersWhoFolded(onOrBefore: previousStreet)
        
        // Also consider any inactive players as folded for streets after preflop
        var effectiveFoldedPlayers = foldedPlayers
        if previousStreet != .preflop {
            for player in players where !player.isActive {
                effectiveFoldedPlayers.insert(player.position)
            }
        }
        
        // Return players who haven't folded
        return allPositions.filter { !effectiveFoldedPlayers.contains($0) }
    }

    // Helper to find players who folded on or before a specific street
    private func getPlayersWhoFolded(onOrBefore street: StreetIdentifier) -> Set<String> {
        var folded = Set<String>()
        
        // Check all streets up to and including the specified one
        let streetOrder: [StreetIdentifier] = [.preflop, .flop, .turn, .river]
        for s in streetOrder {
            let actions = actionsForStreet(s)
            for action in actions {
                if action.actionType == .fold {
                    folded.insert(action.playerName)
                }
            }
            
            if s == street {
                break
            }
        }
        
        return folded
    }

    // Fix problem where blind posters might need to act
    private func adjustQueueForBlindPosters() {
        guard let queue = preflopActionQueue else { return }
        
        // Print the current queue state

        
        // Force the queue to update the next player
        _ = queue.nextPlayer()
        

    }

    // New method to reset all action queues when active players change
    private func resetActionQueues() {

        preflopActionQueue = nil
        flopActionQueue = nil
        turnActionQueue = nil
        riverActionQueue = nil
        
        // Only clear actions if we're starting fresh
        if preflopActions.isEmpty || (preflopActions.count <= 2 && 
                                   preflopActions.allSatisfy({ $0.isSystemAction })) {
            preflopActions = []
            flopActions = []
            turnActions = []
            riverActions = []

        } else {

        }
        
        // Reset pending action
        pendingActionInput = nil
    }

    // Add method to update active players in the queue when they change in the UI
    func updateQueueWithNewActiveStatus() {

        
        // Get the current active positions
        let currentActive = players.filter { $0.isActive }.map { $0.position }

        
        // Update the queue for the current street
        let queue = getOrCreateActionQueue(for: currentActionStreet, force: true)
        
        // Force re-determination of next player
        determineNextPlayerAndUpdateState()
    }

    // Helper to get active players at the end of the hand
    private func getActivePlayersAtEndOfStreet(streets: [Street]) -> [String] {
        // Start with all player names
        var activePlayers = Set<String>()
        
        // Add all players who have acted
        for street in streets {
            for action in street.actions {
                activePlayers.insert(action.playerName)
            }
        }
        
        // Remove players who folded
        for street in streets {
            for action in street.actions {
                if action.action.lowercased() == "folds" {
                    activePlayers.remove(action.playerName)
                }
            }
        }
        
        return Array(activePlayers)
    }

    // Method to set the current street for the UI
    func setCurrentStreet(street: StreetIdentifier) {
        currentActionStreet = street

    }

    // Method to get the next player to act and prepare the UI
    func getNextPlayerToAct() {

        
        // Clear any existing pending action
        pendingActionInput = nil
        
        // Get the action queue for the current street
        let queue = getOrCreateActionQueue(for: currentActionStreet)
        
        // Get the next player from the queue
        if let nextPlayerPosition = queue.nextPlayer() {

            
            // Determine legal actions for this player
            legalActionsForPendingPlayer = getLegalActions(for: nextPlayerPosition, on: currentActionStreet)
            
            // Create pending action for this player
            pendingActionInput = ActionInput(
                playerName: nextPlayerPosition,
                actionType: legalActionsForPendingPlayer.first ?? .fold
            )
            
            // Set initial amounts if needed
            if pendingActionInput!.actionType == .call {
                pendingActionInput!.amount = callAmountForPendingPlayer
            } else if pendingActionInput!.actionType == .bet || pendingActionInput!.actionType == .raise {
                pendingActionInput!.amount = minBetRaiseAmountForPendingPlayer
            }
        } else {

            
            // If no next player and we're at the preflop street, move to flop
            // (Other streets rely on card selection to advance)
            if currentActionStreet == .preflop && !preflopActions.isEmpty {
                waitingForNextStreetCards = true
                nextStreetNeeded = .flop
            }
        }
    }

    // MARK: - LLM Parsing Logic

    private func mapLLMPositionToViewModelPosition(_ llmPosition: String, tableSize: Int, availableViewModelPositions: [String]) -> String {
        let lowerLLMPos = llmPosition.lowercased()
        
        // First check for direct matches (case insensitive)
        if let directMatch = availableViewModelPositions.first(where: { $0.lowercased() == lowerLLMPos }) {
            return directMatch
        }

        // Create a comprehensive mapping for all possible LLM position variations
        let positionMappings: [String: [String]] = [
            "SB": ["sb", "small", "small blind", "smallblind"],
            "BB": ["bb", "big", "big blind", "bigblind"],
            "UTG": ["utg", "under the gun", "underthegun"],
            "UTG+1": ["utg+1", "utg1", "utg plus 1", "utg plus one"],
            "MP": ["mp", "middle", "middle position", "hj", "hijack", "lj", "lojack"], // In 6-max, HJ often becomes MP
            "MP1": ["mp1", "middle1", "lj", "lojack"],
            "MP2": ["mp2", "middle2"],
            "HJ": ["hj", "hijack", "mp"], // In larger games, HJ is distinct
            "CO": ["co", "cutoff", "cut off"],
            "BTN": ["btn", "button", "dealer", "d"]
        ]
        
        // Find the best match based on available positions
        for (viewModelPos, variations) in positionMappings {
            if availableViewModelPositions.contains(viewModelPos) && variations.contains(lowerLLMPos) {
                return viewModelPos
            }
        }
        
        // Special handling for ambiguous positions based on table size
        
        
        switch lowerLLMPos {
        case "hj", "hijack":
            if availableViewModelPositions.contains("HJ") {
                return "HJ"
            } else if availableViewModelPositions.contains("MP") {
                return "MP" // In 6-max, HJ becomes MP
            } else if availableViewModelPositions.contains("CO") {
                return "CO" // In smaller games, might be CO
            }
        case "lj", "lojack":
            if availableViewModelPositions.contains("MP1") {
                return "MP1"
            } else if availableViewModelPositions.contains("MP") {
                return "MP"
            } else if availableViewModelPositions.contains("UTG+1") {
                return "UTG+1"
            }
        default:
            break // No special handling needed for other positions
        }
        
        print("Warning: No mapping found for LLM position '\(llmPosition)' at table size \(tableSize). Available positions: \(availableViewModelPositions). Using uppercase as fallback.")
        return llmPosition.uppercased()
    }

    func parseHandWithLLM() async {
        guard !llmInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                llmError = "Please enter hand history text."
            }
            return
        }

        await MainActor.run {
            isParsingLLM = true
            llmError = nil
        }

        // RE-ENABLED: HTTP request to LLM API
        let urlString = "https://europe-west1-stack-24dea.cloudfunctions.net/parse_poker_hand"
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                llmError = "Invalid URL for LLM parsing."
                isParsingLLM = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ["handDescription": llmInputText] // Changed "text" to "handDescription"
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            await MainActor.run {
                llmError = "Failed to encode request: \\(error.localizedDescription)"
                isParsingLLM = false
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let responseDataString = String(data: data, encoding: .utf8) ?? "No parsable response data"
                
                print("--- LLM Parsing HTTP Error ---")
                print("Status Code: \(statusCode)")
                print("Response Data: \(responseDataString)")
                print("-----------------------------")
                
                let clientErrorMessage = "LLM parsing failed (Status: \(statusCode)). Check console for details."
                await MainActor.run {
                    llmError = clientErrorMessage
                    isParsingLLM = false
                }
                return
            }

            // Print raw response for successful (200) but potentially unparsable JSON
            let rawSuccessfulResponse = String(data: data, encoding: .utf8) ?? "Could not decode successful response to string"
            print("--- LLM Parsing Success (Raw Response) ---")
            print(rawSuccessfulResponse)
            print("-----------------------------------------")

            let decodedResponse = try JSONDecoder().decode(LLMParsedResponse.self, from: data)
            await MainActor.run {
                applyLLMParsedData(decodedResponse)
                isParsingLLM = false
            }
        } catch {
            print("--- LLM Parsing Decoding Error ---")
            print("Error: \(error)")
            print("Localized Description: \(error.localizedDescription)")
            // If you want to see what data caused the decoding error:
            // if let dataString = String(data: data, encoding: .utf8) { // `data` is not in this catch block's scope
            //    print("Data causing error: \(dataString)") 
            // }
            print("---------------------------------")
            await MainActor.run {
                llmError = "LLM parsing error: \(error.localizedDescription). Check console."
                isParsingLLM = false
            }
        }

        // COMMENTED OUT: Testing mode for JSON input
        /*
        // TESTING MODE: Parse llmInputText directly as JSON
        do {
            print("--- Testing Mode: Parsing JSON directly ---")
            print("Input JSON: \(llmInputText)")
            print("------------------------------------------")
            
            guard let jsonData = llmInputText.data(using: .utf8) else {
                await MainActor.run {
                    llmError = "Could not convert input text to data."
                    isParsingLLM = false
                }
                return
            }
            
            let decodedResponse = try JSONDecoder().decode(LLMParsedResponse.self, from: jsonData)
            print("--- JSON Parsing Success ---")
            print("Decoded response: \(decodedResponse)")
            print("----------------------------")
            
            await MainActor.run {
                applyLLMParsedData(decodedResponse)
                isParsingLLM = false
            }
        } catch {
            print("--- JSON Parsing Error ---")
            print("Error: \(error)")
            print("Localized Description: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                print("Decoding Error Details: \(decodingError)")
            }
            print("Input text: \(llmInputText)")
            print("-------------------------")
            
            await MainActor.run {
                llmError = "JSON parsing error: \(error.localizedDescription). Check console for details."
                isParsingLLM = false
            }
        }
        */
    }

    private func applyLLMParsedData(_ llmData: LLMParsedResponse) {
        // 1. Reset board, player cards, and all action arrays
        resetBoardAndPlayerCards()
        resetAllActions() // Clears preflopActions, flopActions etc. & pendingActionInput
        
        // 2. Baseline Player Setup (Hero active, others inactive, stacks set)
        setupInitialPlayers()
        
        let currentViewModelPositions = self.availablePositions // For mapping LLM pos to VM pos

        // 3. Process LLM Players: Activate them and assign cards
        if let llmPlayers = llmData.players {
            for llmPlayer in llmPlayers {
                let viewModelPosition = mapLLMPositionToViewModelPosition(llmPlayer.position, tableSize: self.tableSize, availableViewModelPositions: currentViewModelPositions)
                
                if let playerIndex = players.firstIndex(where: { $0.position == viewModelPosition }) {
                    players[playerIndex].isActive = true // Activate player specified by LLM
                    if let cardsString = llmPlayer.cards, !cardsString.isEmpty {
                        let parsedCards = parseCardString(cardsString)
                        if players[playerIndex].isHero {
                            heroCard1 = parsedCards.card1
                            heroCard2 = parsedCards.card2
                        } else {
                            players[playerIndex].card1 = parsedCards.card1
                            players[playerIndex].card2 = parsedCards.card2
                        }
                    }
                } else if viewModelPosition == heroPosition { // LLM might specify hero by actual position
                    if let heroPlayerIndex = players.firstIndex(where: { $0.isHero }) {
                        players[heroPlayerIndex].isActive = true // Ensure hero is active
                        if let cardsString = llmPlayer.cards, !cardsString.isEmpty {
                            let parsedCards = parseCardString(cardsString)
                            heroCard1 = parsedCards.card1
                            heroCard2 = parsedCards.card2
                        }
                    }
                }
            }
        }
        // Ensure Hero is marked active if not explicitly in llmPlayers but is the designated hero
        if let heroIdx = players.firstIndex(where: {$0.isHero}) { 
            players[heroIdx].isActive = true 
            // If hero cards were in llmData.players for hero's position, they are already set.
            // If not, heroCard1/2 remain as they were (nil or previously set).
        }

        // IMPORTANT: Also activate any players who appear in LLM actions but weren't in llmData.players
        // This handles cases where LLM mentions actions but doesn't list all players in the players section
        var allLLMActionPositions = Set<String>()
        
        // Collect all positions mentioned in any LLM actions
        if let preflopActions = llmData.preflop?.actions {
            for action in preflopActions {
                let mappedPosition = mapLLMPositionToViewModelPosition(action.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
                allLLMActionPositions.insert(mappedPosition)
            }
        }
        if let flopActions = llmData.flop?.actions {
            for action in flopActions {
                let mappedPosition = mapLLMPositionToViewModelPosition(action.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
                allLLMActionPositions.insert(mappedPosition)
            }
        }
        if let turnActions = llmData.turn?.actions {
            for action in turnActions {
                let mappedPosition = mapLLMPositionToViewModelPosition(action.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
                allLLMActionPositions.insert(mappedPosition)
            }
        }
        if let riverActions = llmData.river?.actions {
            for action in riverActions {
                let mappedPosition = mapLLMPositionToViewModelPosition(action.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
                allLLMActionPositions.insert(mappedPosition)
            }
        }
        
        // Activate any players who appear in actions
        for position in allLLMActionPositions {
            if let playerIndex = players.firstIndex(where: { $0.position == position }) {
                players[playerIndex].isActive = true
            }
        }

        // Debug: Print active players after LLM processing
        print("--- Active Players After LLM Processing ---")
        let activePlayers = players.filter { $0.isActive }
        print("Active players: \(activePlayers.map { "\($0.position)(\($0.isHero ? "Hero" : "Villain"))" }.joined(separator: ", "))")
        print("All LLM action positions: \(allLLMActionPositions.sorted())")
        print("-------------------------------------------")

        // 4. Apply LLM Board Cards
        if let flopCardData = llmData.flop?.cards { // This can be ["A", "K", "Q"] or ["AKQ"]
            if !flopCardData.isEmpty {
                if flopCardData.count == 1 && flopCardData[0].count > 1 && flopCardData[0].count <= 3 { // Likely a single string e.g. "AKQ" or "T72"
                    let singleStringCards = Array(flopCardData[0])
                    flopCard1 = singleStringCards.indices.contains(0) ? normalizeCard(String(singleStringCards[0])) : nil
                    flopCard2 = singleStringCards.indices.contains(1) ? normalizeCard(String(singleStringCards[1])) : nil
                    flopCard3 = singleStringCards.indices.contains(2) ? normalizeCard(String(singleStringCards[2])) : nil
                } else { // Likely an array of individual card strings/ranks e.g. ["A", "K", "Q"]
                    flopCard1 = flopCardData.indices.contains(0) ? normalizeCard(flopCardData[0]) : nil
                    flopCard2 = flopCardData.indices.contains(1) ? normalizeCard(flopCardData[1]) : nil
                    flopCard3 = flopCardData.indices.contains(2) ? normalizeCard(flopCardData[2]) : nil
                }
            }
        }
        // Assuming turn and river are single cards if present
        if let turnCardData = llmData.turn?.cards, !turnCardData.isEmpty {
            turnCard = normalizeCard(turnCardData[0])
        }
        if let riverCardData = llmData.river?.cards, !riverCardData.isEmpty {
            riverCard = normalizeCard(riverCardData[0])
        }

        // --- Action processing will continue from here in the next step ---
        // For now, just print the state after player/card setup
        print("--- After LLM Player/Card Processing ---")
        printPlayersStateForDebug()
        printBoardCardsForDebug()

        // 5. NEW PREFLOP ACTION PROCESSING: Initialize players with their actions and process in queue order
        
        // 5A. Parse LLM preflop actions and group by player
        var playerActionQueues: [String: [ActionInput]] = [:] // Actions for each player position
        
        if let rawLLMPreflopActions = llmData.preflop?.actions {
            var currentPreflopBet: Double = bigBlind // Start with big blind as the current bet
            
            // Include straddle in initial bet if present
            if hasStraddle, let straddleAmount = straddle {
                currentPreflopBet = straddleAmount
            }
            
            for llmAction in rawLLMPreflopActions {
                let viewModelPosition = mapLLMPositionToViewModelPosition(llmAction.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
                
                // Convert LLM action to ActionInput
                let normalizedActionName = normalizeActionName(llmAction.action)
                guard let actionType = PokerActionType(rawValue: normalizedActionName) else {
                    print("Unknown LLM action type: \(llmAction.action) (normalized: \(normalizedActionName))")
                    continue
                }
                
                var finalAmount: Double? = nil
                if let amountString = llmAction.amount, !amountString.isEmpty {
                    finalAmount = Double(amountString)
                }
                
                // Enhanced all-in and call calculation for preflop
                let isAllIn = llmAction.action.lowercased() == "all-in" || 
                             llmAction.action.lowercased() == "allin" || 
                             llmAction.action.lowercased() == "all in" ||
                             llmAction.action.lowercased().contains("shove") || 
                             (llmAction.amount?.lowercased().contains("all") ?? false)
                
                if let player = players.first(where: { $0.position == viewModelPosition }) {
                    // Calculate effective stack (after antes)
                    var effectiveStack = player.stack
                    if let anteAmount = self.ante, anteAmount > 0 {
                        effectiveStack -= anteAmount
                    }
                    
                    if isAllIn {
                        // For all-in actions, calculate the player's remaining stack after previous actions
                        finalAmount = calculateRemainingStack(for: viewModelPosition, upToStreet: .preflop)
                        print("Preflop all-in detected for \(viewModelPosition): remaining stack \(finalAmount ?? 0)")
                    } else if actionType == .call && (finalAmount == nil || finalAmount == 0) {
                        // For calls with no amount, calculate the call amount
                        var playerContribution: Double = 0
                        
                        // Check if player posted a blind
                        if viewModelPosition == "SB" {
                            playerContribution = smallBlind
                        } else if viewModelPosition == "BB" {
                            playerContribution = bigBlind
                        }
                        
                        finalAmount = max(0, currentPreflopBet - playerContribution)
                        print("Preflop call amount calculated for \(viewModelPosition): \(finalAmount ?? 0) (current bet: \(currentPreflopBet), player contribution: \(playerContribution))")
                    }
                }
                
                // Update current preflop bet for raises and bets
                if actionType == .bet || actionType == .raise {
                    if let amount = finalAmount {
                        currentPreflopBet = max(currentPreflopBet, amount)
                    }
                }
                
                // Set amount based on action type
                switch actionType {
                case .call, .bet, .raise:
                    finalAmount = finalAmount ?? 0.0
                case .fold, .check:
                    finalAmount = nil
                }
                
                let actionInput = ActionInput(
                    playerName: viewModelPosition,
                    actionType: actionType,
                    amount: finalAmount,
                    isSystemAction: false
                )
                
                // Add to player's action queue
                if playerActionQueues[viewModelPosition] == nil {
                    playerActionQueues[viewModelPosition] = []
                }
                playerActionQueues[viewModelPosition]?.append(actionInput)
            }
            
            // Check for missing call actions after all-ins
            // print("DEBUG: About to check for missing call actions. Raw LLM preflop actions count: \(rawLLMPreflopActions.count)")
            // for action in rawLLMPreflopActions {
            //     print("DEBUG: Raw LLM action - position: \(action.position), action: \(action.action), amount: \(action.amount ?? "nil")")
            // }
            // self.addMissingCallActionsAfterAllIn(&playerActionQueues, rawActions: rawLLMPreflopActions)
        }
        
        // 5B. Initialize all players with their appropriate actions
        let preflopOrder = getPreflopActionOrder()
        
        for position in self.availablePositions {
            if playerActionQueues[position] == nil {
                playerActionQueues[position] = []
            }
            
            let isActivePlayer = players.first(where: { $0.position == position })?.isActive ?? false
            
            // Add blinds for SB/BB (whether active or not)
            if position == "SB" {
                let blindAction = ActionInput(playerName: position, actionType: .bet, amount: smallBlind, isSystemAction: true)
                playerActionQueues[position]?.insert(blindAction, at: 0) // Insert at beginning
            } else if position == "BB" {
                let blindAction = ActionInput(playerName: position, actionType: .bet, amount: bigBlind, isSystemAction: true)
                playerActionQueues[position]?.insert(blindAction, at: 0) // Insert at beginning
            }
            
            // Add straddle if applicable
        if hasStraddle, let straddleAmount = straddle, straddleAmount > 0 {
                // UTG should always be the straddler, not the first non-blind from preflopOrder
                // (because preflopOrder removes UTG when straddle is enabled)
                if position == "UTG" && self.availablePositions.contains("UTG") {
                    let straddleAction = ActionInput(playerName: position, actionType: .bet, amount: straddleAmount, isSystemAction: true)
                    playerActionQueues[position]?.insert(straddleAction, at: 0) // Insert at beginning
                }
            }
            
            // Add fold for inactive players (except if they only have blind actions)
            if !isActivePlayer {
                let hasNonBlindActions = playerActionQueues[position]?.contains(where: { !$0.isSystemAction }) ?? false
                if !hasNonBlindActions || (playerActionQueues[position]?.count ?? 0) > 1 {
                    // Add fold action for inactive players
                    let foldAction = ActionInput(playerName: position, actionType: .fold, isSystemAction: true)
                    playerActionQueues[position]?.append(foldAction)
                }
            }
        }
        
        // 5C. Process actions in preflop order: BLINDS FIRST, then action order
        var finalPreflopActions: [ActionInput] = []
        
        // Step 1: Post blinds first (SB, BB, Straddle if any)
        let blindOrder = ["SB", "BB"] // Blinds always come first
        for position in blindOrder {
            if let actions = playerActionQueues[position], !actions.isEmpty {
                // Take only the blind action (first action which should be the blind)
                let blindAction = actions.first!
                if blindAction.isSystemAction && blindAction.actionType == .bet {
                    finalPreflopActions.append(blindAction)
                    playerActionQueues[position]?.removeFirst()
                    print("Posted blind: \(position) \(blindAction.actionType.rawValue) \(blindAction.amount ?? 0)")
                }
            }
        }
        
        // Handle straddle if present (after BB)
        if hasStraddle, let straddleAmount = straddle, straddleAmount > 0 {
            // UTG should always be the straddler, not the first non-blind from preflopOrder
            if self.availablePositions.contains("UTG") {
                if let actions = playerActionQueues["UTG"], !actions.isEmpty {
                    let straddleAction = actions.first!
                    if straddleAction.isSystemAction && straddleAction.actionType == .bet && straddleAction.amount == straddleAmount {
                        finalPreflopActions.append(straddleAction)
                        playerActionQueues["UTG"]?.removeFirst()
                        print("Posted straddle: UTG \(straddleAction.actionType.rawValue) \(straddleAction.amount ?? 0)")
                    }
                }
            }
        }
        
        // Step 2: Process remaining actions in preflop order
        var playersStillInQueue = preflopOrder.filter { (playerActionQueues[$0]?.count ?? 0) > 0 }
        
        // Debug: Print initial player action queues (after blinds posted)
        print("--- Player Action Queues After Blinds Posted ---")
        for position in self.availablePositions {
            if let actions = playerActionQueues[position], !actions.isEmpty {
                let actionStrings = actions.map { "\($0.actionType.rawValue)(\($0.amount ?? -1))" }
                print("  \(position): [\(actionStrings.joined(separator: ", "))]")
            }
        }
        print("Preflop order: \(preflopOrder)")
        print("Players in queue: \(playersStillInQueue)")
        print("-------------------------------------------")
        
        while !playersStillInQueue.isEmpty {
            var playersToRemove: [String] = []
            
            print("--- Processing round ---")
            for position in preflopOrder {
                guard playersStillInQueue.contains(position),
                      let playerActions = playerActionQueues[position],
                      !playerActions.isEmpty else { continue }
                
                // Take the first action for this player
                let nextAction = playerActions.first!
                finalPreflopActions.append(nextAction)
                print("  \(position): \(nextAction.actionType.rawValue) \(nextAction.amount ?? 0)")
                
                // Remove the action from the player's queue
                playerActionQueues[position]?.removeFirst()
                
                // If player has no more actions, remove from queue
                if playerActionQueues[position]?.isEmpty ?? true {
                    playersToRemove.append(position)
                    print("    (removed from queue)")
                }
            }
            
            // Remove players with no more actions
            for position in playersToRemove {
                playersStillInQueue.removeAll { $0 == position }
            }
            print("Players still in queue: \(playersStillInQueue)")
        }
        
        self.preflopActions = finalPreflopActions
        
        // 6. Postflop Action Construction (Simpler: order is from LLM)
        if let rawLLMFlop = llmData.flop?.actions {
            self.flopActions = convertLLMActions(rawLLMFlop, forStreet: .flop)
        }
        if let rawLLMTurn = llmData.turn?.actions {
            self.turnActions = convertLLMActions(rawLLMTurn, forStreet: .turn)
        }
        if let rawLLMRiver = llmData.river?.actions {
            self.riverActions = convertLLMActions(rawLLMRiver, forStreet: .river)
        }

        // Print actions for debugging before queue fast-forwarding
        print("--- Raw Actions after LLM processing ---")
        print("Preflop Actions: \(self.preflopActions.map { action in "[P:\(action.playerName) A:\(action.actionType.rawValue) Amt:\(action.amount ?? -1.0)]" })")
        print("Flop Actions:    \(self.flopActions.map { action in "[P:\(action.playerName) A:\(action.actionType.rawValue) Amt:\(action.amount ?? -1.0)]" })")
        print("Turn Actions:    \(self.turnActions.map { action in "[P:\(action.playerName) A:\(action.actionType.rawValue) Amt:\(action.amount ?? -1.0)]" })")
        print("River Actions:   \(self.riverActions.map { action in "[P:\(action.playerName) A:\(action.actionType.rawValue) Amt:\(action.amount ?? -1.0)]" })")

        // 7. Fast-forward Queues: Process ALL actions (blinds + LLM) into their respective queues
        //    The `getOrCreateActionQueue` with `force: true` rebuilds the queue based on current players.
        //    Then we iterate through our combined action list and feed it to the queue.

        let preflopQueue = getOrCreateActionQueue(for: .preflop, force: true)
        print("Processing \(self.preflopActions.count) preflop actions into queue...")
        for action in self.preflopActions { 
            let isBlindOrStraddle = action.isSystemAction && action.actionType == .bet && (action.playerName == "SB" || action.playerName == "BB" || (self.hasStraddle && players.first(where:{$0.position == action.playerName}) != nil))
            print("  Processing Preflop: \(action.playerName) \(action.actionType) \(action.amount ?? -1) Blind/Straddle: \(isBlindOrStraddle)")
            preflopQueue.processAction(player: action.playerName, action: action.actionType, betAmount: action.amount, isBlindOrStraddle: isBlindOrStraddle)
        }
        print("Preflop Queue after processing: \(preflopQueue.debugQueueState)")

        if !self.flopActions.isEmpty || flopCard1 != nil {
            let flopQueue = getOrCreateActionQueue(for: .flop, force: true)
            print("Processing \(self.flopActions.count) flop actions into queue...")
            for action in self.flopActions {
                 print("  Processing Flop: \(action.playerName) \(action.actionType) \(action.amount ?? -1)")
                flopQueue.processAction(player: action.playerName, action: action.actionType, betAmount: action.amount, isBlindOrStraddle: false)
            }
            print("Flop Queue after processing: \(flopQueue.debugQueueState)")
        }

        if !self.turnActions.isEmpty || turnCard != nil {
            let turnQueue = getOrCreateActionQueue(for: .turn, force: true)
            print("Processing \(self.turnActions.count) turn actions into queue...")
            for action in self.turnActions {
                print("  Processing Turn: \(action.playerName) \(action.actionType) \(action.amount ?? -1)")
                turnQueue.processAction(player: action.playerName, action: action.actionType, betAmount: action.amount, isBlindOrStraddle: false)
            }
            print("Turn Queue after processing: \(turnQueue.debugQueueState)")
        }

        if !self.riverActions.isEmpty || riverCard != nil {
            let riverQueue = getOrCreateActionQueue(for: .river, force: true)
            print("Processing \(self.riverActions.count) river actions into queue...")
            for action in self.riverActions {
                 print("  Processing River: \(action.playerName) \(action.actionType) \(action.amount ?? -1)")
                riverQueue.processAction(player: action.playerName, action: action.actionType, betAmount: action.amount, isBlindOrStraddle: false)
            }
            print("River Queue after processing: \(riverQueue.debugQueueState)")
        }
        
        // 8. Determine Current State (which street are we on now, after all LLM info?)
        if riverCard != nil || !self.riverActions.isEmpty { currentActionStreet = .river }
        else if turnCard != nil || !self.turnActions.isEmpty { currentActionStreet = .turn }
        else if flopCard1 != nil || !self.flopActions.isEmpty { currentActionStreet = .flop }
        else { currentActionStreet = .preflop } 
        print("Final currentActionStreet determined as: \(currentActionStreet)")
        
        // 9. Call determineNextPlayerAndUpdateState to set up UI for next action OR complete street/hand.
        //    This will use the fast-forwarded queues.
        determineNextPlayerAndUpdateState() 
        objectWillChange.send() 
    }

    func printPlayersStateForDebug() {
        print("Players State:")
        for player in players {
            let cards = [player.card1, player.card2].compactMap { $0 }.joined(separator: "")
            print("- Pos: \(player.position), Active: \(player.isActive), Hero: \(player.isHero), Stack: \(player.stack), Cards: \(cards.isEmpty ? "N/A" : cards)")
        }
        print("Hero cards (direct): \(heroCard1 ?? "nil") \(heroCard2 ?? "nil")")
    }

    func printBoardCardsForDebug() {
        print("Board Cards:")
        let f = [flopCard1, flopCard2, flopCard3].compactMap{$0}.joined(separator: " ")
        print("Flop: \(f.isEmpty ? "N/A" : f)")
        print("Turn: \(turnCard ?? "N/A")")
        print("River: \(riverCard ?? "N/A")")
    }

    // Modify setupInitialPlayers to set non-hero players to inactive by default.
    // ... existing code ...

    private func normalizeCard(_ cardStr: String) -> String? {
        guard !cardStr.isEmpty else { return nil }
        let ranks = "23456789TJQKA"
        let suits = "shdc" // spades, hearts, diamonds, clubs

        var rank = ""
        var suit = ""

        if cardStr.count == 1 { // e.g., "T"
            rank = String(cardStr.prefix(1)).uppercased()
            // Cannot determine suit, so we'll leave it empty.
            // This means the card selector might be needed or we assume a default/placeholder.
            // For now, return as is, UI might show "?" for suit.
            // Or, we could try to find a suit that isn't used yet.
            // For simplicity, let's return rank + a placeholder like 'x' if only rank is given.
            // However, the LLM output for board is ["T", "7", "2"]. This implies ranks only.
            // We need to assign suits. The best approach is to have the LLM return full card strings.
            // Assuming for now the LLM gives full cards for players, but ranks for board.
            // This is a tricky part. If only rank, we can't form a unique card.
            // Let's try to find an unused suit for this rank.
            let potentialSuits = ["s", "h", "d", "c"]
            let currentUsedCards = self.usedCards // Get all currently known cards
            for s_char in potentialSuits {
                let testCard = rank + s_char
                if !currentUsedCards.contains(testCard) {
                    return testCard // Found an unused suit
                }
            }
            // If all suits for this rank are somehow used (unlikely for board cards), return with a default or nil.
            return rank + "s" // Default to spades if all else fails, though this is not ideal.
        } else if cardStr.count == 2 { // e.g., "Ts"
            rank = String(cardStr.prefix(1)).uppercased()
            suit = String(cardStr.suffix(1)).lowercased()
            if ranks.contains(rank) && suits.contains(suit) {
                return rank + suit
            }
        }
        return nil // Invalid card string
    }


    private func parseCardString(_ cards: String) -> (card1: String?, card2: String?) {
        let trimmedCards = cards.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCards.isEmpty else { return (nil, nil) }

        var c1: String? = nil
        var c2: String? = nil

        // Handle cases like "AsKd", "AhQc", "T9s", "76o", "AK" (implies offsuit)
        // More robust parsing needed for "o" and "s" if LLM uses them.
        // Assuming LLM gives "JsTs" or "ATo" -> "AT"
        // "ATo" -> ATo, T is card1, o is card2? No. A is rank1, T is rank2, o is offsuit.
        // "JsTs" -> Js is card1, Ts is card2.
        
        let cardChars = Array(trimmedCards)
        
        if cardChars.count == 4 { // e.g., AsKd
            let firstCardRank = String(cardChars[0]).uppercased()
            let firstCardSuit = String(cardChars[1]).lowercased()
            let secondCardRank = String(cardChars[2]).uppercased()
            let secondCardSuit = String(cardChars[3]).lowercased()
            if isValidRank(firstCardRank) && isValidSuit(firstCardSuit) {
                c1 = firstCardRank + firstCardSuit
            }
            if isValidRank(secondCardRank) && isValidSuit(secondCardSuit) {
                c2 = secondCardRank + secondCardSuit
            }
        } else if cardChars.count == 3 { // e.g., T9s, AJo. Assume ranks + s/o
            let rank1 = String(cardChars[0]).uppercased()
            let rank2 = String(cardChars[1]).uppercased()
            let suffix = String(cardChars[2]).lowercased()

            if isValidRank(rank1) && isValidRank(rank2) {
                if suffix == "s" { // Suited
                    // Assign first available suit to both, ensuring they are the same.
                    // This is complex if other cards are known. For now, default to 's'.
                    // A better LLM output would be "Ts9s".
                    c1 = rank1 + "s"
                    c2 = rank2 + "s"
                } else if suffix == "o" { // Offsuit
                    // Assign different suits. Default to 's' and 'h'.
                    // A better LLM output would be "Ts9h".
                    c1 = rank1 + "s"
                    c2 = rank2 + "h"
                    if c1 == c2 { c2 = rank2 + "d" } // Ensure different
                } else { // Could be a single card like "Adx" or "Ad" if one card given
                    let suit = String(cardChars[2]).lowercased()
                     if isValidSuit(suit) {
                        c1 = rank1 + suit // Assume rank1 + suit, and rank2 is part of the name
                    }
                }
            }
        } else if cardChars.count == 2 { // Could be one card "As" or two ranks "AK"
             let rank1 = String(cardChars[0]).uppercased()
             let char2 = String(cardChars[1])

            if isValidRank(rank1) {
                if isValidSuit(char2.lowercased()) { // Single card, e.g., "As"
                    c1 = rank1 + char2.lowercased()
                } else if isValidRank(char2.uppercased()) { // Two ranks, e.g., "AK" (assume offsuit)
                    c1 = rank1 + "s" // Default suit 1
                    c2 = char2.uppercased() + "h" // Default suit 2
                     if c1 == c2 { c2 = char2.uppercased() + "d" } // Ensure different
                }
            }
        } else if cardChars.count == 1 && isValidRank(String(cardChars[0]).uppercased()) { // Single rank, e.g. "A"
             // Cannot determine full card.
        }


        return (normalizeCard(c1 ?? ""), normalizeCard(c2 ?? ""))
    }
    
    private func isValidRank(_ rank: String) -> Bool {
        return "23456789TJQKA".contains(rank.uppercased())
    }

    private func isValidSuit(_ suit: String) -> Bool {
        return "shdc".contains(suit.lowercased())
    }


    private func normalizeActionName(_ actionName: String) -> String {
        let lowercased = actionName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle multiple variations of action names
        switch lowercased {
        case "fold", "folds":
            return "fold"
        case "check", "checks":
            return "check"
        case "call", "calls":
            return "call"
        case "bet", "bets":
            return "bet"
        case "raise", "raises":
            return "raise"
        case "all-in", "allin", "all in", "shove", "shoves", "all in bet", "all in raise":
            return "bet" // Treat all-in as a bet for now
        default:
            return lowercased
        }
    }

    private func addMissingCallActionsAfterAllIn(_ playerActionQueues: inout [String: [ActionInput]], rawActions: [LLMActionDetail]) {
        // Debug: Print what we're checking for all-ins
        if let lastAction = rawActions.last {
            print("DEBUG: Checking last action for all-in: position=\(lastAction.position), action=\(lastAction.action), contains 'all'=\(lastAction.action.lowercased().contains("all"))")
        } else {
            print("DEBUG: No actions to check for all-in")
        }
        
        // Check if the last action is an all-in
        guard let lastAction = rawActions.last,
              (lastAction.action.lowercased() == "all-in" || 
               lastAction.action.lowercased() == "allin" || 
               lastAction.action.lowercased() == "all in" ||
               lastAction.action.lowercased().contains("shove") || 
               (lastAction.amount?.lowercased().contains("all") ?? false)) else {
            print("DEBUG: No all-in detected, returning early")
            return
        }
        
        print("DEBUG: All-in detected, proceeding with missing call logic")
        
        let lastActionPosition = mapLLMPositionToViewModelPosition(lastAction.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
        
        // Get all active players
        let activePlayers = self.players.filter { $0.isActive }
        let activePositions = Set(activePlayers.map { $0.position })
        
        // Get positions that have already acted
        let positionsWithActions = Set(rawActions.map { 
            mapLLMPositionToViewModelPosition($0.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
        })
        
        // Find active players who haven't acted yet
        let missingActors = activePositions.subtracting(positionsWithActions)
        
        print("All-in detected from \(lastActionPosition). Active positions: \(activePositions)")
        print("Positions with actions: \(positionsWithActions)")
        print("Missing actors: \(missingActors)")
        
        // If there are players who haven't acted, add a call for them
        for missingPosition in missingActors {
            // Calculate the all-in amount to call
            var allInAmount: Double = 0
            if let amountString = lastAction.amount, !amountString.isEmpty {
                allInAmount = Double(amountString) ?? 0
            } else if let player = players.first(where: { $0.position == lastActionPosition }) {
                // Calculate effective stack if amount wasn't specified
                var effectiveStack = player.stack
                if let anteAmount = self.ante, anteAmount > 0 {
                    effectiveStack -= anteAmount
                }
                allInAmount = effectiveStack
            }
            
            print("Adding missing call action for \(missingPosition) to call all-in amount: \(allInAmount)")
            
            let callAction = ActionInput(
                playerName: missingPosition,
                actionType: .call,
                amount: allInAmount,
                isSystemAction: false
            )
            
            // Add to player's action queue
            if playerActionQueues[missingPosition] == nil {
                playerActionQueues[missingPosition] = []
            }
            playerActionQueues[missingPosition]?.append(callAction)
        }
    }

    private func convertLLMActions(_ llmActions: [LLMActionDetail], forStreet street: StreetIdentifier) -> [ActionInput] {
        var convertedActions: [ActionInput] = []
        var currentStreetBet: Double = 0 // Track the current highest bet on this street
        
        for (index, llmAction) in llmActions.enumerated() {
            // Handle multiple possible action name variations
            let normalizedActionName = normalizeActionName(llmAction.action)
            guard let actionType = PokerActionType(rawValue: normalizedActionName) else {
                print("Unknown LLM action type: \(llmAction.action) (normalized: \(normalizedActionName))")
                continue
            }
            
            // Map LLM position to ViewModel's standard position name
            let viewModelPlayerPosition = mapLLMPositionToViewModelPosition(llmAction.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)

            // Determine the playerName to use in ActionInput, preferring heroPosition if player is hero.
            let playerNameForActionInput: String
            if let player = players.first(where: { $0.position == viewModelPlayerPosition }) {
                // If the LLM-specified player is the hero (matched by mapped position),
                // use the canonical heroPosition string (which might be "Hero" or the actual position string from hero picker).
                // Otherwise, use the player's standard position string.
                playerNameForActionInput = player.isHero ? self.heroPosition : player.position 
            } else if self.heroPosition == viewModelPlayerPosition { 
                // This case covers if the hero is identified by their specific position name (e.g. hero picked "BTN" and LLM says "BTN" acted)
                playerNameForActionInput = self.heroPosition
            } else {
                // Fallback if no player matches the mapped ViewModel position.
                // This might happen if LLM provides a position not in current table setup or an error in mapping.
                print("LLM Action: Could not find an active player for mapped VM position '\(viewModelPlayerPosition)' (from LLM pos '\(llmAction.position)\') for action. Using mapped position as fallback.")
                playerNameForActionInput = viewModelPlayerPosition 
            }

            // Parse amount from LLM string, handling nil and invalid strings
            var finalAmount: Double? = nil
            if let amountString = llmAction.amount, !amountString.isEmpty {
                // Handle special case where amount is literally "All-in"
                if amountString.lowercased().contains("all") {
                    finalAmount = nil // Will be calculated below as all-in
                } else {
                    finalAmount = Double(amountString)
                }
            }
            
            // Enhanced all-in and call amount calculation
            let isAllIn = llmAction.action.lowercased() == "all-in" || 
                         llmAction.action.lowercased() == "allin" || 
                         llmAction.action.lowercased() == "all in" ||
                         llmAction.action.lowercased().contains("shove") || 
                         (llmAction.amount?.lowercased().contains("all") ?? false)
            let playerPosition = mapLLMPositionToViewModelPosition(llmAction.position, tableSize: self.tableSize, availableViewModelPositions: self.availablePositions)
            
            if isAllIn {
                print("DEBUG convertLLMActions: All-in detected for action: \(llmAction.action) from position: \(llmAction.position)")
            }
            
            if let player = players.first(where: { $0.position == playerPosition }) {
                // Calculate effective stack (after antes)
                var effectiveStack = player.stack
                if let anteAmount = self.ante, anteAmount > 0 {
                    effectiveStack -= anteAmount
                }
                
                if isAllIn {
                    // For all-in actions, calculate the player's remaining stack after previous actions
                    finalAmount = calculateRemainingStack(for: playerPosition, upToStreet: street)
                    print("All-in detected for \(playerPosition): remaining stack \(finalAmount ?? 0)")
                } else if actionType == .call && convertedActions.count > 0 {
                    // Check if this is calling an all-in, regardless of LLM amount
                    let lastAction = convertedActions.last!
                    let lastLLMAction = llmActions[convertedActions.count - 1]
                    let wasLastActionAllIn = lastLLMAction.action.lowercased() == "all-in" || 
                                           lastLLMAction.action.lowercased() == "allin" || 
                                           lastLLMAction.action.lowercased() == "all in" ||
                                           lastLLMAction.action.lowercased().contains("shove") || 
                                           (lastLLMAction.amount?.lowercased().contains("all") ?? false)
                    
                    if wasLastActionAllIn && lastAction.amount != nil {
                        // Override LLM amount with actual all-in amount
                        finalAmount = lastAction.amount
                        print("DEBUG: Calling all-in, using all-in amount: \(finalAmount ?? 0) instead of LLM amount: \(llmAction.amount ?? "nil")")
                    } else if finalAmount == nil || finalAmount == 0 {
                        // Normal call calculation only if no valid amount provided
                        print("DEBUG: Normal call calculation for \(playerPosition)")
                        let callAmountNeeded = calculateNormalCallAmount(for: playerPosition, on: street, with: convertedActions)
                        finalAmount = callAmountNeeded
                        print("Call amount calculated for \(playerPosition): \(finalAmount ?? 0)")
                    }
                }
                // If LLM provided a valid amount for call/bet/raise, use it as-is (don't recalculate)
            }
            
            // Update current street bet for raises and bets
            if actionType == .bet || actionType == .raise {
                if let amount = finalAmount {
                    currentStreetBet = max(currentStreetBet, amount)
                }
            }
            
            // Set amount based on action type
            switch actionType {
            case .call, .bet, .raise:
                // For betting actions, use the calculated amount or default to 0
                finalAmount = finalAmount ?? 0.0
            case .fold, .check:
                // Folds and checks have no amount
                finalAmount = nil
            }

            let actionInput = ActionInput(
                playerName: playerNameForActionInput,
                actionType: actionType,
                amount: finalAmount,
                isSystemAction: false // LLM parsed actions are not system actions
            )
            convertedActions.append(actionInput)
            
            // Debug logging
            print("LLM Action Converted: \(llmAction.position) -> \(playerNameForActionInput), \(llmAction.action) -> \(actionType.rawValue), amount: \(llmAction.amount ?? "nil") -> \(finalAmount ?? -999)")
        }
        
        // Removed: Do not add "missing" call actions - just follow LLM exactly
        // The LLM knows who should act and who has folded
        
        return convertedActions
    }
    
    // Helper function to calculate a player's contribution this street
    private func getPlayerContributionThisStreet(_ playerPosition: String, in actions: [ActionInput]) -> Double {
        var contribution: Double = 0
        for action in actions {
            if action.playerName == playerPosition {
                switch action.actionType {
                case .bet, .raise:
                    contribution = action.amount ?? 0 // Last bet/raise amount is total contribution
                case .call:
                    contribution += action.amount ?? 0 // Calls add to contribution
                default:
                    break
                }
            }
        }
        return contribution
    }

    private func resetBoardAndPlayerCards() {
        heroCard1 = nil
        heroCard2 = nil
        flopCard1 = nil
        flopCard2 = nil
        flopCard3 = nil
        turnCard = nil
        riverCard = nil
        for i in 0..<players.count {
            players[i].card1 = nil
            players[i].card2 = nil
            // Do not reset isActive here, applyLLMParsedData will manage it.
        }
    }
    
    private func resetAllActions() {
        preflopActions.removeAll()
        flopActions.removeAll()
        turnActions.removeAll()
        riverActions.removeAll()
        pendingActionInput = nil // Reset pending action as well
    }

    // Helper function to calculate a player's remaining stack after all previous actions
    private func calculateRemainingStack(for playerPosition: String, upToStreet currentStreet: StreetIdentifier) -> Double {
        let startingStack = players.first(where: { $0.position == playerPosition })?.stack ?? 400.0
        var totalContributed: Double = 0
        
        // Add ante if applicable
        if let anteAmount = self.ante, anteAmount > 0 {
            totalContributed += anteAmount
        }
        
        // Track contributions across all streets up to current street
        let streetsToCheck: [StreetIdentifier]
        switch currentStreet {
        case .preflop:
            streetsToCheck = []
        case .flop:
            streetsToCheck = [.preflop]
        case .turn:
            streetsToCheck = [.preflop, .flop]
        case .river:
            streetsToCheck = [.preflop, .flop, .turn]
        }
        
        for street in streetsToCheck {
            let actions = actionsForStreet(street)
            
            // Find the largest single contribution this player made on this street
            var largestContributionThisStreet: Double = 0
            
            for action in actions {
                if action.playerName == playerPosition {
                    switch action.actionType {
                    case .bet, .raise:
                        // For bets/raises, this is their total contribution for the street
                        largestContributionThisStreet = action.amount ?? 0
                    case .call:
                        // For calls, we need to see what they're calling to
                        // Find the highest bet/raise before this call
                        var targetAmount: Double = 0
                        for prevAction in actions {
                            if prevAction.id == action.id { break } // Stop at this call
                            if prevAction.actionType == .bet || prevAction.actionType == .raise {
                                targetAmount = max(targetAmount, prevAction.amount ?? 0)
                            }
                        }
                        largestContributionThisStreet = targetAmount
                    default:
                        break
                    }
                }
            }
            
            totalContributed += largestContributionThisStreet
            print("DEBUG: \(playerPosition) contributed \(largestContributionThisStreet) on \(street)")
        }
        
        let remainingStack = startingStack - totalContributed
        print("DEBUG: \(playerPosition) remaining stack: \(startingStack) - \(totalContributed) = \(remainingStack)")
        return max(0, remainingStack)
    }
    
    // Helper function to calculate normal call amounts (not all-ins)
    private func calculateNormalCallAmount(for playerPosition: String, on street: StreetIdentifier, with convertedActions: [ActionInput]) -> Double {
        var currentStreetBet: Double = 0
        
        if street == .preflop {
            // On preflop, consider blinds and previous raises
            var streetPot: Double = 0
            if let anteAmount = self.ante, anteAmount > 0 {
                streetPot += anteAmount * Double(players.filter { $0.isActive }.count)
            }
            streetPot += smallBlind + bigBlind
            if hasStraddle, let straddleAmount = straddle {
                streetPot += straddleAmount
            }
            
            // Check previous actions to determine current bet level
            for prevAction in convertedActions {
                if prevAction.actionType == .bet || prevAction.actionType == .raise {
                    currentStreetBet = max(currentStreetBet, prevAction.amount ?? 0)
                }
            }
            
            return max(0, currentStreetBet - getPlayerContributionThisStreet(playerPosition, in: convertedActions))
        } else {
            // Post-flop: call the current bet
            for prevAction in convertedActions {
                if prevAction.actionType == .bet || prevAction.actionType == .raise {
                    currentStreetBet = max(currentStreetBet, prevAction.amount ?? 0)
                }
            }
            return max(0, currentStreetBet - getPlayerContributionThisStreet(playerPosition, in: convertedActions))
        }
    }
}

// Enum for effective stack type
enum EffectiveStackType: String, CaseIterable, Identifiable {
    case bigBlinds = "BB"
    case dollars = "$"
    var id: String { self.rawValue }
}

// Struct for player input in the new wizard
struct PlayerInput: Identifiable, Equatable {
    let id = UUID()
    var name: String { isHero ? "Hero" : "Villain \(position)" }
    var position: String
    var stack: Double
    var isActive: Bool
    var isHero: Bool { self.position == self.heroPositionInternal }
    var card1: String? = nil
    var card2: String? = nil

    private var heroPositionInternal: String

    init(position: String, isActive: Bool, stack: Double, heroPosition: String, card1: String? = nil, card2: String? = nil) {
        self.position = position
        self.isActive = isActive
        self.stack = stack
        self.heroPositionInternal = heroPosition
        self.card1 = card1
        self.card2 = card2
    }
    
    mutating func updateHeroPosition(_ newHeroPosition: String) {
        self.heroPositionInternal = newHeroPosition
    }

    static func == (lhs: PlayerInput, rhs: PlayerInput) -> Bool {
        lhs.id == rhs.id &&
        lhs.position == rhs.position &&
        lhs.isActive == rhs.isActive &&
        lhs.card1 == rhs.card1 &&
        lhs.card2 == rhs.card2
    }
}

// Struct for action input
struct ActionInput: Identifiable, Equatable {
    let id = UUID()
    var playerName: String // This will be the position string (e.g., "SB", "BB", "UTG")
    var actionType: PokerActionType
    var amount: Double? = nil
    var isSystemAction: Bool = false

    // Conformance to Equatable by comparing IDs
    static func == (lhs: ActionInput, rhs: ActionInput) -> Bool {
        lhs.id == rhs.id
    }
}

enum PokerActionType: String, CaseIterable, Identifiable {
    case fold = "fold" // Was "Folds"
    case check = "check" // Was "Checks"
    case bet = "bet"   // Was "Bets"
    case call = "call"  // Was "Calls"
    case raise = "raise" // Was "Raises"
    // Posts might be handled automatically or as a specific type if needed

    var id: String { self.rawValue }
}

// Helper extension for sorting (can be placed globally or in a utility file)
extension Array where Element == ActionInput {
    func sortedByPokerPosition(order: [String], tableSize: Int) -> [ActionInput] {
        // Simple sort: preserve relative order of actions for the same player,
        // then sort by player position according to `order`.
        // This doesn't handle complex re-ordering of interleaved actions perfectly for all scenarios
        // but aims to get player blocks in order.
        
        // First, get actions for blinds as they should always be at the start if present.
        var sortedActions: [ActionInput] = []
        let sbPost = self.first { $0.playerName == "SB" && $0.isSystemAction && $0.actionType == .bet }
        let bbPost = self.first { $0.playerName == "BB" && $0.isSystemAction && $0.actionType == .bet }
        
        if let sb = sbPost { sortedActions.append(sb) }
        if let bb = bbPost { sortedActions.append(bb) }
        
        // Then add other actions, sorted by the defined order for players.
        let otherActions = self.filter { !($0.isSystemAction && ($0.playerName == "SB" || $0.playerName == "BB") && $0.actionType == .bet) }
        
        sortedActions.append(contentsOf: otherActions.sorted {
            guard let index1 = order.firstIndex(of: $0.playerName), 
                  let index2 = order.firstIndex(of: $1.playerName) else {
                return false // Should not happen if playerName is always a valid position
            }
            if index1 != index2 {
                return index1 < index2
            }
            // If same player, preserve original order (implicit in stable sort, but good to be mindful)
            // For this basic sort, if player indices are same, it means it's the same player, rely on stability.
            return false // Keep original relative order for same player, effectively
        })
        return sortedActions
    }
} 
