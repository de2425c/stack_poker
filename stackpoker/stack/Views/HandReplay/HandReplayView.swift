import SwiftUI
import Foundation
import FirebaseAuth

struct Card: Identifiable {
    let id = UUID()
    let rank: String
    let suit: String
    
    var description: String {
        return rank + suit
    }
    
    // Parse a card string like "Ah" or "Td"
    init(from string: String) {
        self.rank = String(string.prefix(1))
        self.suit = String(string.suffix(1))
    }
}

struct HandReplayView: View {
    let hand: ParsedHandHistory
    let userId: String
    @Environment(\.dismiss) var dismiss
    @State private var currentStreetIndex = 0
    @State private var currentActionIndex = 0
    @State private var isPlaying = false
    @State private var potAmount: Double = 0
    @State private var playerStacks: [String: Double] = [:]
    @State private var foldedPlayers: Set<String> = []
    @State private var isHandComplete = false
    @State private var playerBets: [String: Double] = [:]
    @State private var showdownRevealed = false
    @State private var winningPlayers: Set<String> = []
    @State private var showPotDistribution = false
    @State private var lastCheckPlayer: String? = nil
    @State private var showCheckAnimation: Bool = false
    @State private var showingShareSheet = false
    @State private var showingShareAlert = false
    @State private var isShowdownComplete = false
    @State private var highestBetOnStreet: Double = 0
    @State private var showWinnerPopup = false
    @State private var winnerName = ""
    @State private var winningHand = ""
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    
    // Use standard card size for all cards with proper aspect ratio
    private let cardAspectRatio: CGFloat = 0.69 // Standard playing card ratio (width to height)
    let cardWidth: CGFloat = 36
    var cardHeight: CGFloat { return cardWidth / cardAspectRatio }
    
    private var hasMoreActions: Bool {
        guard currentStreetIndex < hand.raw.streets.count else { return false }
        let currentStreet = hand.raw.streets[currentStreetIndex]
        return currentActionIndex < currentStreet.actions.count || currentStreetIndex + 1 < hand.raw.streets.count
    }
    
    // This ensures we accumulate all community cards as the hand progresses
    private var allCommunityCards: [String] {
        var cards: [String] = []
        for i in 0...min(currentStreetIndex, hand.raw.streets.count - 1) {
            cards.append(contentsOf: hand.raw.streets[i].cards)
        }
        return cards
    }
    
    private var isShowdown: Bool {
        guard currentStreetIndex == hand.raw.streets.count - 1 else { return false }
        let currentStreet = hand.raw.streets[currentStreetIndex]
        return currentActionIndex >= currentStreet.actions.count
    }
    
