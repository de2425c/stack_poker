import SwiftUI
import FirebaseAuth

// Constants for styling consistency
private enum DesignConstants {
    // Colors
    static let primaryAccent = Color(red: 0/255, green: 194/255, blue: 255/255) // Bright blue accent
    static let secondaryAccent = Color(red: 87/255, green: 244/255, blue: 190/255) // Mint green accent
    static let cardBackground = Color.black.opacity(0.3)
    static let panelBackground = Color(red: 15/255, green: 25/255, blue: 40/255).opacity(0.7)
    static let darkOverlay = Color.black.opacity(0.5)
    
    // Sizing
    static let buttonCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 16
    static let transitionDuration = 0.3
    static let contentPadding: CGFloat = 20
    static let topSpacing: CGFloat = 24
    
    // Text styles
    static let titleFont = Font.title2.weight(.bold)
    static let subtitleFont = Font.headline.weight(.semibold)
    static let buttonFont = Font.system(size: 16, weight: .semibold)
}

struct ManualHandEntryWizardView: View {
    enum EntryStep: Int, CaseIterable {
        case stakes = 0
        case players = 1
        case board = 2
        case actions = 3
        
        var title: String {
            switch self {
            case .stakes: return "Game Info"
            case .players: return "Players"
            case .board: return "Community Cards"
            case .actions: return "Actions"
            }
        }
        
        var systemIcon: String {
            switch self {
            case .stakes: return "dollarsign.circle"
            case .players: return "person.2.fill"
            case .board: return "suit.club.fill"
            case .actions: return "arrow.left.arrow.right"
            }
        }
    }
    
    @StateObject var viewModel = HandEntryViewModel()
    @StateObject private var handStore = HandStore(userId: Auth.auth().currentUser?.uid ?? "")
    @Environment(\.presentationMode) var presentationMode
    @State private var currentStep: EntryStep = .stakes
    @State private var showingCancelAlert = false
    @State private var errorMessage: String? = nil
    @State private var isCompleting = false
    
    var body: some View {
        NavigationView { 
            ZStack {
                // Background
                AppBackgroundView().ignoresSafeArea(.all)
                
                // Content
                VStack(spacing: 0) {
                    // Top section
                    VStack(spacing: 16) {
                        // Progress indicator
                        progressBar
                            .padding(.top, DesignConstants.topSpacing)
                        
                        // Step title
                        stepTitle
                    }
                    .padding(.horizontal, DesignConstants.contentPadding)
                    .padding(.bottom, 16)
                    
                    // Main content area
                    ZStack {
                        // Background for main content
                        RoundedRectangle(cornerRadius: DesignConstants.panelCornerRadius)
                            .fill(DesignConstants.panelBackground)
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
                            .padding(.horizontal, DesignConstants.contentPadding - 6)
                        
                        // Step view content
                        currentStepView
                            .padding(.horizontal, DesignConstants.contentPadding)
                            .padding(.vertical, 18)
                    }
                    .padding(.bottom, 12)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        errorMessageView(message: errorMessage)
                    }
                    
                    Spacer()
                    
                    // Navigation controls
                    navigationControls
                        .padding(.horizontal, DesignConstants.contentPadding)
                        .padding(.vertical, 16)
                        .background(
                            DesignConstants.darkOverlay
                                .ignoresSafeArea(edges: .bottom)
                        )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { 
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingCancelAlert = true }) {
                        Text("Cancel")
                            .foregroundColor(DesignConstants.primaryAccent)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("New Hand")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .environmentObject(viewModel)
            .alert(isPresented: $showingCancelAlert) {
                Alert(
                    title: Text("Discard Hand?"),
                    message: Text("Any information entered will be lost."),
                    primaryButton: .destructive(Text("Discard")) {
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    // MARK: - View Components
    
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(EntryStep.allCases, id: \.self) { step in
                VStack(spacing: 4) {
                    // Step indicator
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? 
                                  DesignConstants.primaryAccent : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        if step.rawValue < currentStep.rawValue {
                            // Completed step
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                        } else if step.rawValue == currentStep.rawValue {
                            // Current step
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                        } else {
                            // Future step
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    // Step label - more compact
                    Text(step.title)
                        .font(.system(size: 11, weight: step.rawValue == currentStep.rawValue ? .semibold : .regular))
                        .foregroundColor(step.rawValue == currentStep.rawValue ? 
                                        DesignConstants.primaryAccent : .gray)
                        .fixedSize()
                }
                
                // Connecting line (except after last step)
                if step != EntryStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? 
                              DesignConstants.primaryAccent : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: currentStep)
    }
    
    private var stepTitle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentStep.title)
                    .font(DesignConstants.titleFont)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Image(systemName: currentStep.systemIcon)
                .font(.title2)
                .foregroundColor(DesignConstants.primaryAccent)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.3))
                )
        }
    }
    
