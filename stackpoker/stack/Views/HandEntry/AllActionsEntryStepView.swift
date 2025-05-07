import SwiftUI

struct AllActionsEntryStepView: View {
    @EnvironmentObject var viewModel: HandEntryViewModel
    
    // Local state for this combined view
    @State private var currentPlayerToActionPosition: String? = nil
    
    var body: some View {
        ScrollView {
            // Add extra spacing at the top
            VStack(alignment: .leading, spacing: 20) { 
                // Extra top padding
                
                // Helpful Blurb
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter the actions for each street as they occurred.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    

                }
                .padding(.bottom, 10)
                
                // --- Preflop --- 
                actionsSection(title: "Preflop", actions: $viewModel.preflopActions, isPreflop: true)
                
                // --- Flop --- 
                if viewModel.flopCard1 != nil || viewModel.flopCard2 != nil || viewModel.flopCard3 != nil || !viewModel.flopActions.isEmpty {
                    Divider().padding(.vertical, 10)
                    boardDisplay(cards: [viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3].compactMap { $0 })
                    actionsSection(title: "Flop", actions: $viewModel.flopActions, isPreflop: false)
                }
                
                // --- Turn --- 
                if (viewModel.turnCard != nil || !viewModel.turnActions.isEmpty) && 
                   (viewModel.flopCard1 != nil || viewModel.flopCard2 != nil || viewModel.flopCard3 != nil || !viewModel.flopActions.isEmpty) 
                {
                    Divider().padding(.vertical, 10)
                    boardDisplay(cards: [viewModel.turnCard].compactMap { $0 })
                    actionsSection(title: "Turn", actions: $viewModel.turnActions, isPreflop: false)
                }
                
                // --- River ---
                if (viewModel.riverCard != nil || !viewModel.riverActions.isEmpty) &&
                   (viewModel.turnCard != nil || !viewModel.turnActions.isEmpty)
                {
                     Divider().padding(.vertical, 10)
                     boardDisplay(cards: [viewModel.riverCard].compactMap { $0 })
                     actionsSection(title: "River", actions: $viewModel.riverActions, isPreflop: false)
                }
            }
            .padding() // Padding for the overall content
        }
        .onAppear { updateCurrentPlayerHighlight() } // Initial highlight
    }
    
    // MARK: - Subviews & Helpers for Combined Actions View
    
    // Displays board cards for a given street
    @ViewBuilder
    func boardDisplay(cards: [String]) -> some View {
        if !cards.isEmpty {
             HStack(spacing: 5) {
                 ForEach(cards, id: \.self) { card in
                     Text(card)
                         .font(.system(size: 18, weight: .medium))
                         .foregroundColor(suitColorForCard(card) ?? .white)
                         .frame(width: 35, height: 50)
                         .background(Color.black.opacity(0.3))
                         .cornerRadius(5)
                         .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.2)))
                 }
             }
             .padding(.bottom, 8)
        }
    }
    
    // Reusable section for a street's actions
    func actionsSection(title: String, actions: Binding<[ActionEntry]>, isPreflop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button { addAction(to: actions) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .font(.caption)
            }
            .padding(.bottom, 4)
            
            // Action Rows or Placeholder
            if actions.wrappedValue.isEmpty {
                Text("No actions entered.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 15)
            } else {
                VStack(spacing: 0) {
                    ForEach(actions) { $action in
                        actionRow(action: $action, isPreflop: isPreflop)
                        Divider().background(Color.white.opacity(0.1))
                            .padding(.leading, 10) // Indent divider slightly
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.15))
        .cornerRadius(10)
    }

    // Individual Action Row (similar to previous ActionEntryStepView)
    func actionRow(action: Binding<ActionEntry>, isPreflop: Bool) -> some View {
        let isCurrentPlayer = action.playerName.wrappedValue == currentPlayerToActionPosition
        let streetActions = currentActions(for: action.wrappedValue) // Get actions for the specific street
        
        return HStack(spacing: 8) {
             playerPicker(action: action)
             actionTypePicker(action: action, streetActions: streetActions, isPreflop: isPreflop)
             amountField(action: action, streetActions: streetActions)
             Spacer(minLength: 4)
             removeButton(action: action)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isCurrentPlayer ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.1) : Color.clear)
        .cornerRadius(isCurrentPlayer ? 6 : 0)
        .animation(.easeInOut(duration: 0.2), value: isCurrentPlayer)
    }
    
    // --- Action Row Helper Subviews ---
    
    // Remove @ViewBuilder if not strictly necessary for these simple views
    private func playerPicker(action: Binding<ActionEntry>) -> some View {
        // Using active positions from the ViewModel now
        HStack(spacing: 2) {
            // Dealer button indicator for BTN position
            if action.playerName.wrappedValue == "BTN" {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                    Text("D")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                }
                .offset(x: -2, y: 0)
            }
            
            Picker("Player", selection: action.playerName) {
                // Allow all players to be selected
                ForEach(activePlayerPositionsForPicker(), id: \.self) { pos in
                    HStack {
                        // Show SB or BB indicator for blinds
                        if pos == "SB" || pos == "BB" {
                            Circle()
                                .fill(pos == "SB" ? Color.yellow.opacity(0.7) : Color.red.opacity(0.7))
                                .frame(width: 8, height: 8)
                        }
                        
                        // Show dealer button indicator
                        if pos == "BTN" {
                            Circle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 8, height: 8)
                        }
                        
                        let name = viewModel.players.first { $0.position == pos }?.name ?? pos
                        Text(name == "Hero" ? "Hero" : pos).tag(pos)
                    }
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 74)
            .tint(.gray)
        }
        .frame(width: 80)
        .onAppear {
            // Ensure player has a valid position on initial appearance
            if action.playerName.wrappedValue.isEmpty {
                let positions = activePlayerPositionsForPicker()
                if !positions.isEmpty {
                    action.playerName.wrappedValue = positions.first!
                }
            }
        }
    }
    
    // Show styled action based on type
    private func actionTypePicker(action: Binding<ActionEntry>, streetActions: [ActionEntry], isPreflop: Bool) -> some View {
        // Get legal actions for this player and always ensure we have a valid action selected
        var currentStreetActions = streetActions
        
        // Filter to only include actions before this one
        if let actionIndex = currentStreetActions.firstIndex(where: { $0.id == action.id.wrappedValue }) {
            currentStreetActions = Array(currentStreetActions[..<actionIndex])
        }
        
        // Handle first preflop action specially
        var legalActions: [String]
        if isPreflop && currentStreetActions.isEmpty {
            // First preflop action is ALWAYS fold/call/raise
            legalActions = ["folds", "calls", "raises"]
        } else {
            // Normal action selection based on betting rules
            legalActions = viewModel.getLegalActions(for: currentStreetActions, playerPosition: action.playerName.wrappedValue)
        }
        
        return Picker("Action", selection: action.action) {
            ForEach(legalActions, id: \.self) { actionName in
                HStack {
                    // Show special styling for key actions
                    switch actionName {
                    case "folds":
                        Circle()
                            .fill(Color.red.opacity(0.6))
                            .frame(width: 8, height: 8)
                    case "calls":
                        Circle()
                            .fill(Color.green.opacity(0.6))
                            .frame(width: 8, height: 8)
                    case "raises":
                        Circle()
                            .fill(Color.purple.opacity(0.6))
                            .frame(width: 8, height: 8)
                    default:
                        EmptyView()
                    }
                    
                    Text(actionName.capitalized).tag(actionName)
                }
            }
        }
        .pickerStyle(MenuPickerStyle())
        .frame(minWidth: 80)
        .tint(.gray)
        .onChange(of: action.action.wrappedValue) { newValue in
            handleActionTypeChange(action: action, newValue: newValue, streetActions: streetActions)
        }
        .onChange(of: action.playerName.wrappedValue) { newPlayer in
            // Update legal actions when player changes, ensuring preflop rules are followed
            updateActionForNewPlayer(action: action, player: newPlayer, streetActions: streetActions, isPreflop: isPreflop)
        }
        .onAppear {
            // Ensure the selected action is legal on first appearance
            if !legalActions.contains(action.action.wrappedValue) {
                action.action.wrappedValue = legalActions.first ?? "folds" // Default to first legal action
                // Also update amount if needed for this action
                handleActionTypeChange(action: action, newValue: action.action.wrappedValue, streetActions: streetActions)
            }
        }
    }

    // Helper method to determine if this is the first real preflop action (after SB/BB posts)
    private func isFirstRealPreFlopAction(action: Binding<ActionEntry>, currentStreetActions: [ActionEntry]) -> Bool {
        // In the UI, we don't show blind posts
        // So the first action in preflop is always the first real action
        return isPreflop(streetActions: currentStreetActions) && currentStreetActions.isEmpty
    }

    // Helper to update action type when player changes
    private func updateActionForNewPlayer(action: Binding<ActionEntry>, player: String, streetActions: [ActionEntry], isPreflop: Bool) {
        var legalActions: [String]
        
        if isPreflop && streetActions.isEmpty {
            // First preflop action always has fold/call/raise options
            legalActions = ["folds", "calls", "raises"]
        } else {
            legalActions = viewModel.getLegalActions(for: streetActions, playerPosition: player)
        }
        
        // If current action isn't legal for this player, select the first legal action
        if !legalActions.contains(action.action.wrappedValue) {
            action.action.wrappedValue = legalActions.first ?? "folds"
            // Also update amount if needed for this action
            handleActionTypeChange(action: action, newValue: action.action.wrappedValue, streetActions: streetActions)
        }
    }

    // @ViewBuilder removed: this returns a single Group view
    @ViewBuilder
    private func amountField(action: Binding<ActionEntry>, streetActions: [ActionEntry]) -> some View {
        let isAmountEditable = ["bets", "raises"].contains(action.action.wrappedValue)
        let isDisabled = ["folds", "checks", "calls"].contains(action.action.wrappedValue)

        return Group { // Use Group to return one view type
            if ["bets", "raises", "calls"].contains(action.action.wrappedValue) {
                HStack(spacing: 2) {
                    Text("$").font(.caption).foregroundColor(.gray)
                    TextField("Amt", value: action.amount, formatter: currencyFormatter()) 
                        .keyboardType(.decimalPad)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(isDisabled ? .gray : .white)
                        .frame(width: 50)
                        .disabled(isDisabled) // Disable for non-manual amounts
                        .opacity(isDisabled ? 0.6 : 1.0) // Dim if disabled
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.2))
                .cornerRadius(5)
                .fixedSize(horizontal: true, vertical: false)
           } else {
                // Keep layout consistent even when field is hidden
                Spacer().frame(width: 60) 
           }
       }
    }

    private func removeButton(action: Binding<ActionEntry>) -> some View {
        Button { removeAction(id: action.id.wrappedValue) } label: {
             Image(systemName: "minus.circle") // Use minus for less aggressive look
                 .foregroundColor(.red.opacity(0.6))
                 .font(.body) // Slightly smaller
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // --- Logic Helpers --- 
    
    func activePlayerPositionsForPicker() -> [String] {
         // Include ALL player positions, even folded ones, so they can be selected in actions
         let allPositions = viewModel.players
                    .filter { $0.position != nil }
                    .compactMap { $0.position }
         let fullOrder = viewModel.positions(for: viewModel.tableSize)
         return allPositions.sorted { (pos1, pos2) -> Bool in
              (fullOrder.firstIndex(of: pos1) ?? -1) < (fullOrder.firstIndex(of: pos2) ?? -1)
          }
    }

    func handleActionTypeChange(action: Binding<ActionEntry>, newValue: String, streetActions: [ActionEntry]) {
        let position = action.playerName.wrappedValue
        if newValue == "folds" {
            viewModel.foldedPlayerPositions.insert(position)
        } else {
            // Note: We don't automatically un-fold if action changes
        }
        
        // Autofill amount based on action type
        if newValue == "checks" || newValue == "folds" {
            action.amount.wrappedValue = 0
        } else if newValue == "calls" {
            // Get a filtered version of street actions up to this point
            var currentStreetActions = streetActions
            if let actionIndex = streetActions.firstIndex(where: { $0.id == action.id.wrappedValue }) {
                currentStreetActions = Array(streetActions[..<actionIndex])
            }
            // Calculate call amount based on current state
            action.amount.wrappedValue = viewModel.calculateCallAmount(for: streetActions, playerPosition: position)
        }
        updateCurrentPlayerHighlight()
    }

    func addAction(to actions: Binding<[ActionEntry]>) {
        // Handle regular actions - determine next player
        let nextPlayerPos = determineNextPlayerPosition(
            lastActionPos: actions.wrappedValue.last?.playerName, 
            currentStreetActions: actions.wrappedValue
        )
        
        // First valid position to act should never be SB or BB for manually added actions
        // (blinds are posted automatically and are not part of the user-added actions)
        var validPosition = nextPlayerPos.isEmpty ? 
            (activePlayerPositionsForPicker().first ?? "BB") : nextPlayerPos
            
        // For the first preflop action, make sure we start with UTG not a blind position
        let isFirstPreflopAction = isPreflop(streetActions: actions.wrappedValue) && actions.wrappedValue.isEmpty
        if isFirstPreflopAction {
            // Ensure we don't start with blinds for preflop action
            let allPositions = viewModel.positions(for: viewModel.tableSize)
            if validPosition == "SB" || validPosition == "BB" {
                // Find UTG (position after BB) or any non-blind position
                if let bbIndex = allPositions.firstIndex(of: "BB") {
                    let utgIndex = (bbIndex + 1) % allPositions.count
                    validPosition = allPositions[utgIndex]
                } else if let nonBlindPos = allPositions.first(where: { $0 != "SB" && $0 != "BB" }) {
                    validPosition = nonBlindPos
                }
            }
        }
                                  
        // Determine which actions are legal for this player
        let initialLegalActions: [String]
        if isFirstPreflopAction {
            // First preflop action is ALWAYS fold/call/raise
            initialLegalActions = ["folds", "calls", "raises"]
        } else {
            initialLegalActions = viewModel.getLegalActions(for: actions.wrappedValue, playerPosition: validPosition)
        }
        
        let initialAction = initialLegalActions.first ?? "checks"
        
        // Calculate amount for the action
        let actionAmount: Double
        if initialAction == "calls" {
            actionAmount = viewModel.calculateCallAmount(for: actions.wrappedValue, playerPosition: validPosition)
        } else {
            actionAmount = 0 // Default for folds, checks, etc.
        }
        
        // Add the action
        actions.wrappedValue.append(ActionEntry(
            playerName: validPosition,
            action: initialAction,
            amount: actionAmount
        ))
        
        updateCurrentPlayerHighlight()
    }
    
    // Remove by ID
    func removeAction(id: UUID) {
        viewModel.preflopActions.removeAll { $0.id == id }
        viewModel.flopActions.removeAll { $0.id == id }
        viewModel.turnActions.removeAll { $0.id == id }
        viewModel.riverActions.removeAll { $0.id == id }
        updateCurrentPlayerHighlight()
    }
    
    // Determines and updates the local state for the next player highlight
    func updateCurrentPlayerHighlight() {
         // Consider all actions entered so far to find the true last player
         let allEnteredActions = viewModel.preflopActions + viewModel.flopActions + viewModel.turnActions + viewModel.riverActions
         currentPlayerToActionPosition = determineNextPlayerPosition(lastActionPos: allEnteredActions.last?.playerName, currentStreetActions: []) // Pass empty array or determine current street if needed for context
    }
    
    // Logic to determine next player (uses global folded state)
    // This is now used primarily for defaulting the *next* action's player
    func determineNextPlayerPosition(lastActionPos: String?, currentStreetActions: [ActionEntry]) -> String {
         let allPositions = viewModel.positions(for: viewModel.tableSize)
         guard !allPositions.isEmpty else { return viewModel.players.first?.position ?? "" }
         
         // Get positions that still have players
         let existingPositions = allPositions.filter { pos in
             viewModel.players.contains(where: { $0.position == pos })
         }
         
         // Track who has folded in this street
         let foldedInThisStreet = Set(currentStreetActions.filter { $0.action == "folds" }.map { $0.playerName })
         
         // For multiway pots, we need to track who has already acted in this round of betting
         let lastBetRaiseIndex = currentStreetActions.lastIndex(where: { $0.action == "bets" || $0.action == "raises" })
         
         // Get all actions after the last bet/raise (the current betting round)
         let actionsInCurrentRound: [ActionEntry]
         if let lastBetIndex = lastBetRaiseIndex {
             actionsInCurrentRound = Array(currentStreetActions[(lastBetIndex+1)...])
         } else {
             actionsInCurrentRound = currentStreetActions
         }
         
         // Players who have acted in the current round of betting
         let playersActedInCurrentRound = Set(actionsInCurrentRound.map { $0.playerName })
         
         // Active players who haven't folded in this street
         let activePositions = existingPositions.filter { !foldedInThisStreet.contains($0) }
         
         // If no one has bet/raised yet, we're just going in normal rotating order
         if lastBetRaiseIndex == nil {
             // Standard rotation - find the next player after the last one who acted
             if let lastPos = lastActionPos, let lastIndex = activePositions.firstIndex(of: lastPos) {
                 let nextIndex = (lastIndex + 1) % activePositions.count
                 return activePositions[nextIndex]
             } else {
                 // No last action, determine first player based on street
                 let streetTitle = self.streetTitle(for: currentStreetActions)
                 let startingPosition = (streetTitle == "Preflop") ? getPositionAfterBB(allPositions) : "SB"
                 return getNextPlayerStartingFrom(position: startingPosition, positions: activePositions)
             }
         } else {
             // Someone has bet/raised - we need to make sure everyone gets to act
             
             // Find positions that still need to act (haven't acted since the last bet/raise)
             let positionsNeedingAction = activePositions.filter { !playersActedInCurrentRound.contains($0) }
             
             if positionsNeedingAction.isEmpty {
                 // Everyone has acted - betting round is complete
                 // Go to the next player after the aggressor for the next round
                 if lastBetRaiseIndex != nil {
                     let lastBetAction = currentStreetActions[lastBetRaiseIndex!]
                     let lastBetPos = lastBetAction.playerName
                     if let aggressorIndex = activePositions.firstIndex(of: lastBetPos) {
                         let nextIndex = (aggressorIndex + 1) % activePositions.count
                         return activePositions[nextIndex]
                     }
                 }
                 // Fallback to normal order if we can't find the aggressor
                 return activePositions.first ?? existingPositions.first ?? ""
             } else {
                 // Still have players who need to act in this betting round
                 if lastActionPos != nil {
                     // Find the next player who needs to act, in position
                     var currentIndex = allPositions.firstIndex(of: lastActionPos!) ?? 0
                     for _ in 0..<allPositions.count {
                         currentIndex = (currentIndex + 1) % allPositions.count
                         let nextPos = allPositions[currentIndex]
                         if positionsNeedingAction.contains(nextPos) {
                             return nextPos
                         }
                     }
                 }
                 
                 // No last action or couldn't find next - find the first player who needs to act
                 return positionsNeedingAction.first ?? activePositions.first ?? ""
             }
         }
     }
     
     // Helper to find the position after BB
     private func getPositionAfterBB(_ positions: [String]) -> String {
         if let bbIndex = positions.firstIndex(of: "BB") {
             let nextIndex = (bbIndex + 1) % positions.count
             return positions[nextIndex]
         }
         return positions.first ?? ""
     }

     // Helper to find next player starting from a specific position
     private func getNextPlayerStartingFrom(position: String, positions: [String]) -> String {
         if positions.isEmpty { return position }
         
         if positions.contains(position) {
             return position
         }
         
         // Find the next valid position in the ordering
         let allPositions = viewModel.positions(for: viewModel.tableSize)
         if let startIndex = allPositions.firstIndex(of: position) {
             var currentIndex = startIndex
             for _ in 0..<allPositions.count {
                 currentIndex = (currentIndex + 1) % allPositions.count
                 if positions.contains(allPositions[currentIndex]) {
                     return allPositions[currentIndex]
                 }
             }
         }
         
         // Fallback to first position if we can't find a match
         return positions.first ?? position
     }

    // Helper needed for determineNextPlayerPosition
    private func streetTitle(for actions: [ActionEntry]) -> String {
        // This comparison won't work reliably across structs/bindings.
        // We need a different way to know the current street context within determineNextPlayerPosition,
        // or simplify the starting logic.
        // For now, default to SB for postflop as an approximation.
        if actions.isEmpty && (viewModel.flopCard1 != nil || viewModel.flopActions.isEmpty) { return "Flop" } // Crude check
        if actions.isEmpty && (viewModel.turnCard != nil || viewModel.turnActions.isEmpty) { return "Turn" } 
        if actions.isEmpty && (viewModel.riverCard != nil || viewModel.riverActions.isEmpty) { return "River" } 
        return "Preflop" // Default assumption
    }

    // Helper to get the correct actions array based on the action entry
    private func currentActions(for actionEntry: ActionEntry) -> [ActionEntry] {
        if viewModel.preflopActions.contains(where: { $0.id == actionEntry.id }) { return viewModel.preflopActions }
        if viewModel.flopActions.contains(where: { $0.id == actionEntry.id }) { return viewModel.flopActions }
        if viewModel.turnActions.contains(where: { $0.id == actionEntry.id }) { return viewModel.turnActions }
        if viewModel.riverActions.contains(where: { $0.id == actionEntry.id }) { return viewModel.riverActions }
        return [] // Should not happen
    }

    // Helper to determine if these are preflop actions
    private func isPreflop(streetActions: [ActionEntry]) -> Bool {
        return streetActions == viewModel.preflopActions
    }
}

// Add Extensions for convenience
extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool {
        return self?.isEmpty ?? true
    }
}

struct AllActionsEntryStepView_Previews: PreviewProvider {
    static var previews: some View {
         NavigationView {
             AllActionsEntryStepView()
                 .environmentObject(HandEntryViewModel())
                 .background(AppBackgroundView())
                 .navigationTitle("Actions")
         }
         .preferredColorScheme(.dark)
    }
} 