    // New property to track if we need one final click for showdown
    private var needsShowdownClick: Bool {
        isHandComplete && !isShowdownComplete && (hand.raw.showdown ?? false)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView(edges: .all)
                
                VStack(spacing: 0) {
                    // Back and share buttons at the top
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 16)
                        .padding(.top, 8)
                        Spacer()
                        Button(action: { showingShareAlert = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 10)
                    
                    Spacer() // Flexible spacer above the table
                    
                    // Poker Table
                    ZStack {
                        // Table background
                        Ellipse()
                            .fill(Color(red: 53/255, green: 128/255, blue: 73/255))
                            .overlay(
                                Ellipse()
                                    .stroke(Color(red: 91/255, green: 70/255, blue: 43/255), lineWidth: 10)
                            )
                            .frame(width: geometry.size.width * 0.93, height: geometry.size.height * 0.78)
                            .shadow(color: .black.opacity(0.6), radius: 15)
                        
                        // Inner table accent 
                        Ellipse()
                            .stroke(Color.black.opacity(0.2), lineWidth: 2)
                            .frame(width: geometry.size.width * 0.80, height: geometry.size.height * 0.65)
                        
                        // Stack Logo - positioned above pot
                        Text("STACK")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(0.3)
                            .offset(y: -geometry.size.height * 0.14)
                            .shadow(color: .black.opacity(0.5), radius: 2)

                        // Pot display - centered at middle of table
                        if potAmount > 0 {
                            ChipView(amount: potAmount)
                                .scaleEffect(1.2)
                                .transition(.scale.combined(with: .opacity))
                                .animation(.spring(response: 0.4), value: potAmount)
                                .offset(y: geometry.size.height * -0.08)
                        }

                        // Community Cards - positioned closer to hero
                        CommunityCardsView(cards: allCommunityCards)
                            .offset(y: geometry.size.height * 0.0)
                            .scaleEffect(1.15)

                        // Player Seats
                        ForEach(hand.raw.players, id: \.seat) { player in
                            PlayerSeatView(
                                player: player,
                                isFolded: foldedPlayers.contains(player.name),
                                isHero: player.isHero,
                                stack: playerStacks[player.name] ?? player.stack,
                                geometry: geometry,
                                allPlayers: hand.raw.players,
                                betAmount: playerBets[player.name],
                                showdownRevealed: showdownRevealed,
                                isWinner: winningPlayers.contains(player.name),
                                showPotDistribution: showPotDistribution,
                                showCheck: showCheckAnimation && lastCheckPlayer == player.name,
                                isPlayingHand: isPlaying,
                                isHandComplete: isHandComplete,
                                isShowdownComplete: isShowdownComplete
                            )
                        }
                        
                        // Winner Popup - shows who won the hand
                        if showWinnerPopup {
                            VStack(spacing: 10) {
                                Text(winnerName + " Wins!")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                if !winningHand.isEmpty {
                                    Text("with " + winningHand)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.yellow)
                                }
                                
                                Button("OK") {
                                    withAnimation {
                                        showWinnerPopup = false
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .padding(.top, 10)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.black.opacity(0.9))
                                    .shadow(color: .black.opacity(0.5), radius: 10)
                            )
                            .padding(40)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(100)
                        }
                    }
                    // No explicit offset needed here if PlayerSeatView positions correctly within the ZStack boundaries.
                    // The overall ZStack is now influenced by the flexible Spacers around it.
                    
                    Spacer() // Flexible spacer below the table
                    
                    // Controls at the bottom
                    HStack(spacing: 20) {
                        Button(action: startReplay) {
                            Text(isPlaying ? "Reset" : "Start")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 100, height: 36)
                                .background(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .cornerRadius(18)
                        }
                        
                        Button(action: nextAction) {
                            Text(needsShowdownClick ? "Show Cards" : "Next")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 100, height: 36)
                                .background(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .opacity(isPlaying && (hasMoreActions || needsShowdownClick) ? 1 : 0.5)
                                .cornerRadius(18)
                        }
                        .disabled(!isPlaying || (!hasMoreActions && !needsShowdownClick))
                    }
                    .padding(.vertical, 25)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.black.opacity(0)
                    )
                }
            }
        }
        .onAppear {
            initializeStacks()
        }
        .alert("Share Hand", isPresented: $showingShareAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Share to Feed") {
                showingShareSheet = true
            }
        } message: {
            Text("Would you like to share this hand to your feed?")
        }
        .sheet(isPresented: $showingShareSheet) {
            PostEditorView(userId: userId, initialHand: hand)
                .environmentObject(postService)
                .environmentObject(userService)
                .environmentObject(HandStore(userId: userId))
        }
    }
    
    private func initializeStacks() {
        // Initialize player stacks
        hand.raw.players.forEach { player in
            playerStacks[player.name] = player.stack
        }
        
        // Print info about cards for debugging
        hand.raw.players.forEach { player in
            if player.cards != nil && !player.cards!.isEmpty {

            }
            if player.finalCards != nil && !player.finalCards!.isEmpty {

            }
        }
        
        // Ensure the dealer button is set - set it manually
        // This is especially important for players who should have the BTN position
        for player in hand.raw.players {
            if player.position == "BTN" {
                // Make sure the player with BTN position is marked as the dealer

            }
        }
        
        // Check showdown flag to ensure it's properly set
        if let showdown = hand.raw.showdown {

            if showdown {
                // If hand has showdown, ensure we have proper data for card reveal
                let playersWithCards = hand.raw.players.filter { $0.cards != nil && !$0.cards!.isEmpty }
                if playersWithCards.count <= 1 {

                }
            }
        } else {

        }
        
        // Log pot distribution for debugging
        if let distribution = hand.raw.pot.distribution {

        } else {

        }
    }
    
    private func startReplay() {
        // Reset all state
        currentStreetIndex = 0
        currentActionIndex = 0
        isPlaying = true
        isHandComplete = false
        potAmount = 0
        foldedPlayers.removeAll()
        playerBets.removeAll()
        winningPlayers.removeAll()
        showPotDistribution = false
        lastCheckPlayer = nil
        showCheckAnimation = false
        highestBetOnStreet = 0
        showdownRevealed = false
        isShowdownComplete = false
        showWinnerPopup = false
        

        
        // Initialize player stacks to their starting values
        initializeStacks()
    }
    
    private func nextAction() {
        // If hand is complete but we need one more click for showdown, handle that
        if isHandComplete && !isShowdownComplete && (hand.raw.showdown ?? false) {

            withAnimation(.easeInOut(duration: 0.5)) {
                showdownRevealed = true
                isShowdownComplete = true
                
                // Show winner popup after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showWinnerAnnouncement()
                }
            }
            return
        }
        
        // Otherwise, if hand is complete, do nothing
        guard !isHandComplete else { return }
        
        if currentStreetIndex < hand.raw.streets.count {
            let currentStreet = hand.raw.streets[currentStreetIndex]
            
            if currentActionIndex < currentStreet.actions.count {
                let action = currentStreet.actions[currentActionIndex]
                
                // Check animation handling
                if action.action.lowercased() == "checks" {
                    lastCheckPlayer = action.playerName
                    showCheckAnimation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showCheckAnimation = false
                        }
                    }
                } else {
                    lastCheckPlayer = nil
                    showCheckAnimation = false
                }
                
                // Process the current action
                processAction(action)
                
                // Check if this is the LAST action of the LAST street (especially river)
                let isLastAction = currentActionIndex == currentStreet.actions.count - 1 
                let isLastStreet = currentStreetIndex == hand.raw.streets.count - 1
                
                // If this is the last action of the last street AND showdown is true, reveal cards immediately
                if isLastAction && isLastStreet && (hand.raw.showdown ?? false) {

                    withAnimation(.easeInOut(duration: 0.5)) {
                        showdownRevealed = true
                        isShowdownComplete = true
                        
                        // Show winner popup after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            showWinnerAnnouncement()
                        }
                    }
                }
                
                currentActionIndex += 1
            } else if currentStreetIndex + 1 < hand.raw.streets.count {
                // Move to the next street
                currentStreetIndex += 1
                currentActionIndex = 0
                playerBets.removeAll() // Clear bet displays for the new street
                highestBetOnStreet = 0 // Reset highest bet for the new street
            } else {
                // No more actions or streets - time for showdown
                handleShowdown()
            }
        }
    }
    
    // New function to show winner announcement
    private func showWinnerAnnouncement() {
        withAnimation(.spring()) {
            // Determine winner name and hand
            if let distribution = hand.raw.pot.distribution, !distribution.isEmpty {
                // Find winner with highest amount
                let sortedWinners = distribution.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
                
                if let winner = sortedWinners.first {
                    winnerName = winner.playerName
                    
                    // Use the HandEvaluator to get a better description of winning hand when available
                    if let winnerCards = hand.raw.players.first(where: { $0.name == winner.playerName })?.finalCards {
                        let communityCards = getCommunityCards()
                        if !winnerCards.isEmpty && !communityCards.isEmpty {
                            // Combine player cards with community cards for best hand evaluation
                            let allCards = winnerCards + communityCards
                            // Use HandEvaluator to get proper hand description
                            winningHand = HandEvaluator.getHandDescription(cards: allCards)
                        } else {
                            winningHand = winner.hand
                        }
                    } else {
                        winningHand = winner.hand
                    }
                    
                    showWinnerPopup = true
                    
                    // Auto-dismiss after a few seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            showWinnerPopup = false
                        }
                    }
                    return
                }
            }
            
            // Fallback if no distribution data - Calculate best hand using HandEvaluator
            let activePlayers = hand.raw.players.filter { !foldedPlayers.contains($0.name) }
            let communityCards = getCommunityCards()
            
            if !activePlayers.isEmpty && !communityCards.isEmpty {
                var playerHands: [(playerName: String, cards: [String])] = []
                
                for player in activePlayers {
                    if let playerCards = player.finalCards ?? player.cards, !playerCards.isEmpty {
                        // Combine player's hole cards with community cards
                        let allCards = playerCards + communityCards
                        playerHands.append((player.name, allCards))
                    }
                }
                
                if !playerHands.isEmpty {
                    // Determine winner using HandEvaluator
                    let results = HandEvaluator.determineWinner(hands: playerHands)
                    let winners = results.filter { $0.winner }
                    
                    if let winner = winners.first {
                        winnerName = winner.playerName
                        winningHand = winner.handDescription
                        showWinnerPopup = true
                        
                        // Auto-dismiss after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showWinnerPopup = false
                            }
                        }
                        return
                    }
                }
            }
            
            // Last resort fallback if hand evaluation fails
            let heroPlayer = hand.raw.players.first { $0.isHero }
            
            if let hero = heroPlayer {
                let heroPnl = hand.accurateHeroPnL
                if heroPnl > 0 {
                    winnerName = hero.name
                    winningHand = hero.finalHand ?? "winning hand"
                } else {
                    // Villain(s) won - make all non-hero active players winners
                    winningPlayers = Set(activePlayers.filter { !$0.isHero }.map { $0.name })

                }
                showWinnerPopup = true
                
                // Auto-dismiss after a few seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation {
                        showWinnerPopup = false
                    }
                }
            }
        }
    }
    
    // Helper function to get all community cards
    private func getCommunityCards() -> [String] {
        return hand.raw.streets.flatMap { $0.cards }
    }
    
    private func processAction(_ action: Action) {
        // Ensure player exists in stacks; handle error if not
        guard let stack = playerStacks[action.playerName] else {

            // Consider how to handle this - skip action, show error?
            return
        }
        // Get amount player has already put in on this street (from playerBets)
        let investedThisStreet = playerBets[action.playerName] ?? 0

        switch action.action.lowercased() {
        case "folds":
            foldedPlayers.insert(action.playerName)
            playerBets[action.playerName] = nil // Remove bet display

        case "checks":
            // No changes needed for stacks or pot
            // Animation is handled in nextAction before calling this
            break // Explicit break

        case "bets":
            let betAmountTotal = action.amount // Amount is the total bet size (e.g., bet $10)
            let amountToAdd = max(0, betAmountTotal - investedThisStreet) // Actual new money going in
            playerStacks[action.playerName] = stack - amountToAdd
            potAmount += amountToAdd
            playerBets[action.playerName] = betAmountTotal // Update total displayed bet for this street
            highestBetOnStreet = max(highestBetOnStreet, betAmountTotal) // Update highest bet

        case "calls":
            // Calculate amount needed to call the current highest bet
            let callAmount = max(0, highestBetOnStreet - investedThisStreet)
            playerStacks[action.playerName] = stack - callAmount
            potAmount += callAmount
            // Player has now matched the highest bet for the street
            playerBets[action.playerName] = highestBetOnStreet

        case "raises":
            let raiseAmountTotal = action.amount // Amount is the total size of the raise (e.g., raise to $30)
            let amountToAdd = max(0, raiseAmountTotal - investedThisStreet) // Actual new money going in
            playerStacks[action.playerName] = stack - amountToAdd
            potAmount += amountToAdd
            playerBets[action.playerName] = raiseAmountTotal // Update total displayed bet for this street
            highestBetOnStreet = max(highestBetOnStreet, raiseAmountTotal) // Update highest bet

        case "posts small blind", "posts big blind", "posts":
            // Treat blinds and posts similar to a bet in terms of stack/pot changes
            let postAmount = action.amount
            playerStacks[action.playerName] = stack - postAmount
            potAmount += postAmount
            playerBets[action.playerName] = postAmount // Display the post amount as a bet
            highestBetOnStreet = max(highestBetOnStreet, postAmount) // Posts set the bet level

        // Handle other potential actions if they exist in your hand history format
        // (e.g., "all-in", "shows", "mucks")
        default:
            print("")
            // If an action involves an amount (like maybe an uncategorized "bets"),
            // you might need a fallback, but explicit handling is better.
            // Example: if action.amount > 0 { /* handle generic bet? */ }
        }
    }
    
    private func handleShowdown() {

        
        // First, log the showdown status to help with debugging
        if let showdown = hand.raw.showdown {

        } else {

        }
        
        // Priority #1: Always respect the explicit showdown flag if it exists
        if let showdownFlag = hand.raw.showdown {
            if showdownFlag {

                withAnimation(.easeInOut(duration: 0.5)) {
                    showdownRevealed = true
                    isShowdownComplete = true
                    
                    // Show winner popup after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showWinnerAnnouncement()
                    }
                }
                
                // Proceed with distributing the pot
                handlePotDistribution()
                return
            } else {
                // Explicit showdown=false - no showdown should happen

                withAnimation(.easeInOut(duration: 0.5)) {
                    showdownRevealed = false
                    isShowdownComplete = false
                    
                    // Handle pot distribution without showing cards
                    handlePotDistribution()
                }
                return
            }
        }
        
        // Priority #2: If no explicit flag, check if multiple players are active with cards
        let activePlayers = hand.raw.players.filter { !foldedPlayers.contains($0.name) }
        let activePlayerCount = activePlayers.count
        
        if activePlayerCount > 1 {
            // Check if multiple players have cards (implying showdown)
            let playersWithCards = activePlayers.filter { 
                ($0.cards != nil && $0.cards!.count >= 2) || 
                ($0.finalCards != nil && $0.finalCards!.count >= 2) 
            }
            
            if playersWithCards.count >= 2 {

                withAnimation(.easeInOut(duration: 0.5)) {
                    showdownRevealed = true
                    isShowdownComplete = true
                    
                    // Show winner popup after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showWinnerAnnouncement()
                    }
                }
                
                // Proceed with distributing the pot
                handlePotDistribution()
                return
            }
        }
        
        // Priority #3: If only one player is active, they win without showdown
        if activePlayerCount == 1 {

            withAnimation(.easeInOut(duration: 0.5)) {
                showdownRevealed = false
                isShowdownComplete = true
                
                // Handle pot distribution without showing cards
                handlePotDistribution()
            }
            return
        }
        
        // Fallback: No clear showdown condition

        withAnimation(.easeInOut(duration: 0.5)) {
            showdownRevealed = false
            isShowdownComplete = true
            
            // Still distribute the pot even with no showdown
            handlePotDistribution()
        }
    }
    
    // Add a separate function for pot distribution logic
    private func handlePotDistribution() {
        // Determine winners based on pot distribution or defaults
        if let distribution = hand.raw.pot.distribution {
            // Use explicit pot distribution from hand history
            winningPlayers = Set(distribution.filter { $0.amount > 0 }.map { $0.playerName })
            

            
            // Log final hand rankings for all winners
            for winner in distribution.filter({ $0.amount > 0 }) {

            }
            
            // Animate pot distribution after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showPotDistribution = true
                    
                    // Update player stacks with winnings
                    for potDist in distribution {
                        if let currentStack = self.playerStacks[potDist.playerName] {
                            self.playerStacks[potDist.playerName] = currentStack + potDist.amount

                        }
                    }
                    self.potAmount = 0
                }
            }
        } else {
            // No distribution data, fallback to simple determination

            
            // If only one player is active (everyone else folded), they win
            let activePlayers = hand.raw.players.filter { !foldedPlayers.contains($0.name) }
            
            if activePlayers.count == 1 {
                // Single player wins the pot
                let winner = activePlayers.first!
                winningPlayers = [winner.name]
                

                
                // Animate winner getting pot
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        showPotDistribution = true
                        
                        // Update winner stack
                        if let currentStack = self.playerStacks[winner.name] {
                            self.playerStacks[winner.name] = currentStack + self.potAmount

                        }
                        self.potAmount = 0
                    }
                }
            } else if showdownRevealed {
                // Try to determine winner based on Hero PnL
                let heroPlayer = hand.raw.players.first { $0.isHero }
                
                if let hero = heroPlayer {
                    let heroPnl = hand.accurateHeroPnL
                    if heroPnl > 0 {
                        // Hero won
                        winningPlayers = [hero.name]

                    } else {
                        // Villain(s) won - make all non-hero active players winners
                        winningPlayers = Set(activePlayers.filter { !$0.isHero }.map { $0.name })

                    }
                    
                    // Distribute pot (simplified)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            showPotDistribution = true
                            
                            if heroPnl > 0 {
                                // Hero gets the pot
                                if let currentStack = self.playerStacks[hero.name] {
                                    self.playerStacks[hero.name] = currentStack + self.potAmount
                                }
                            } else {
                                // Split pot among villains (or just one villain gets it)
                                let villains = activePlayers.filter { !$0.isHero }
                                if !villains.isEmpty {
                                    let splitAmount = self.potAmount / Double(villains.count)
                                    
                                    for villain in villains {
                                        if let currentStack = self.playerStacks[villain.name] {
                                            self.playerStacks[villain.name] = currentStack + splitAmount
                                        }
                                    }
                                }
                            }
                            
                            self.potAmount = 0
                        }
                    }
                } else {
                    distributeToAllActivePlayers(activePlayers)
                }
            } else {
                distributeToAllActivePlayers(activePlayers)
            }
        }
        
        isHandComplete = true
    }
    
    // Helper function to distribute pot to all active players
    private func distributeToAllActivePlayers(_ activePlayers: [Player]) {
        // Can't determine winner, distribute evenly

        
        winningPlayers = Set(activePlayers.map { $0.name })
        
        // Split pot equally
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showPotDistribution = true
                
                if !activePlayers.isEmpty {
                    let splitAmount = self.potAmount / Double(activePlayers.count)
                    
                    for player in activePlayers {
                        if let currentStack = self.playerStacks[player.name] {
                            self.playerStacks[player.name] = currentStack + splitAmount
                        }
                    }
                }
                
                self.potAmount = 0
            }
        }
    }
}