    private func getStepDescription(for step: EntryStep) -> String {
        switch step {
        case .stakes: return "Set blinds and table size"
        case .players: return "Add players and positions"
        case .board: return "Enter community cards"
        case .actions: return "Record betting actions"
        }
    }
    
    private func errorMessageView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, DesignConstants.contentPadding)
        .padding(.vertical, 8)
        .transition(.opacity)
    }
    
    @ViewBuilder
    private var currentStepView: some View {
        ZStack {
        switch currentStep {
        case .stakes:
            StakesEntryStepView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
        case .players:
            PlayerEntryStepView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
        case .board:
            BoardEntryStepView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
        case .actions:
            AllActionsEntryStepView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: DesignConstants.transitionDuration), value: currentStep)
    }
    
    private var navigationControls: some View {
        HStack {
            // Back button
            Button(action: goToPreviousStep) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(DesignConstants.buttonFont)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius)
                        .fill(Color.gray.opacity(0.25))
                )
            }
            .opacity(currentStep == .stakes ? 0.3 : 1.0)
            .disabled(currentStep == .stakes)
            
            Spacer()
            
            // Next/Save button
            Button(action: {
                if currentStep == EntryStep.allCases.last {
                    validateAndSave()
                } else {
                    goToNextStep()
                }
            }) {
                HStack(spacing: 8) {
                    Text(currentStep == EntryStep.allCases.last ? "Save Hand" : "Next Step")
                    Image(systemName: currentStep == EntryStep.allCases.last ? "checkmark" : "chevron.right")
                }
                .font(DesignConstants.buttonFont)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .foregroundColor(.black)
                .background(
                    RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius)
                        .fill(DesignConstants.primaryAccent)
                        .shadow(color: DesignConstants.primaryAccent.opacity(0.3), radius: 5, y: 2)
                )
            }
            .disabled(isCompleting)
            .overlay(
                isCompleting ? 
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.black))
                    .scaleEffect(0.8)
                    .padding() : nil
            )
        }
    }
    
    // MARK: - Action Methods
    
    private func goToNextStep() {
        withAnimation {
            errorMessage = nil
            
            if validateCurrentStep() {
                let allSteps = EntryStep.allCases
                if let currentIndex = allSteps.firstIndex(of: currentStep),
                   currentIndex < allSteps.count - 1 {
                    currentStep = allSteps[currentIndex + 1]
                }
            }
        }
    }
    
    private func goToPreviousStep() {
        withAnimation {
            errorMessage = nil
            
            let allSteps = EntryStep.allCases
            if let currentIndex = allSteps.firstIndex(of: currentStep),
               currentIndex > 0 {
                currentStep = allSteps[currentIndex - 1]
            }
        }
    }
    
    private func validateCurrentStep() -> Bool {
        switch currentStep {
        case .stakes:
            // Validate stakes
            if viewModel.smallBlind <= 0 || viewModel.bigBlind <= 0 {
                errorMessage = "Please enter valid blind values."
                return false
            }
            return true
            
        case .players:
            // Validate players
            if viewModel.players.isEmpty || !viewModel.players.contains(where: { $0.isHero }) {
                errorMessage = "You must include a Hero player."
                return false
            }
            
            let playersWithCards = viewModel.players.filter { $0.card1 != nil && $0.card2 != nil }
            if playersWithCards.isEmpty {
                errorMessage = "At least one player needs hole cards."
                return false
            }
            
            let playersWithPosition = viewModel.players.filter { $0.position != nil }
            if playersWithPosition.count < viewModel.players.count {
                errorMessage = "All players need a position assigned."
                return false
            }
            
            return true
            
        case .board:
            // Validate board (optional, but must be in sequence)
            return true
            
        case .actions:
            // Validate actions
            if viewModel.preflopActions.isEmpty {
                errorMessage = "At least one preflop action is required."
                return false
            }
            return true
        }
    }
    
    private func validateAndSave() {
        // Final validation
        if !validateCurrentStep() {
            return
        }
        
        // Check for overall hand validity
        if !validateHandHistory() {
            errorMessage = "Invalid hand history. Please check all entries."
            return
        }
        
        // Save and dismiss
        isCompleting = true
        
        // Create and save hand history using Task for async operation
        Task {
            do {
                // Create hand history
                guard let handHistory = createHandHistory() else {
                    await MainActor.run {
                        errorMessage = "Error creating hand history"
                        isCompleting = false
                    }
                    return
                }
                
                // Save to database using HandStore
                try await handStore.saveHand(handHistory)
                
                // Success - return to main thread and dismiss
                await MainActor.run { 
                    isCompleting = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                // Handle error on main thread
                await MainActor.run {
                    errorMessage = "Error saving hand: \(error.localizedDescription)"
                    isCompleting = false
                }
            }
        }
    }
    
    // MARK: - Hand History Processing
    
    // Validates that the hand history is complete and valid
    private func validateHandHistory() -> Bool {
        // Verify we have valid stakes
        if viewModel.smallBlind <= 0 || viewModel.bigBlind <= 0 {
            return false
        }
        
        // Validate players have positions and hero exists
        if !viewModel.players.contains(where: { $0.isHero }) {
             return false
        }
        
        let playersWithPosition = viewModel.players.filter { $0.position != nil }
        if playersWithPosition.count < viewModel.players.count {
            return false
        }
        
        // Validate at least one player has hole cards
        let playersWithCards = viewModel.players.filter { $0.card1 != nil && $0.card2 != nil }
        if playersWithCards.isEmpty {
             return false
         }
        
        // Validate the board cards sequence
        let hasFlop = viewModel.flopCard1 != nil && viewModel.flopCard2 != nil && viewModel.flopCard3 != nil
        let hasTurn = viewModel.turnCard != nil
        let hasRiver = viewModel.riverCard != nil
        
        if hasTurn && !hasFlop {
             return false
         }
         
        if hasRiver && (!hasFlop || !hasTurn) {
             return false
        }

        // Validate that preflop actions exist
        if viewModel.preflopActions.isEmpty {
            return false
        }
        
        return true
    }
    
    // Helper to create a ParsedHandHistory object from the view model data
    private func createHandHistory() -> ParsedHandHistory? {
        // Ensure all positions are filled
        ensureAllPositionsFilled()

        // Create game info
        let gameInfo = GameInfo(
            tableSize: viewModel.tableSize,
            smallBlind: viewModel.smallBlind,
            bigBlind: viewModel.bigBlind,
            dealerSeat: determineDealerSeat() 
        )
        
        // Create players array
        let players = createPlayersArray()
        
        // Create streets array with actions
        let streets = createStreetsArray()
        
        // Calculate pot amount and other necessary fields
        let potAmount = calculatePotAmount()
        
        // Determine if showdown occurred
        let showdown = determineShowdown()
        
        // Calculate hero PnL
        let heroPnL = calculateHeroPnL(potAmount: potAmount, showdown: showdown)
        
        // Determine pot distribution based on the hand outcome
        let potDistribution = createPotDistribution(potAmount: potAmount, players: players, showdown: showdown)
        
        // Create pot struct
        let pot = Pot(
            amount: potAmount,
            distribution: potDistribution,
            heroPnl: heroPnL
        )
        
        // Create raw hand history
        let rawHandHistory = RawHandHistory(
            gameInfo: gameInfo,
            players: players,
            streets: streets,
            pot: pot,
            showdown: showdown
        )
        
        // Create parsed hand history
        return ParsedHandHistory(raw: rawHandHistory)
    }
    
    // New helper to create pot distribution
    private func createPotDistribution(potAmount: Double, players: [Player], showdown: Bool) -> [PotDistribution]? {
        // Skip if there's no pot
        if potAmount <= 0 {
            return nil
        }
        
        // Get folded players
        let allActions = viewModel.preflopActions + viewModel.flopActions + 
                         viewModel.turnActions + viewModel.riverActions
        
        let folded = Set(allActions.filter { $0.action == "folds" }.map { $0.playerName })
        
        // Get active players at the end (players who haven't folded)
        let activePlayers = viewModel.players
            .filter { $0.position != nil }
            .filter { !folded.contains($0.position!) }
        
        // If no active players, something is wrong
        if activePlayers.isEmpty {
            return nil
        }
        
        // Track player contributions for accurate PnL
        var playerContributions = calculatePlayerContributions()
        
        // Single player wins automatically (everyone else folded)
        if activePlayers.count == 1 {
            let winner = activePlayers.first!
            let winnerName = players.first { $0.isHero == winner.isHero }?.name ?? winner.name
            
            // Create a distribution with the winner getting the entire pot
            return [
                PotDistribution(
                    playerName: winnerName,
                    amount: potAmount,
                    hand: "Winner by fold",
                    cards: [winner.card1, winner.card2].compactMap { $0 }
                )
            ]
        }
        
        // Multiple active players with showdown
        if showdown {
            // Get community cards
            let communityCards = [viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3, 
                                viewModel.turnCard, viewModel.riverCard].compactMap { $0 }
            
            // Get players with cards at showdown
            let playersWithCards = activePlayers.filter { $0.card1 != nil && $0.card2 != nil }
            
            // Calculate hand ranks for each player
            var playerRanks: [(player: PlayerEntry, handRank: Int, handName: String)] = []
            
            for player in playersWithCards {
                if let card1 = player.card1, let card2 = player.card2 {
                    let cards = [card1, card2]
                    let rank = calculateHandRank(holeCards: cards, communityCards: communityCards)
                    let handName = getHandName(rank: rank, holeCards: cards, communityCards: communityCards)
                    playerRanks.append((player, rank, handName))
                }
            }
            
            // Sort by hand rank (highest first)
            playerRanks.sort { $0.handRank > $1.handRank }
            
            // If no players with cards, can't determine (should not happen)
            if playerRanks.isEmpty {
                return nil
            }
            
            // Find all players tied for best hand
            let bestRank = playerRanks.first!.handRank
            let winners = playerRanks.filter { $0.handRank == bestRank }
            
            // Create distribution based on winners
            var distribution: [PotDistribution] = []
            
            // If multiple winners (split pot)
            if winners.count > 1 {
                let splitAmount = potAmount / Double(winners.count)
                
                for winner in winners {
                    let winnerName = players.first { $0.isHero == winner.player.isHero }?.name ?? winner.player.name
                    distribution.append(
                        PotDistribution(
                            playerName: winnerName,
                            amount: splitAmount,
                            hand: winner.handName,
                            cards: [winner.player.card1, winner.player.card2].compactMap { $0 }
                        )
                    )
                }
            } else {
                // Single winner
                let winner = winners.first!
                let winnerName = players.first { $0.isHero == winner.player.isHero }?.name ?? winner.player.name
                distribution.append(
                    PotDistribution(
                        playerName: winnerName,
                        amount: potAmount,
                        hand: winner.handName,
                        cards: [winner.player.card1, winner.player.card2].compactMap { $0 }
                    )
                )
            }
            
            return distribution
        }
        
        // Default case - no showdown and multiple active players (unexpected)
        return nil
    }
    
    // Helper to calculate hand name based on rank
    private func getHandName(rank: Int, holeCards: [String], communityCards: [String]) -> String {
        // Same logic as calculateHandRank but returns name instead of score
        if rank >= 700 {
            return "Four of a Kind"
        } else if rank >= 600 {
            return "Full House"
        } else if rank >= 500 {
            return "Flush"
        } else if rank >= 400 {
            return "Straight"
        } else if rank >= 300 {
            return "Three of a Kind"
        } else if rank >= 200 {
            return "Two Pair"
        } else if rank >= 100 {
            return "Pair"
        } else {
            return "High Card"
        }
    }
    
    // Helper to calculate each player's total contribution to the pot
    private func calculatePlayerContributions() -> [String: Double] {
        var playerContributions: [String: Double] = [:]
        
        // Initialize blinds
        if let sbPlayer = viewModel.players.first(where: { $0.position == "SB" }) {
            playerContributions[sbPlayer.position!] = viewModel.smallBlind
        }
        if let bbPlayer = viewModel.players.first(where: { $0.position == "BB" }) {
            playerContributions[bbPlayer.position!] = viewModel.bigBlind
        }
        
        // Process all streets
        let allActions = viewModel.preflopActions + viewModel.flopActions + 
                         viewModel.turnActions + viewModel.riverActions
        
        for action in allActions {
                let playerPos = action.playerName
            let currentContribution = playerContributions[playerPos] ?? 0

                switch action.action {
            case "bets", "raises":
                playerContributions[playerPos] = action.amount
                case "calls":
                playerContributions[playerPos] = action.amount
            case "posts":
                // Posts override any existing contribution
                playerContributions[playerPos] = action.amount
                default: 
                break // Fold and check don't change contribution
            }
        }
        
        return playerContributions
    }
    
    // Helper to calculate pot amount
    private func calculatePotAmount() -> Double {
        // Now use the player contributions to calculate the total pot
        let playerContributions = calculatePlayerContributions()
        return playerContributions.values.reduce(0, +)
    }
    
    // Helper to calculate Hero PnL
    private func calculateHeroPnL(potAmount: Double, showdown: Bool) -> Double {
        guard let hero = viewModel.players.first(where: { $0.isHero }),
              let heroPosition = hero.position else {
            return 0
        }
        
        // Get hero's total contribution to the pot
        let playerContributions = calculatePlayerContributions()
        let heroContribution = playerContributions[heroPosition] ?? 0
        
        // If hero folded, they lose their contribution
        let allActions = viewModel.preflopActions + viewModel.flopActions + 
                         viewModel.turnActions + viewModel.riverActions
        let heroFolded = allActions.contains { $0.playerName == heroPosition && $0.action == "folds" }
        
        if heroFolded {
            return -heroContribution
        }
        
        // Get folded players
        let folded = Set(allActions.filter { $0.action == "folds" }.map { $0.playerName })
        
        // Get active players at the end
        let activePlayers = viewModel.players
            .filter { $0.position != nil }
            .filter { !folded.contains($0.position!) }
        
        // Hero is the only player left, so won the pot
        if activePlayers.count == 1 && activePlayers.first?.isHero == true {
            return potAmount - heroContribution
        }
        
        // If showdown, compare hands
        if showdown {
            // Get community cards
            let communityCards = [viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3, 
                                viewModel.turnCard, viewModel.riverCard].compactMap { $0 }
            
            // If there are active players with hole cards, determine the winner
            let playersWithCards = activePlayers.filter { player in
                player.card1 != nil && player.card2 != nil
            }
            
            if playersWithCards.count > 1 {
                // Hero must have cards to win at showdown
                if hero.card1 == nil || hero.card2 == nil {
                    return -heroContribution
                }
                
                // Get hero's cards and hand rank
                let heroCards = [hero.card1!, hero.card2!]
                let heroRank = calculateHandRank(holeCards: heroCards, communityCards: communityCards)
                
                // Calculate hand ranks for all active players
                var playerRanks: [(player: PlayerEntry, rank: Int)] = []
                
                for player in playersWithCards {
                    if let card1 = player.card1, let card2 = player.card2 {
                        let cards = [card1, card2]
                        let rank = calculateHandRank(holeCards: cards, communityCards: communityCards)
                        playerRanks.append((player, rank))
                    }
                }
                
                // Find highest rank
                let maxRank = playerRanks.map { $0.rank }.max() ?? 0
                
                // Count players with the best hand (for split pots)
                let bestHandCount = playerRanks.filter { $0.rank == maxRank }.count
                
                // Hero wins or ties for the win
                if heroRank == maxRank {
                    if bestHandCount > 1 {
                        // Split pot - hero gets their share
                        let heroShare = potAmount / Double(bestHandCount)
                        return heroShare - heroContribution
                    } else {
                        // Hero wins the whole pot
                        return potAmount - heroContribution
                    }
                } else {
                    // Hero lost at showdown
                    return -heroContribution
                }
            } else if playersWithCards.count == 1 && playersWithCards.first?.isHero == true {
                // Only hero has cards, so they win
                return potAmount - heroContribution
            } else {
                // No players with cards, can't determine (should not happen)
                return -heroContribution
            }
        }
        
        // Default: hero lost (no showdown, not the only player left)
        return -heroContribution
    }
    
    // Helper to calculate hand rank (higher number = better hand)
    private func calculateHandRank(holeCards: [String], communityCards: [String]) -> Int {
        // This is a simplified ranking system, with higher values being better hands
        // In a real poker hand evaluator, this would be much more sophisticated
        
        // Combine hole cards and community cards
        let allCards = holeCards + communityCards
        
        // Extract ranks and suits
        let ranks = allCards.map { String($0.prefix(1)) }
        let suits = allCards.map { String($0.suffix(1)) }
        
        // Count rank frequencies
        var rankCounts: [String: Int] = [:]
        for rank in ranks {
            rankCounts[rank, default: 0] += 1
        }
        
        // Count suit frequencies
        var suitCounts: [String: Int] = [:]
        for suit in suits {
            suitCounts[suit, default: 0] += 1
        }
        
        // Check for flush (5+ cards of same suit)
        let hasFlush = suitCounts.values.contains { $0 >= 5 }
        
        // Check for pairs, trips, quads
        let pairs = rankCounts.filter { $0.value == 2 }.count
        let trips = rankCounts.filter { $0.value == 3 }.count
        let quads = rankCounts.filter { $0.value == 4 }.count
        
        // Calculate a simple hand rank score (higher is better)
        // This is vastly simplified, a real evaluator would consider all possible 5-card combinations
        var score = 0
        
        // One pair
        if pairs >= 1 {
            score = 100
        }
        
        // Two pair
        if pairs >= 2 {
            score = 200
        }
        
        // Three of a kind
        if trips >= 1 {
            score = 300
        }
        
        // Straight and Flush detection are simplified
        if hasFlush {
            score = 500
        }
        
        // Full house
        if trips >= 1 && pairs >= 1 {
            score = 600
        }
        
        // Four of a kind
        if quads >= 1 {
            score = 700
        }
        
        // Straight flush and royal flush detection omitted for simplicity
        
        // Add some points for high cards (simplified)
        let highCardPoints = calculateHighCardPoints(ranks: ranks)
        score += highCardPoints
        
        return score
    }
    
    // Helper to calculate points for high cards
    private func calculateHighCardPoints(ranks: [String]) -> Int {
        var points = 0
        let rankValues: [String: Int] = [
            "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
            "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14
        ]
        
        for rank in ranks {
            points += rankValues[rank] ?? 0
        }
        
        return points
    }
    
    // Helper to ensure all positions for the table size are filled
    private func ensureAllPositionsFilled() {
        let allPositions = viewModel.positions(for: viewModel.tableSize)
        let existingPositions = Set(viewModel.players.compactMap { $0.position })
        
        // Find missing positions
        let missingPositions = allPositions.filter { !existingPositions.contains($0) }
        
        if !missingPositions.isEmpty {
            // Add auto-folding villains for missing positions
            for position in missingPositions {
                // Create a new villainName
                let villainName = "Villain \(position)"
                
                // Add the player with position
                let autoFoldVillain = PlayerEntry(
                    name: villainName,
                    position: position,
                    stack: viewModel.bigBlind * 100, // Standard 100BB stack
                    isHero: false,
                    card1: nil,
                    card2: nil
                )
                
                viewModel.players.append(autoFoldVillain)
            }
            
            // Ensure preflop action order and folds are correct
            ensureCorrectPreflopActions()
        } else if !viewModel.preflopActions.isEmpty {
            // Also ensure preflop action order when all positions are filled
            ensureCorrectPreflopActions()
        }
    }
    
    // Helper to ensure correct preflop action order with blinds and auto-folds
    private func ensureCorrectPreflopActions() {
        // For proper hand history representation:
        // 1. SB and BB posts are recorded as the first actions
        // 2. Then preflop action starts with UTG (after BB) and continues clockwise
        // 3. Players without explicit actions fold in positional order when their turn comes
        // 4. SB and BB fold when action gets back to them if they didn't act explicitly
        let allPositions = viewModel.positions(for: viewModel.tableSize)
        
        // Don't modify if no actions exist
        if viewModel.preflopActions.isEmpty {
            // If no actions exist, we assume the user will add them
            return
        }
        
        // Create a new properly ordered preflop action list
        var newPreflopActions: [ActionEntry] = []
        
        // 1. Always start with SB and BB posts
        // SB posts small blind (ALWAYS first)
        newPreflopActions.append(ActionEntry(
            playerName: "SB",
            action: "posts",
            amount: viewModel.smallBlind
        ))
        
        // BB posts big blind (ALWAYS second)
        newPreflopActions.append(ActionEntry(
            playerName: "BB",
            action: "posts",
            amount: viewModel.bigBlind
        ))
        
        // 2. Get all user-added actions (excluding any auto-added)
        let userActions = getUserAddedPreflopActions()
        
        // Players who need to be skipped in the auto-fold process
        // These are players who have custom user-added actions 
        var playersWithCustomActions = Set<String>()
        
        // Group user actions by player position
        var actionsByPlayer = [String: [ActionEntry]]()
        for action in userActions {
            if var existing = actionsByPlayer[action.playerName] {
                existing.append(action)
                actionsByPlayer[action.playerName] = existing
            } else {
                actionsByPlayer[action.playerName] = [action]
            }
            
            // Mark this player as having custom actions
            playersWithCustomActions.insert(action.playerName)
        }
        
        // 3. Get proper preflop action order (UTG first, then clockwise)
        let preflopActionOrder = getPreflopActionOrder(positions: allPositions)
        
        // 4. Add actions in order, inserting auto-folds for missing players
        for position in preflopActionOrder {
            if let playerActions = actionsByPlayer[position] {
                // This player has explicit user actions - add them
                newPreflopActions.append(contentsOf: playerActions)
            } else if !playersWithCustomActions.contains(position) {
                // No user actions for this player - add auto-fold
                // Note: We're explicitly adding a fold for EVERY position without custom actions
                newPreflopActions.append(ActionEntry(
                    playerName: position,
                    action: "folds",
                    amount: 0
                ))
            }
        }
        
        // 5. Handle SB and BB folding if they didn't have explicit actions
        // Since the positions were processed in UTG->BTN->SB->BB order, 
        // ensure SB and BB fold if they don't have custom actions
        if !playersWithCustomActions.contains("SB") {
            // Check if we already added a fold for SB in the loop
            if !newPreflopActions.contains(where: { $0.playerName == "SB" && $0.action == "folds" }) {
                // Add SB fold AFTER the SB post
                // Find the correct position based on the UTG->BTN->SB->BB order
                let sbIndex = preflopActionOrder.firstIndex(of: "SB") ?? 0
                let insertionIndex = 2 + sbIndex // 2 blind posts + index in action order
                
                newPreflopActions.insert(ActionEntry(
                    playerName: "SB",
                    action: "folds",
                    amount: 0
                ), at: min(insertionIndex, newPreflopActions.count))
            }
        }
        
        if !playersWithCustomActions.contains("BB") {
            // Check if we already added a fold for BB in the loop
            if !newPreflopActions.contains(where: { $0.playerName == "BB" && $0.action == "folds" }) {
                // Add BB fold AFTER the BB post
                // Find the correct position based on the UTG->BTN->SB->BB order
                let bbIndex = preflopActionOrder.firstIndex(of: "BB") ?? 0
                let insertionIndex = 2 + bbIndex // 2 blind posts + index in action order
                
                newPreflopActions.insert(ActionEntry(
                    playerName: "BB",
                    action: "folds",
                    amount: 0
                ), at: min(insertionIndex, newPreflopActions.count))
            }
        }
        
        // Replace the existing actions with our properly ordered set
        viewModel.preflopActions = newPreflopActions
    }
    
    // Helper to get user-added preflop actions (excluding auto-added blinds/folds)
    private func getUserAddedPreflopActions() -> [ActionEntry] {
        // Get all preflop actions
        let allActions = viewModel.preflopActions
        
        // Filter out the automatic blind posts (SB and BB)
        return allActions.filter { action in
            // Skip standard SB and BB posts with exact blind amounts
            if action.playerName == "SB" && action.action == "posts" && action.amount == viewModel.smallBlind {
                return false
            }
            if action.playerName == "BB" && action.action == "posts" && action.amount == viewModel.bigBlind {
                return false
            }
            
            // Include all other actions
            return true
        }
    }
    
    // Helper to get the proper preflop action order
    private func getPreflopActionOrder(positions: [String]) -> [String] {
        // Hardcoded positions for different table sizes
        let positions2Max = ["SB", "BB"]
        let positions6Max = ["SB", "BB", "UTG", "MP", "CO", "BTN"]
        let positions9Max = ["SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "HJ", "CO", "BTN"]
        
        // Choose the correct position array based on table size
        let tableSize = viewModel.tableSize
        let relevantPositions: [String]
        
        switch tableSize {
        case 2:
            relevantPositions = positions2Max
        case 6:
            relevantPositions = positions6Max
        case 9:
            relevantPositions = positions9Max
        default:
            // Fallback to the passed positions
            relevantPositions = positions
        }
        
        // Find UTG (player after BB) - action starts here preflop
        guard let bbIndex = relevantPositions.firstIndex(of: "BB") else {
            return relevantPositions
        }
        
        // Preflop action starts with UTG and continues clockwise around to BB
        let utgIndex = (bbIndex + 1) % relevantPositions.count
        
        // Create an order that starts with UTG and continues clockwise
        // Full order is: UTG -> ... -> CO -> BTN -> SB -> BB
        return Array(relevantPositions[utgIndex...] + relevantPositions[..<utgIndex])
    }
    
    // Helper to determine the dealer seat
    private func determineDealerSeat() -> Int {
        // Find the BTN player (dealer)
        if let btnPlayer = viewModel.players.firstIndex(where: { $0.position == "BTN" }) {
            return btnPlayer + 1 // Seat numbers are 1-indexed
        }
        
        // If no BTN, find the relative positions
        let positions = viewModel.positions(for: viewModel.tableSize)
        if let btnIndex = positions.firstIndex(of: "BTN") {
            return btnIndex + 1
        }
        
        // Default to 1 if we can't determine
        return 1
    }
    
    // Helper to create the players array
    private func createPlayersArray() -> [Player] {
        // Sort players by position for consistent seat assignment
        let allPositions = viewModel.positions(for: viewModel.tableSize)
        let sortedPlayers = viewModel.players.sorted { player1, player2 in
            guard let pos1 = player1.position, let idx1 = allPositions.firstIndex(of: pos1),
                  let pos2 = player2.position, let idx2 = allPositions.firstIndex(of: pos2) else {
                return false
            }
             return idx1 < idx2
         }
        
        // Convert PlayerEntry to Player
        return sortedPlayers.enumerated().map { index, player in
            Player(
                name: player.name,
                seat: index + 1, // 1-indexed seats
                stack: player.stack,
                position: player.position,
                isHero: player.isHero,
                cards: [player.card1, player.card2].compactMap { $0 },
                finalHand: nil, // Could be determined later
                finalCards: nil
            )
        }
    }
    
    // Helper to create the streets array
    private func createStreetsArray() -> [Street] {
        var streets: [Street] = []
        
        // Preflop actions - we always include preflop
        streets.append(Street(
            name: "preflop",
            cards: [],
            actions: mapActionsToPlayers(viewModel.preflopActions)
        ))
        
        // Flop actions - check if there are flop cards or actions
        let flopCards = [viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3].compactMap { $0 }
        if flopCards.count == 3 {
            streets.append(Street(
                name: "flop",
                cards: flopCards,
                actions: mapActionsToPlayers(viewModel.flopActions)
            ))
            
            // Turn - only if flop exists
            if let turnCard = viewModel.turnCard {
                streets.append(Street(
                    name: "turn",
                    cards: [turnCard],
                    actions: mapActionsToPlayers(viewModel.turnActions)
                ))
                
                // River - only if turn exists
                if let riverCard = viewModel.riverCard {
                    streets.append(Street(
                        name: "river",
                        cards: [riverCard],
                        actions: mapActionsToPlayers(viewModel.riverActions)
                    ))
                }
            }
        }
        
        return streets
    }
    
    // Helper to map ActionEntry to Action, converting position to player name
    private func mapActionsToPlayers(_ actions: [ActionEntry]) -> [Action] {
        return actions.map { entry in
            let playerName = viewModel.players.first { $0.position == entry.playerName }?.name ?? entry.playerName
            return Action(
                playerName: playerName,
                action: entry.action,
                amount: entry.amount,
                cards: nil
            )
        }
    }
    
    // Helper to determine if showdown occurred
    private func determineShowdown() -> Bool {
        // Check if there are multiple players still in the hand at the end
        let lastStreetActions: [ActionEntry]
        
        if !viewModel.riverActions.isEmpty {
            lastStreetActions = viewModel.riverActions
        } else if !viewModel.turnActions.isEmpty {
            lastStreetActions = viewModel.turnActions
        } else if !viewModel.flopActions.isEmpty {
            lastStreetActions = viewModel.flopActions
             } else {
            lastStreetActions = viewModel.preflopActions
        }
        
        // Get folded players
        let folded = Set(viewModel.preflopActions.filter { $0.action == "folds" }.map { $0.playerName } +
                         viewModel.flopActions.filter { $0.action == "folds" }.map { $0.playerName } +
                         viewModel.turnActions.filter { $0.action == "folds" }.map { $0.playerName } +
                         viewModel.riverActions.filter { $0.action == "folds" }.map { $0.playerName })
        
        // Get active players at the end
        let activePlayers = viewModel.players
            .filter { $0.position != nil }
            .filter { !folded.contains($0.position!) }
        
        // If 2+ active players and the last action is a call or check, it's a showdown
        return activePlayers.count > 1 && 
               (lastStreetActions.last?.action == "calls" || lastStreetActions.last?.action == "checks")
    }
}

// MARK: - Utility Extensions

func currencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
        return formatter
}

// Preview
struct ManualHandEntryWizardView_Previews: PreviewProvider {
    static var previews: some View {
        ManualHandEntryWizardView()
            .preferredColorScheme(.dark)
    }
}

