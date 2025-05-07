import SwiftUI
import Foundation

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
    
    private let tableColor = Color(red: 45/255, green: 120/255, blue: 65/255)
    private let tableBorderColor = Color(red: 74/255, green: 54/255, blue: 38/255)
    
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
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0))
                    .ignoresSafeArea()
                
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
                    
                    Spacer()
                    
                    // Poker Table
                    ZStack {
                        // Table background
                        Ellipse()
                            .fill(tableColor)
                            .overlay(
                                Ellipse()
                                    .stroke(tableBorderColor, lineWidth: 8)
                            )
                            .frame(width: geometry.size.width * 0.93, height: geometry.size.height * 0.78)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                        
                        // Stack Logo - positioned above pot
                        Text("STACK")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(0.3)
                            .offset(y: -geometry.size.height * 0.14)

                        // Pot display - centered at middle of table
                        if potAmount > 0 {
                            ChipView(amount: potAmount)
                                .scaleEffect(1.2) // Scale up for better visibility
                                .transition(.scale.combined(with: .opacity))
                                .animation(.spring(response: 0.4), value: potAmount)
                                .offset(y: geometry.size.height * 0.0)
                        }

                        // Community Cards - positioned closer to hero
                        CommunityCardsView(cards: allCommunityCards)
                            .offset(y: geometry.size.height * 0.08)
                            .scaleEffect(1.15) // Make it slightly larger overall

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
                            .zIndex(100) // Ensure it's on top
                        }
                    }
                    .frame(height: geometry.size.height * 0.78)
                    
                    Spacer()
                        .frame(height: 0) // Collapse this spacer
                    
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
            ShareHandView(hand: hand, showingReplay: $showingShareSheet)
                .environmentObject(postService)
                .environmentObject(userService)
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
                print("Player \(player.name) has \(player.cards!.count) cards: \(player.cards!.joined(separator: ", "))")
            }
            if player.finalCards != nil && !player.finalCards!.isEmpty {
                print("Player \(player.name) has \(player.finalCards!.count) final cards: \(player.finalCards!.joined(separator: ", "))")
            }
        }
        
        // Ensure the dealer button is set - set it manually
        // This is especially important for players who should have the BTN position
        for player in hand.raw.players {
            if player.position == "BTN" {
                // Make sure the player with BTN position is marked as the dealer
                print("Found BTN player: \(player.name) - marking as dealer")
            }
        }
        
        // Check showdown flag to ensure it's properly set
        if let showdown = hand.raw.showdown {
            print("Hand has showdown = \(showdown)")
            if showdown {
                // If hand has showdown, ensure we have proper data for card reveal
                let playersWithCards = hand.raw.players.filter { $0.cards != nil && !$0.cards!.isEmpty }
                if playersWithCards.count <= 1 {
                    print("WARNING: Showdown flag is true but only \(playersWithCards.count) players have cards")
                }
            }
        } else {
            print("Hand does not have explicit showdown flag")
        }
        
        // Log pot distribution for debugging
        if let distribution = hand.raw.pot.distribution {
            print("Hand has pot distribution: \(distribution.map { "\($0.playerName): $\($0.amount)" }.joined(separator: ", "))")
        } else {
            print("Hand does not have pot distribution data")
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
        
        print("DEBUG - startReplay(): All state reset, cards will be revealed at the end of the hand")
        
        // Initialize player stacks to their starting values
        initializeStacks()
    }
    
    private func nextAction() {
        // If hand is complete but we need one more click for showdown, handle that
        if isHandComplete && !isShowdownComplete && (hand.raw.showdown ?? false) {
            print("DEBUG - Final showdown click: Revealing all cards now")
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
                    print("DEBUG - Last action on river with showdown=true, revealing cards immediately")
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
                let heroPnl = hand.raw.pot.heroPnl ?? 0
                if heroPnl > 0 {
                    winnerName = hero.name
                    winningHand = hero.finalHand ?? "winning hand"
                } else {
                    // Find a non-folded villain
                    let activeVillains = hand.raw.players.filter { !$0.isHero && !foldedPlayers.contains($0.name) }
                    if let villain = activeVillains.first {
                        winnerName = villain.name
                        winningHand = villain.finalHand ?? "winning hand"
                    } else {
                        winnerName = "Unknown Player"
                        winningHand = ""
                    }
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
            print("Error: Player \(action.playerName) not found in stacks during action processing.")
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
            print("Warning: Unhandled action type '\(action.action)' for player \(action.playerName)")
            // If an action involves an amount (like maybe an uncategorized "bets"),
            // you might need a fallback, but explicit handling is better.
            // Example: if action.amount > 0 { /* handle generic bet? */ }
        }
    }
    
    private func handleShowdown() {
        print("DEBUG - handleShowdown() called - Checking if card reveal is needed")
        
        // Only reveal cards if it's explicitly a showdown hand or there are multiple active players
        withAnimation(.easeInOut(duration: 0.5)) {
            // Mark hand as complete, but don't immediately show cards
            
            // CRITICAL: Check hand.raw.showdown to determine if cards should be revealed
            if let showdown = hand.raw.showdown, showdown == true {
                print("DEBUG - Hand has showdown=true flag, revealing cards immediately at end")
                showdownRevealed = true
                isShowdownComplete = true
                
                // Show winner popup after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showWinnerAnnouncement()
                }
            } else {
                // For non-showdown hands, check if multiple players are active
                let activePlayerCount = hand.raw.players.filter { !foldedPlayers.contains($0.name) }.count
                if activePlayerCount > 1 {
                    print("DEBUG - Multiple active players at showdown but no explicit flag. Revealing immediately.")
                    showdownRevealed = true
                    isShowdownComplete = true
                    
                    // Show winner popup after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showWinnerAnnouncement()
                    }
                } else {
                    print("DEBUG - No showdown: \(activePlayerCount) active player(s) and showdown flag is \(hand.raw.showdown)")
                    showdownRevealed = false
                    isShowdownComplete = false
                }
            }
        }
        
        // Determine winners based on pot distribution or defaults
        if let distribution = hand.raw.pot.distribution {
            // Use explicit pot distribution from hand history
            winningPlayers = Set(distribution.filter { $0.amount > 0 }.map { $0.playerName })
            
            print("DEBUG - Using explicit pot distribution: \(distribution.map { "\($0.playerName): $\($0.amount)" }.joined(separator: ", "))")
            
            // Log final hand rankings for all winners
            for winner in distribution.filter({ $0.amount > 0 }) {
                print("DEBUG - Winner \(winner.playerName) with hand: \(winner.hand)")
            }
            
            // Animate pot distribution after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showPotDistribution = true
                    
                    // Update player stacks with winnings
                    for potDist in distribution {
                        if let currentStack = self.playerStacks[potDist.playerName] {
                            self.playerStacks[potDist.playerName] = currentStack + potDist.amount
                            print("DEBUG - Distributing $\(potDist.amount) to \(potDist.playerName), new stack: $\(currentStack + potDist.amount)")
                        }
                    }
                    self.potAmount = 0
                }
            }
        } else {
            // No distribution data, fallback to simple determination
            print("DEBUG - No pot distribution data, using fallback winner determination")
            
            // If only one player is active (everyone else folded), they win
            let activePlayers = hand.raw.players.filter { !foldedPlayers.contains($0.name) }
            
            if activePlayers.count == 1 {
                // Single player wins the pot
                let winner = activePlayers.first!
                winningPlayers = [winner.name]
                
                print("DEBUG - Single active player: \(winner.name) wins by fold")
                
                // Animate winner getting pot
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        showPotDistribution = true
                        
                        // Update winner stack
                        if let currentStack = self.playerStacks[winner.name] {
                            self.playerStacks[winner.name] = currentStack + self.potAmount
                            print("DEBUG - Distributing $\(self.potAmount) to \(winner.name), new stack: $\(currentStack + self.potAmount)")
                        }
                        self.potAmount = 0
                    }
                }
            } else if showdownRevealed {
                // Try to determine winner based on Hero PnL
                let heroPlayer = hand.raw.players.first { $0.isHero }
                
                if let hero = heroPlayer {
                    let heroPnl = hand.raw.pot.heroPnl ?? 0
                    if heroPnl > 0 {
                        // Hero won
                        winningPlayers = [hero.name]
                        print("DEBUG - Hero won based on positive PnL: $\(heroPnl)")
                    } else {
                        // Villain(s) won - make all non-hero active players winners
                        winningPlayers = Set(activePlayers.filter { !$0.isHero }.map { $0.name })
                        print("DEBUG - Villains won based on negative hero PnL: $\(heroPnl)")
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
                    // Can't determine winner, distribute randomly
                    print("DEBUG - Cannot determine winner, using fallback equal distribution")
                    
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
        }
        
        isHandComplete = true
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
        let tableCenterX = width * 0.5
        let tableCenterY = height * 0.4 // Center of the ellipse
        let tableWidthRadius = width * 0.93 * 0.5 * 0.9 // Condense horizontally
        let tableHeightRadius = height * 0.75 * 0.5 * 0.9 // Condense vertically

        // Determine position order based on table size
        let tableSize = allPlayers.count
        let positionOrder: [String]
        switch tableSize {
            case 2: positionOrder = positionOrder2Max
            case 3...6: positionOrder = positionOrder6Max // Assume 6max layout for intermediate sizes too
            case 7...9: positionOrder = positionOrder9Max
            default: positionOrder = positionOrder6Max // Default fallback
        }
        
        let numSeats = positionOrder.count // Use the count from the relevant order

        let hero = allPlayers.first(where: { $0.isHero })
        guard let hero = hero else {
            print("Error: Hero player not found in allPlayers for HandReplayView layout.")
            fatalError("Hero player required for layout but not found.") // Or handle more gracefully
        }
        let heroPos = hero.position // Now accessing the unwrapped hero
        let heroSeatIndex = hero.seat - 1 // Now accessing the unwrapped hero

        
        let playerSeatIndex = player.seat - 1 // Use seat index (0-based)

        // --- Angle Calculation --- 
        // Calculate the angle step between seats
        let angleStep = 360.0 / Double(numSeats)
        
        // Calculate the "natural" angle for the hero based on their seat index
        // Assuming seat 1 (index 0) is roughly SB position (e.g., ~225 degrees from top)
        // And seats increase clockwise.
        // Let's refine: Assume seat 1 starts just left of bottom (Hero's spot)
        let baseAngleOffset = -100.0 // Degrees offset from positive X-axis for seat 1
        let heroNaturalAngle = baseAngleOffset + Double(heroSeatIndex) * angleStep
        
        // Calculate the desired angle for the hero (bottom center)
        let heroTargetAngle = 80.0 // Moved hero slightly more up (smaller angle)
        
        // Calculate the rotation needed to move hero to the target angle
        let rotationOffset = heroTargetAngle - heroNaturalAngle
        
        // Calculate the natural angle for the current player
        let playerNaturalAngle = baseAngleOffset + Double(playerSeatIndex) * angleStep
        
        // Apply the rotation offset to the current player's angle
        let playerFinalAngleDegrees = playerNaturalAngle + rotationOffset
        let playerFinalAngleRadians = playerFinalAngleDegrees * .pi / 180.0
        
        // Calculate position on the ellipse using the final angle
        let x = tableCenterX + tableWidthRadius * cos(playerFinalAngleRadians)
        
        // Calculate base y position
        var y = tableCenterY + tableHeightRadius * sin(playerFinalAngleRadians)
        
        // Move hero up a bit more if this is the hero player
        if isHero {
            y -= 15  // Move hero up by 15 points
        }
        
        return CGPoint(x: x, y: y)
    }
    
    private func getBetPosition() -> CGPoint {
        let width = geometry.size.width
        let height = geometry.size.height

        // Calculate vector from center to player position
        let pos = getPosition()
        let tableCenterY = height * 0.4
        let vectorX = pos.x - (width * 0.5)
        let vectorY = pos.y - tableCenterY
        
        // Only normalize if the vector has length
        let length = sqrt(vectorX * vectorX + vectorY * vectorY)
        let normalizedVectorX = length > 0 ? vectorX / length : 0
        let normalizedVectorY = length > 0 ? vectorY / length : -1 // Default point up if zero vector

        // Use different scaling factors for different players to avoid overlap
        let scaleFactor: CGFloat = isHero ? 50 : 70
        var offsetX = normalizedVectorX * -scaleFactor
        var offsetY = normalizedVectorY * -scaleFactor

        // For hero, place bet to the right (screen right)
        if isHero {
            offsetX = 60 // Move bet chip to the hero's right (screen right)
            offsetY = 0
        }

        // Add a small random offset to avoid exact overlaps when bets are the same
        let jitter = CGFloat(player.seat % 3) * 5.0 // Small offset based on seat number
        let jitterX = jitter * normalizedVectorY // Perpendicular to the vector
        let jitterY = -jitter * normalizedVectorX

        return CGPoint(x: pos.x + offsetX + jitterX, y: pos.y + offsetY + jitterY)
    }
    
    // Position for the dealer button - needs adjustment based on new getPosition
    private func getDealerButtonPosition() -> CGPoint {
        let position = getPosition()
        let width = geometry.size.width
        let height = geometry.size.height
        let tableCenterY = height * 0.4
        
        // Calculate vector from center to player position
        let vectorX = position.x - (width * 0.5)
        let vectorY = position.y - tableCenterY
        let length = sqrt(vectorX * vectorX + vectorY * vectorY)
        
        // Only use normalized vector if length is non-zero
        let normalizedVectorX = length > 0 ? vectorX / length : 0
        let normalizedVectorY = length > 0 ? vectorY / length : -1
        
        let perpendicularOffsetX = (normalizedVectorY) * 25
        let perpendicularOffsetY = (-normalizedVectorX) * 25
        
        // Further offset based on general location (e.g., push slightly out)
        let outwardOffsetX = normalizedVectorX * 10
        let outwardOffsetY = normalizedVectorY * 10

        return CGPoint(x: position.x + perpendicularOffsetX + outwardOffsetX, 
                       y: position.y + perpendicularOffsetY + outwardOffsetY)
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

struct ShareHandView: View {
    let hand: ParsedHandHistory
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @State private var postText = ""
    @State private var isLoading = false
    @FocusState private var isTextEditorFocused: Bool
    @Binding var showingReplay: Bool
    @State private var isSharing = false
    
    private var heroName: String? {
        hand.raw.players.first(where: { $0.isHero })?.name
    }
    
    private var heroPnl: Double {
        hand.raw.pot.heroPnl ?? 0
    }
    
    private var formattedPnl: String {
        if heroPnl >= 0 {
            return "+$\(Int(heroPnl))"
        } else {
            return "-$\(abs(Int(heroPnl)))"
        }
    }
    
    private var handResult: String {
        // Determine the outcome of the hand for a concise description
        if let showdown = hand.raw.showdown, showdown {
            if let distribution = hand.raw.pot.distribution, !distribution.isEmpty {
                // Find if hero won the showdown
                let heroWon = distribution.contains(where: { 
                    $0.amount > 0 && $0.playerName == heroName
                })
                
                if heroWon {
                    if let heroWinner = distribution.first(where: { $0.playerName == heroName }) {
                        return "Won at showdown with \(heroWinner.hand)"
                    } else {
                        return "Won at showdown"
                    }
                } else {
                    return "Lost at showdown"
                }
            } else {
                // No distribution data - use PnL to determine
                return heroPnl > 0 ? "Won at showdown" : "Lost at showdown"
            }
        } else {
            // No showdown
            return heroPnl > 0 ? "Won, all opponents folded" : "Folded"
        }
    }
    
    private var gameDetails: String {
        let stakes = "\(Int(hand.raw.gameInfo.smallBlind))/\(Int(hand.raw.gameInfo.bigBlind))"
        let tableSize = "\(hand.raw.gameInfo.tableSize)-max"
        return "$\(stakes) \(tableSize)"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 12) {
                        if let profileImage = userService.currentUserProfile?.avatarURL {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    )
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let displayName = userService.currentUserProfile?.displayName,
                               !displayName.isEmpty {
                                Text(displayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            } else if let username = userService.currentUserProfile?.username {
                                Text(username)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Text("Share your hand")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    
                    // Hand Summary
                    HandSummaryView(hand: hand)
                        .padding(.horizontal)
                    
                    // Text Editor
                    TextEditor(text: $postText)
                        .focused($isTextEditorFocused)
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        .frame(maxHeight: .infinity)
                        .padding()
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                    
                    // Default post text suggestion

                    
                    
                    // Bottom toolbar
                    HStack {
                        Spacer()
                        Text("\(280 - postText.count)")
                            .foregroundColor(postText.count > 280 ? .red : .gray)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding()
                    .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 0.95)))
                }
            }
            .navigationTitle("Share Hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: shareHand) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Share")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || postText.count > 280)
                    .foregroundColor(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postText.count > 280 ? .gray : .white)
                }
            }
        }
        .onAppear {
            isTextEditorFocused = true
        }
    }
    
    // Generate a default post text based on the hand outcome

    
    private func shareHand() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let userId = userService.currentUserProfile?.id,
              let username = userService.currentUserProfile?.username,
              let profileImage = userService.currentUserProfile?.avatarURL else { return }
        
        let displayName = userService.currentUserProfile?.displayName
        
        isLoading = true
        
        Task {
            do {
                try await postService.createHandPost(
                    content: postText,
                    userId: userId,
                    username: username,
                    displayName: displayName,
                    profileImage: profileImage,
                    hand: hand
                )
                try await postService.fetchPosts()
                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                print("Error sharing hand: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
} 