struct CommunityCardsView: View {
    let cards: [String]
    
    var body: some View {
        let cardWidth: CGFloat = 36
        let cardHeight: CGFloat = 52
        VStack(spacing: 4) {
            // Flop, Turn, River label
            Text(getStreetLabel())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 3)
                .shadow(color: .black.opacity(0.5), radius: 1)
            
            // All cards in one row with better spacing and shadow
            HStack(spacing: 6) {
                ForEach(0..<5) { idx in
                    if idx < cards.count {
                        CardView(card: Card(from: cards[idx]))
                            .aspectRatio(0.69, contentMode: .fit)
                            .frame(width: cardWidth, height: cardHeight)
                            .shadow(color: .black.opacity(0.5), radius: 1.5)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: cards.count)
                    } else {
                        // Empty placeholder - more visible
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.gray.opacity(0.15))
                            .aspectRatio(0.69, contentMode: .fit)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
    
    // Get label for current street
    private func getStreetLabel() -> String {
        switch cards.count {
        case 0: return "Pre-Flop"
        case 3: return "Flop"
        case 4: return "Turn"
        case 5: return "River"
        default: return ""
        }
    }
}

struct CardView: View {
    let card: Card
    
    // Get color based on suit
    private var cardBackgroundColor: Color {
        switch card.suit.lowercased() {
        case "s": return Color(red: 0.1, green: 0.2, blue: 0.5) // Spades - dark blue
        case "h": return Color(red: 0.5, green: 0.1, blue: 0.1) // Hearts - dark red
        case "d": return Color(red: 0.1, green: 0.4, blue: 0.6) // Diamonds - medium blue
        case "c": return Color(red: 0.1, green: 0.3, blue: 0.2) // Clubs - dark green
        default: return Color(red: 0.1, green: 0.25, blue: 0.5) // Default blue
        }
    }
    
    private var suitColor: Color {
        card.suit.lowercased() == "h" || card.suit.lowercased() == "d" ? .red : .white
    }
    
    var body: some View {
        ZStack {
            // Card background - color based on suit
            RoundedRectangle(cornerRadius: 5)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.black.opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 1)
            
            // Card content - simplified design matching image
            VStack {
                // Top left - rank and suit
                HStack {
                    VStack(alignment: .leading, spacing: -2) {
                        Text(formatRank(card.rank))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(suitSymbol(for: card.suit))
                            .font(.system(size: 14))
                            .foregroundColor(suitColor)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2)
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
    }
    
    private func suitSymbol(for suit: String) -> String {
        switch suit.lowercased() {
        case "h": return "♥"
        case "d": return "♦"
        case "c": return "♣"
        case "s": return "♠"
        default: return suit
        }
    }
    
    // Format card ranks for better display
    private func formatRank(_ rank: String) -> String {
        switch rank {
        case "T": return "10"
        default: return rank
        }
    }
}


struct PlayerSeatView: View {
    let player: Player
    let isFolded: Bool
    let isHero: Bool
    let stack: Double
    let geometry: GeometryProxy
    let allPlayers: [Player]
    let betAmount: Double?
    let showdownRevealed: Bool
    let isWinner: Bool
    let showPotDistribution: Bool
    let showCheck: Bool
    let isPlayingHand: Bool
    let isHandComplete: Bool
    let isShowdownComplete: Bool
    
    @State private var showCards: Bool = true
    
    var displayName: String {
        isHero ? "Hero" : (player.position ?? "")
    }
    
    // Check if this player is on the button (BTN position)
    private var isOnButton: Bool {
        return player.position == "BTN"
    }
    
    private let positionOrder6Max = ["SB", "BB", "UTG", "MP", "CO", "BTN"]
    private let positionOrder9Max = ["SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "HJ", "CO", "BTN"]
    private let positionOrder2Max = ["SB", "BB"]

    private func getPosition() -> CGPoint {
        let width = geometry.size.width
        let height = geometry.size.height
        let centerX = width * 0.5
        let centerY = height * 0.4  // Table center

        // 1. Find the hero and their position
        guard let heroPlayer = allPlayers.first(where: { $0.isHero }) else {
            // Fallback position if no hero is found
            return CGPoint(x: centerX, y: centerY)
        }
        
        guard let heroPosition = heroPlayer.position else {
            // Fallback if hero has no position
            return CGPoint(x: centerX, y: centerY)
        }
        
        // 2. Set up position orders for different table sizes
        let positionOrder2Max = ["SB", "BB"]
        let positionOrder6Max = ["SB", "BB", "UTG", "MP", "CO", "BTN"]
        let positionOrder9Max = ["SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "HJ", "CO", "BTN"]
        
        // 3. Determine the appropriate order based on table size
        let positionOrder: [String]
        let tableSize = allPlayers.count
        
        switch tableSize {
        case 2:
            positionOrder = positionOrder2Max
        case 3...6:
            positionOrder = positionOrder6Max
        case 7...9:
            positionOrder = positionOrder9Max
        default:
            positionOrder = positionOrder6Max // Default to 6-max
        }
        
        // 4. Find the index of the hero's position in the order
        guard let heroIndex = positionOrder.firstIndex(of: heroPosition) else {
            // Fallback if hero's position isn't in the standard order
            return CGPoint(x: centerX, y: centerY)
        }
        
        // 5. Define seat positions around the table (clockwise from bottom)
        // These are the fixed seat locations regardless of who sits where
        let seatPositions: [(CGFloat, CGFloat)]
        
        if tableSize == 2 {
            // For heads-up (2 players), just use bottom and top
            seatPositions = [
                (0.5, 0.7),  // bottom (hero)
                (0.5, 0.1)   // top (opponent)
            ]
        } else if tableSize <= 6 {
            // 6-max table positions (clockwise from bottom)
            seatPositions = [
                (0.5, 0.75),   // bottom
                (0.15, 0.55), // bottom left
                (0.15, 0.3), // middle left
                (0.5, 0.05),  // top left
                (0.85, 0.3), // middle right
                (0.85, 0.55)  // bottom right
            ]
        } else {
            // 9-max table positions (clockwise from bottom)
            seatPositions = [
                (0.5, 0.75),    // bottom
                (0.15, 0.66),  // bottom left
                (0.11, 0.48),  // lower left
                (0.11, 0.25),  // middle left
                (0.35, 0.08),  // upper left
                (0.65, 0.08),  // upper right
                (0.89, 0.25),  // middle right
                (0.89, 0.48),  // lower right
                (0.85, 0.66)   // bottom right
            ]
        }
        
        // 6. If this is the hero, always place at the bottom position
        if isHero {
            let (xPercent, yPercent) = seatPositions[0] // Hero always at bottom
            return CGPoint(x: width * xPercent, y: height * yPercent)
        }
        
        // 7. For other players, calculate their position relative to hero
        guard let playerPosition = player.position,
              let playerIndex = positionOrder.firstIndex(of: playerPosition) else {
            // Fallback if player's position isn't found
            return CGPoint(x: centerX, y: centerY)
        }
        
        // Calculate relative position (how many seats away from hero, clockwise)
        let relativePosition = (playerIndex - heroIndex + positionOrder.count) % positionOrder.count
        
        // 8. Map to the appropriate seat position
        // Seat 0 is always hero at bottom, so we start at seat 1
        let seatIndex = relativePosition == 0 ? 0 : relativePosition
        
        // Ensure we don't go out of bounds
        let safeSeatIndex = min(seatIndex, seatPositions.count - 1)
        let (xPercent, yPercent) = seatPositions[safeSeatIndex]
        
        return CGPoint(x: width * xPercent, y: height * yPercent)
    }
    
    private func getBetPosition() -> CGPoint {
        let playerPos = getPosition()
        let width = geometry.size.width
        let height = geometry.size.height
        let centerX = width * 0.5
        let centerY = height * 0.4
        
        // Calculate vector from center to player
        let vectorX = playerPos.x - centerX
        let vectorY = playerPos.y - centerY
        
        // Special handling for hero
        if isHero {
            // Place bet up and to the right of hero
            return CGPoint(x: playerPos.x + 60, y: playerPos.y - 25)
        }
        
        // For other players, calculate bet position based on their location
        // Normalize the vector for direction calculation
        let length = sqrt(vectorX * vectorX + vectorY * vectorY)
        let normalizedVectorX = length > 0 ? vectorX / length : 0
        let normalizedVectorY = length > 0 ? vectorY / length : -1
        
        // Scale determines how far toward center the bet appears
        let scaleFactor: CGFloat = 0.4
        
        // Calculate bet position (toward center of table)
        let betX = playerPos.x - (normalizedVectorX * width * 0.15)
        let betY = playerPos.y - (normalizedVectorY * height * 0.1)
        
        // Add small random variation to prevent exact overlaps
        let seatOffset = CGFloat(player.seat % 3) * 5.0
        let seatOffsetX = seatOffset * normalizedVectorY  // Perpendicular to vector
        let seatOffsetY = -seatOffset * normalizedVectorX // Perpendicular to vector
        
        return CGPoint(x: betX + seatOffsetX, y: betY + seatOffsetY)
    }
    
    // Position for the dealer button
    private func getDealerButtonPosition() -> CGPoint {
        let position = getPosition()
        
        // For the dealer button, we'll place it on a fixed side of the player box
        // based on where they are in relation to the table center
        let width = geometry.size.width
        let height = geometry.size.height
        let centerX = width * 0.5
        let centerY = height * 0.4
        
        // Calculate vector from center to player
        let vectorX = position.x - centerX
        let vectorY = position.y - centerY
        
        // Determine which quadrant the player is in
        if vectorY < 0 { // Player is in top half
            if vectorX < 0 { // Top left
                return CGPoint(x: position.x + 25, y: position.y + 20)
            } else { // Top right
                return CGPoint(x: position.x - 25, y: position.y + 20)
            }
        } else { // Player is in bottom half
            if vectorX < 0 { // Bottom left
                return CGPoint(x: position.x + 25, y: position.y - 20)
            } else { // Bottom right
                return CGPoint(x: position.x - 25, y: position.y - 20)
            }
        }
    }
    
    private var shouldShowCards: Bool {
        // If player has folded, don't show cards
        if isFolded {
            return false
        }
        
        // Otherwise, always show cards (blank or real)
        return true
    }
    
    // Whether to show the actual card values or just back-faced cards
    private var shouldRevealCardValues: Bool {
        // Hero's cards are always revealed if not folded
        if isHero && !isFolded {
            return true
        }
        
        // For villains, ONLY show cards when the showdown is complete
        if !isHero && !isFolded && isShowdownComplete {
            return true
        }
        
        // Otherwise, keep cards hidden
        return false
    }
    
    var body: some View {
        let cardWidth: CGFloat = 36
        let cardHeight: CGFloat = cardWidth / 0.69 // Maintain consistent aspect ratio
        let position = getPosition()
        let betPosition = getBetPosition()
        
        // Use standard poker card size for all cards
        let rectWidth: CGFloat = isHero ? 110 : 80
        let rectHeight: CGFloat = isHero ? 60 : 40
        let fontSize: CGFloat = isHero ? 17 : 14
        let stackFontSize: CGFloat = isHero ? 15 : 12
        let cardOffset: CGFloat = isHero ? -44 : -36
        
        ZStack {
            // Main content in a separate ZStack for proper layering
            ZStack {
                // Cards first (will be behind player info but above table)
                if shouldShowCards {
                    HStack(spacing: 8) {
                        ForEach(0..<2, id: \ .self) { index in
                            if shouldRevealCardValues {
                                if showdownRevealed && player.finalCards != nil && index < player.finalCards!.count {
                                    CardView(card: Card(from: player.finalCards![index]))
                                        .aspectRatio(0.69, contentMode: .fit)
                                        .frame(width: cardWidth, height: cardHeight)
                                        .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
                                } else if let cards = player.cards, index < cards.count {
                                    CardView(card: Card(from: cards[index]))
                                        .aspectRatio(0.69, contentMode: .fit)
                                        .frame(width: cardWidth, height: cardHeight)
                                        .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
                                } else {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.gray.opacity(0.3))
                                        .aspectRatio(0.69, contentMode: .fit)
                                        .frame(width: cardWidth, height: cardHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: isHero ? 7 : 5)
                                        .fill(Color.gray)
                                        .aspectRatio(0.69, contentMode: .fit)
                                        .frame(width: cardWidth, height: cardHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: isHero ? 7 : 5)
                                                .stroke(Color.white, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    .offset(y: cardOffset)
                    .zIndex(1)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showCards)
                }
                
                // Player info rectangle on top -> Now just player info text
                VStack(spacing: isHero ? 4 : 4) {
                    ZStack {
                        if showCheck {
                            Text("CHECK")
                                .font(.system(size: isHero ? 22 : 16, weight: .bold))
                                .foregroundColor(.yellow)
                                .padding(6)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(8)
                                .transition(.scale.combined(with: .opacity))
                                .zIndex(2)
                        }
                        Text(displayName)
                            .font(.system(size: isHero ? 20 : fontSize, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(String(format: "$%.0f", stack))
                        .font(.system(size: isHero ? 18 : stackFontSize, weight: isHero ? .medium : .regular))
                        .foregroundColor(isWinner ? .green : .white.opacity(0.9))
                }
                .frame(width: isHero ? 110 : rectWidth, height: isHero ? 60 : rectHeight)
                .background(
                    RoundedRectangle(cornerRadius: isHero ? 13 : 10)
                        .fill(Color.black.opacity(isHero ? 0.9 : 0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: isHero ? 13 : 10)
                                .stroke(isWinner ? Color.green : Color.white.opacity(0.7), lineWidth: isWinner ? 2 : 1)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                )
                .scaleEffect(isWinner && showPotDistribution ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isWinner && showPotDistribution)
                .zIndex(2)  // Keep info on top
                .opacity(isFolded ? 0.5 : 1.0)
            }
            .position(x: position.x, y: position.y)
            
            // Dealer button only for the player on the button
            if isOnButton {
                DealerButtonView()
                    .scaleEffect(0.8)
                    .position(getDealerButtonPosition())
                    .zIndex(3)
            }
            
            // Bet amount in separate layer
            if let bet = betAmount, bet > 0 {
                ChipView(amount: bet)
                    .scaleEffect(isHero ? 1.1 : 0.9) // Slightly larger chips overall 
                    .position(x: betPosition.x, y: betPosition.y)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: bet)
                    .zIndex(3)  // Always on top
            }
        }
        .onAppear {
            showCards = true
        }
        .onChange(of: isFolded) { folded in
            withAnimation {
                showCards = !folded
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCheck)
    }
}

// Dealer button view
struct DealerButtonView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.9),
                        Color.gray.opacity(0.7)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.4), radius: 1)
            
            Text("D")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
        }
    }
}

// Update ChipView for better aesthetics
struct ChipView: View {
    let amount: Double
    
    // Define chip denominations and their colors
    private let chipDenominations: [(value: Int, color: Color)] = [
        (500, Color(red: 0.6, green: 0.0, blue: 0.6)), // Purple for 500
        (100, Color(red: 0.0, green: 0.0, blue: 0.8)), // Blue for 100
        (25, Color(red: 0.9, green: 0.0, blue: 0.0)),  // Red for 25
        (5, Color(red: 0.0, green: 0.6, blue: 0.0)),   // Green for 5
        (1, Color(red: 0.5, green: 0.5, blue: 0.5))    // Gray for 1
    ]
    
    // Calculate how many of each chip to display
    private func calculateChips() -> [(value: Int, count: Int, color: Color)] {
        let intAmount = Int(amount)
        var remainingAmount = intAmount
        var result: [(value: Int, count: Int, color: Color)] = []
        
        for (value, color) in chipDenominations {
            if remainingAmount >= value {
                let count = min(remainingAmount / value, 3) // Cap at 3 chips per denomination for visual clarity
                remainingAmount -= count * value
                result.append((value: value, count: count, color: color))
            }
        }
        
        // Limit to 3 different denominations for visual clarity
        if result.count > 3 {
            result = Array(result.prefix(3))
        }
        
        return result
    }
    
    var body: some View {
        let chipStacks = calculateChips()
        
        return ZStack {
            // Chip stack
            VStack(alignment: .center, spacing: 0) {
                HStack(alignment: .bottom, spacing: -2) {
                    // Create the chip stacks side by side for a more compact look
                    ForEach(0..<chipStacks.count, id: \.self) { stackIndex in
                        let stack = chipStacks[stackIndex]
                        ZStack {
                            // Stack the chips of the same value
                            ForEach(0..<stack.count, id: \.self) { chipIndex in
                                PokerChip(color: stack.color)
                                    .offset(y: CGFloat(-chipIndex * 2)) // Slightly offset each chip for 3D effect
                            }
                        }
                    }
                }
                
                // Amount text below the chips
                Text("$\(Int(amount))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(6)
                    .padding(.top, 2)
            }
        }
        .frame(width: 55, height: 40)
    }
}

// Individual poker chip component
struct PokerChip: View {
    let color: Color
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
            
            // Colored center
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color,
                            color.opacity(0.7)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 18, height: 18)
            
            // Inner pattern ring
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                .frame(width: 15, height: 15)
            
            // Edge detail
            Circle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: 22, height: 22)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
    }
}

struct ActionLogView: View {
    let hand: ParsedHandHistory
    let currentStreetIndex: Int
    let currentActionIndex: Int
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0...currentStreetIndex, id: \.self) { streetIndex in
                    let street = hand.raw.streets[streetIndex]
                    ForEach(0..<(streetIndex == currentStreetIndex ? currentActionIndex : street.actions.count), id: \.self) { actionIndex in
                        let action = street.actions[actionIndex]
                        Text("\(action.playerName) \(action.action) \(action.amount > 0 ? "$\(Int(action.amount))" : "")")
                            .foregroundColor(.white)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

// Update the main view's frame to ensure everything is centered
extension View {
    func centerInParent() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)
    }
} 
