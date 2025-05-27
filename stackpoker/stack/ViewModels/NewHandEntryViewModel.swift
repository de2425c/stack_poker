import Foundation
import Combine
import SwiftUI

class NewHandEntryViewModel: ObservableObject {
    // Session ID for associating the hand
    let sessionId: String?

    // Stakes
    @Published var smallBlind: Double = 1.0
    @Published var bigBlind: Double = 2.0
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
    @Published var effectiveStackType: EffectiveStackType = .bigBlinds
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

    init(sessionId: String? = nil) { // Add sessionId to init, default to nil
        self.sessionId = sessionId // Store sessionId

        if !availablePositions.contains(heroPosition) {
            heroPosition = availablePositions.first ?? "BTN"
        }
        setupInitialPlayers()
        // Post blinds after initialization to avoid re-entrancy issues during init
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.updatePreflopStateAndFirstActor()
        }
    }

    func setupInitialPlayers() {

        let currentHeroPos = self.heroPosition
        players = availablePositions.map {
            PlayerInput(position: $0, 
                        isActive: $0 == currentHeroPos, // Initially only hero is active
                        stack: effectiveStackType == .bigBlinds ? effectiveStackAmount * bigBlind : effectiveStackAmount, 
                        heroPosition: currentHeroPos)
        }
        
        // Print active player information
        let activePlayers = players.filter { $0.isActive }

        for player in activePlayers {

        }
        
        if !players.contains(where: { $0.isHero }) {
            if !players.isEmpty {
                self.heroPosition = players[0].position 
                players[0].isActive = true
                for i in 0..<players.count { players[i].updateHeroPosition(self.heroPosition) }
            }
        }
        updatePlayerStacksBasedOnEffectiveStack()
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
    private func determineNextPlayerAndUpdateState() {

        
        if currentActionStreet == .preflop && preflopActions.isEmpty && !isPostingBlinds {

            postBlinds()
            return // postBlinds will trigger this function again
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
    
    // Fix getPreflopActionOrder to ensure SB acts first
    private func getPreflopActionOrder() -> [String] {
        // Preflop action order is: UTG, MP, CO, BTN, SB, BB
        // For auto-adds (i.e. SB and BB blind posts), we handle those separately in postBlinds()
        // This method returns the order of positions who need to act after blinds
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
        
        // Then add SB, BB
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
        
        // Preflop
        runningPot += preflopActions.reduce(0) { $0 + ($1.amount ?? 0) }
        currentPotPreflop = runningPot
        
        // Flop
        runningPot += flopActions.reduce(0) { $0 + ($1.amount ?? 0) }
        currentPotFlop = runningPot
        
        // Turn
        runningPot += turnActions.reduce(0) { $0 + ($1.amount ?? 0) }
        currentPotTurn = runningPot
        
        // River
        runningPot += riverActions.reduce(0) { $0 + ($1.amount ?? 0) }
        currentPotRiver = runningPot
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
            let player = Player(
                name: pInput.name,
                seat: seatCounter, // Assign seat based on order in `players` array
                stack: pInput.stack, // Initial stack
                position: pInput.position,
                isHero: pInput.isHero,
                cards: pInput.isHero ? [heroCard1, heroCard2].compactMap { $0 } : nil, // Only hero cards for now
                finalHand: nil, // To be determined by evaluator or post-processing
                finalCards: nil // To be determined by evaluator or post-processing
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

        // Flop
        let flopCards = [flopCard1, flopCard2, flopCard3].compactMap { $0 }
        if !flopCards.isEmpty || !flopActions.isEmpty {
            let flopMappedActions = mapActionInputsToActions(flopActions)
            streets.append(Street(name: "flop", cards: flopCards.count == 3 ? flopCards : [], actions: flopMappedActions))
        }

        // Turn (only if Flop has cards)
        if !flopCards.isEmpty, (turnCard != nil || !turnActions.isEmpty) {
            let turnMappedActions = mapActionInputsToActions(turnActions)
            streets.append(Street(name: "turn", cards: [turnCard].compactMap { $0 }, actions: turnMappedActions))
        }

        // River (only if Turn has cards)
        if turnCard != nil, (riverCard != nil || !riverActions.isEmpty) {
            let riverMappedActions = mapActionInputsToActions(riverActions)
            streets.append(Street(name: "river", cards: [riverCard].compactMap { $0 }, actions: riverMappedActions))
        }
        return streets
    }
    
    private func mapActionInputsToActions(_ inputs: [ActionInput]) -> [Action] {
        return inputs.map { input in
            // Find the player name from the `players` array based on position string
            let playerName = players.first { $0.position == input.playerName }?.name ?? input.playerName
            return Action(playerName: playerName, action: input.actionType.rawValue, amount: input.amount ?? 0, cards: nil)
        }
    }
    
    // Placeholder for pot calculation logic
    private func calculatePotAndDistribution(players: [Player], streets: [Street]) -> (potAmount: Double, heroPnl: Double, distribution: [PotDistribution]?) {
        // This is a very simplified version. Real pot/PnL requires detailed action processing.
        var totalPot: Double = 0
        var contributions: [String: Double] = [:] // PlayerName: Amount

        for street in streets {
            for action in street.actions {
                totalPot += action.amount // Assumes amount is net contribution for bets/raises/calls
                contributions[action.playerName, default: 0] += action.amount
            }
        }
        
        // Simplified PnL: if hero is only one left or wins at showdown (not implemented here)
        // For now, just return 0 PnL and no distribution
        // A more complex version would use PokerCalculator.calculateHandHistoryPnL
        let hero = players.first(where: { $0.isHero })
        let heroContribution = hero != nil ? contributions[hero!.name, default: 0] : 0
        
        // Basic win condition: if hero is the only one not folded by the end of all actions
        var activePlayerNames = Set(players.map { $0.name })
        for street in streets {
            for action in street.actions {
                if action.action.lowercased() == "folds" {
                    activePlayerNames.remove(action.playerName)
                }
            }
        }
        
        var calculatedHeroPnl = -heroContribution // Starts by losing what was put in
        var finalDistribution: [PotDistribution]? = nil

        if let heroName = hero?.name, activePlayerNames.contains(heroName) {
            if activePlayerNames.count == 1 { // Hero is the only one left
                calculatedHeroPnl = totalPot - heroContribution
                finalDistribution = [PotDistribution(playerName: heroName, amount: totalPot, hand: "Winner by fold", cards: hero?.cards ?? [])]
            } else {
                // Showdown scenario - for now, assume hero loses if other active players
                // This needs full hand evaluation to be correct.
                // If a simple showdown is assumed and hero wins (e.g. user indicates manually)
                // calculatedHeroPnl = totalPot - heroContribution;
                // For now, leave as loss if not sole winner by fold.
            }
        }
        // If PNL calculation makes pot negative, PNL is just -contribution.
        if calculatedHeroPnl + heroContribution < 0 {
            calculatedHeroPnl = -heroContribution
        }

        return (totalPot, calculatedHeroPnl, finalDistribution)
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
    case fold = "Folds"
    case check = "Checks"
    case bet = "Bets"
    case call = "Calls"
    case raise = "Raises"
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
