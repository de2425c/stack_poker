import SwiftUI

struct HandSummaryDisplay: View {
    @Binding var hand: ParsedHandHistory
    @State private var viewMode: ViewMode = .preview
    @State private var isReplayActive = false
    
    enum ViewMode {
        case preview, edit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // View mode selector
            HStack {
                Picker("View Mode", selection: $viewMode) {
                    Text("Preview").tag(ViewMode.preview)
                    Text("Edit Details").tag(ViewMode.edit)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
            }
            .padding(.bottom, 5)
            
            if viewMode == .preview {
                // Preview Mode
                previewModeView
            } else {
                // Edit Mode - original detailed editor
                editModeView
            }
        }
    }
    
    var previewModeView: some View {
        ZStack {
            // Background
            Color(red: 0.09, green: 0.09, blue: 0.11)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Hero results card
                VStack(spacing: 16) {
                    // Pot amount and hero result
                    HStack(spacing: 40) {
                        // Total pot
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TOTAL POT")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text("$\(Int(hand.raw.pot.amount))")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // Hero result
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("HERO RESULT")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text(hand.raw.pot.heroPnl >= 0 ? "+$\(Int(hand.raw.pot.heroPnl))" : "-$\(abs(Int(hand.raw.pot.heroPnl)))")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(hand.raw.pot.heroPnl >= 0 ? 
                                                Color(red: 0.3, green: 0.8, blue: 0.3) : 
                                                Color(red: 0.9, green: 0.2, blue: 0.2))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    // Blinds display
                    HStack {
                        Text("\(hand.raw.gameInfo.tableSize)-max • $\(Int(hand.raw.gameInfo.smallBlind))/$\(Int(hand.raw.gameInfo.bigBlind))")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Community cards if available
                    if !getAllCommunityCards().isEmpty {
                        HStack(spacing: 5) {
                            ForEach(getAllCommunityCards(), id: \.self) { card in
                                PokerCardView(card: card)
                                    .frame(width: 40, height: 56)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    
                    // Display winner if available
                    if let distribution = hand.raw.pot.distribution, !distribution.isEmpty {
                        VStack(spacing: 6) {
                            Text("WINNER\(distribution.count > 1 ? "S" : "")")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            ForEach(distribution, id: \.playerName) { winner in
                                HStack(spacing: 8) {
                                    Text(winner.playerName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    Text("$\(Int(winner.amount))")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.3))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                    
                    // Watch hand replay button
                    Button(action: {
                        isReplayActive = true
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                            Text("WATCH HAND REPLAY")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.6, blue: 0.3),
                                    Color(red: 0.1, green: 0.5, blue: 0.2)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .fullScreenCover(isPresented: $isReplayActive) {
                        HandReplayView(hand: hand)
                    }
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.18),
                            Color(red: 0.12, green: 0.12, blue: 0.15)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
        }
    }
    
    var editModeView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Game Info - Collapsible
            CollapsibleSection(title: "Game Info", icon: "info.circle.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    EditableInfoRow(label: "Table Size", value: Binding(
                        get: { "\(hand.raw.gameInfo.tableSize)" },
                        set: { newValue in
                            if let intValue = Int(newValue) {
                                // Create a new GameInfo with updated tableSize
                                let updatedGameInfo = GameInfo(
                                    tableSize: intValue,
                                    smallBlind: hand.raw.gameInfo.smallBlind,
                                    bigBlind: hand.raw.gameInfo.bigBlind,
                                    dealerSeat: hand.raw.gameInfo.dealerSeat
                                )
                                
                                // Create a new RawHandHistory with the updated GameInfo
                                let updatedRaw = RawHandHistory(
                                    gameInfo: updatedGameInfo,
                                    players: hand.raw.players,
                                    streets: hand.raw.streets,
                                    pot: hand.raw.pot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        }
                    ), icon: "person.3")
                    
                    EditableInfoRow(label: "Small Blind", value: Binding(
                        get: { "\(Int(hand.raw.gameInfo.smallBlind))" },
                        set: { newValue in
                            if let doubleValue = Double(newValue) {
                                // Create a new GameInfo with updated smallBlind
                                let updatedGameInfo = GameInfo(
                                    tableSize: hand.raw.gameInfo.tableSize,
                                    smallBlind: doubleValue,
                                    bigBlind: hand.raw.gameInfo.bigBlind,
                                    dealerSeat: hand.raw.gameInfo.dealerSeat
                                )
                                
                                // Create a new RawHandHistory with the updated GameInfo
                                let updatedRaw = RawHandHistory(
                                    gameInfo: updatedGameInfo,
                                    players: hand.raw.players,
                                    streets: hand.raw.streets,
                                    pot: hand.raw.pot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        }
                    ), icon: "dollarsign.circle")
                    
                    EditableInfoRow(label: "Big Blind", value: Binding(
                        get: { "\(Int(hand.raw.gameInfo.bigBlind))" },
                        set: { newValue in
                            if let doubleValue = Double(newValue) {
                                // Create a new GameInfo with updated bigBlind
                                let updatedGameInfo = GameInfo(
                                    tableSize: hand.raw.gameInfo.tableSize,
                                    smallBlind: hand.raw.gameInfo.smallBlind,
                                    bigBlind: doubleValue,
                                    dealerSeat: hand.raw.gameInfo.dealerSeat
                                )
                                
                                // Create a new RawHandHistory with the updated GameInfo
                                let updatedRaw = RawHandHistory(
                                    gameInfo: updatedGameInfo,
                                    players: hand.raw.players,
                                    streets: hand.raw.streets,
                                    pot: hand.raw.pot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        }
                    ), icon: "dollarsign.circle.fill")
                    
                    EditableInfoRow(label: "Dealer Seat", value: Binding(
                        get: { "\(hand.raw.gameInfo.dealerSeat)" },
                        set: { newValue in
                            if let intValue = Int(newValue) {
                                // Create a new GameInfo with updated dealerSeat
                                let updatedGameInfo = GameInfo(
                                    tableSize: hand.raw.gameInfo.tableSize,
                                    smallBlind: hand.raw.gameInfo.smallBlind,
                                    bigBlind: hand.raw.gameInfo.bigBlind,
                                    dealerSeat: intValue
                                )
                                
                                // Create a new RawHandHistory with the updated GameInfo
                                let updatedRaw = RawHandHistory(
                                    gameInfo: updatedGameInfo,
                                    players: hand.raw.players,
                                    streets: hand.raw.streets,
                                    pot: hand.raw.pot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        }
                    ), icon: "person.badge.key")
                }
            }
            
            // Players - Collapsible
            CollapsibleSection(title: "Players", icon: "person.2.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(hand.raw.players.indices, id: \.self) { index in
                        PlayerRowView(
                            player: hand.raw.players[index],
                            onUpdate: { updatedPlayer in
                                var newPlayers = hand.raw.players
                                newPlayers[index] = updatedPlayer
                                
                                // Create a new RawHandHistory with updated players
                                let updatedRaw = RawHandHistory(
                                    gameInfo: hand.raw.gameInfo,
                                    players: newPlayers,
                                    streets: hand.raw.streets,
                                    pot: hand.raw.pot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        )
                    }
                }
            }
            
            // Streets - Collapsible
            CollapsibleSection(title: "Streets", icon: "arrow.forward.circle.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(hand.raw.streets.indices, id: \.self) { index in
                        StreetView(
                            street: hand.raw.streets[index],
                            onUpdate: { updatedStreet in
                                var newStreets = hand.raw.streets
                                newStreets[index] = updatedStreet
                                
                                // Create a new RawHandHistory with updated streets
                                let updatedRaw = RawHandHistory(
                                    gameInfo: hand.raw.gameInfo,
                                    players: hand.raw.players,
                                    streets: newStreets,
                                    pot: hand.raw.pot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        )
                    }
                }
            }
            
            // Pot - Collapsible
            CollapsibleSection(title: "Pot", icon: "dollarsign.square.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    EditableInfoRow(label: "Total Amount", value: Binding(
                        get: { "\(Int(hand.raw.pot.amount))" },
                        set: { newValue in
                            if let doubleValue = Double(newValue) {
                                // Create a new Pot with updated amount
                                let updatedPot = Pot(
                                    amount: doubleValue,
                                    distribution: hand.raw.pot.distribution,
                                    heroPnl: hand.raw.pot.heroPnl
                                )
                                
                                // Create a new RawHandHistory with the updated Pot
                                let updatedRaw = RawHandHistory(
                                    gameInfo: hand.raw.gameInfo,
                                    players: hand.raw.players,
                                    streets: hand.raw.streets,
                                    pot: updatedPot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        }
                    ), icon: "dollarsign.circle")
                    
                    EditableInfoRow(label: "Hero P/L", value: Binding(
                        get: { "\(Int(hand.raw.pot.heroPnl))" },
                        set: { newValue in
                            if let doubleValue = Double(newValue) {
                                // Create a new Pot with updated heroPnl
                                let updatedPot = Pot(
                                    amount: hand.raw.pot.amount,
                                    distribution: hand.raw.pot.distribution,
                                    heroPnl: doubleValue
                                )
                                
                                // Create a new RawHandHistory with the updated Pot
                                let updatedRaw = RawHandHistory(
                                    gameInfo: hand.raw.gameInfo,
                                    players: hand.raw.players,
                                    streets: hand.raw.streets,
                                    pot: updatedPot,
                                    showdown: hand.raw.showdown
                                )
                                
                                // Update the hand with the new RawHandHistory
                                hand = ParsedHandHistory(raw: updatedRaw)
                            }
                        }
                    ), icon: "arrow.up.right.square")
                    
                    if let distribution = hand.raw.pot.distribution, !distribution.isEmpty {
                        Text("Winners")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        
                        ForEach(distribution.indices, id: \.self) { index in
                            PotDistributionView(
                                distribution: distribution[index],
                                onUpdate: { updatedDistribution in
                                    var newDistribution = distribution
                                    newDistribution[index] = updatedDistribution
                                    
                                    // Create a new Pot with updated distribution
                                    let updatedPot = Pot(
                                        amount: hand.raw.pot.amount,
                                        distribution: newDistribution,
                                        heroPnl: hand.raw.pot.heroPnl
                                    )
                                    
                                    // Create a new RawHandHistory with the updated Pot
                                    let updatedRaw = RawHandHistory(
                                        gameInfo: hand.raw.gameInfo,
                                        players: hand.raw.players,
                                        streets: hand.raw.streets,
                                        pot: updatedPot,
                                        showdown: hand.raw.showdown
                                    )
                                    
                                    // Update the hand with the new RawHandHistory
                                    hand = ParsedHandHistory(raw: updatedRaw)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    // Helper function to get all community cards
    private func getAllCommunityCards() -> [String] {
        var allCards: [String] = []
        for street in hand.raw.streets {
            allCards.append(contentsOf: street.cards)
        }
        return allCards
    }
}

struct PlayerRowView: View {
    let player: Player
    let onUpdate: (Player) -> Void
    
    @State private var playerName: String
    @State private var seat: String
    @State private var position: String
    @State private var stack: String
    @State private var cards: [String]
    @State private var isExpanded: Bool = false
    
    init(player: Player, onUpdate: @escaping (Player) -> Void) {
        self.player = player
        self.onUpdate = onUpdate
        
        _playerName = State(initialValue: player.name)
        _seat = State(initialValue: "\(player.seat)")
        _position = State(initialValue: player.position ?? "")
        _stack = State(initialValue: "\(Int(player.stack))")
        _cards = State(initialValue: player.cards ?? [])
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row with basic info
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                            HStack {
                    // Player name and hero badge
                    HStack(spacing: 6) {
                        TextField("Name", text: $playerName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .onChange(of: playerName) { newValue in 
                                updatePlayer()
                            }
                        
                        if player.isHero {
                            Text("Hero")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .cornerRadius(10)
                        }
                    }
                    
                                Spacer()
                    
                    // Position and seat
                    HStack(spacing: 12) {
                        if !position.isEmpty {
                            Menu {
                                Button("SB") { updatePosition("SB") }
                                Button("BB") { updatePosition("BB") }
                                Button("UTG") { updatePosition("UTG") }
                                Button("MP") { updatePosition("MP") }
                                Button("HJ") { updatePosition("HJ") }
                                Button("CO") { updatePosition("CO") }
                                Button("BTN") { updatePosition("BTN") }
                            } label: {
                                Text(position)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(5)
                            }
                        }
                        
                        Text("Seat \(seat)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                        
                        // Cards preview
                        if !cards.isEmpty {
                            HStack(spacing: -6) {
                                ForEach(cards.indices, id: \.self) { index in
                                    PokerCardView(card: cards[index])
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded details
            if isExpanded {
                VStack(spacing: 10) {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    // Cards editor
                    HStack {
                        Text("Cards:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            ForEach(cards.indices, id: \.self) { index in
                                TextField("", text: Binding(
                                    get: { cards[index] },
                                    set: { 
                                        cards[index] = $0
                                        updatePlayer()
                                    }
                                ))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(
                                    (cards[index].hasSuffix("h") || cards[index].hasSuffix("d")) 
                                    ? .red : .white
                                )
                                .frame(width: 32, height: 32)
                                .multilineTextAlignment(.center)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            (cards[index].hasSuffix("h") || cards[index].hasSuffix("d")) 
                                            ? Color.red.opacity(0.5) : Color.gray.opacity(0.5), 
                                            lineWidth: 1
                                        )
                                )
                            }
                        }
                    }
                    
                    // Position and seat editor
                    HStack(spacing: 20) {
                        HStack {
                            Text("Position:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Menu {
                                Button("SB") { updatePosition("SB") }
                                Button("BB") { updatePosition("BB") }
                                Button("UTG") { updatePosition("UTG") }
                                Button("MP") { updatePosition("MP") }
                                Button("HJ") { updatePosition("HJ") }
                                Button("CO") { updatePosition("CO") }
                                Button("BTN") { updatePosition("BTN") }
                                Button("Clear") { updatePosition("") }
                            } label: {
                                Text(position.isEmpty ? "Select" : position)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .frame(width: 50)
                                    .padding(4)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                    )
                            }
                        }
                        
                        HStack {
                            Text("Seat:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Menu {
                                ForEach(1...10, id: \.self) { seatNum in
                                    Button("\(seatNum)") { 
                                        seat = "\(seatNum)"
                                        updatePlayer()
                                    }
                                }
                            } label: {
                                TextField("Seat", text: $seat)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .frame(width: 40)
                                    .multilineTextAlignment(.center)
                                    .padding(4)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                    )
                                    .onChange(of: seat) { newValue in
                                        updatePlayer()
                                    }
                            }
                        }
                    }
                    
                    // Stack editor
                    HStack {
                        Text("Stack:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        HStack(spacing: 0) {
                            Text("$")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                            
                            TextField("Amount", text: $stack)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                                .padding(4)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                .onChange(of: stack) { newValue in
                                    updatePlayer()
                                }
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.16, green: 0.16, blue: 0.22),
                        Color(red: 0.12, green: 0.12, blue: 0.16)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(player.isHero ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.4) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func updatePosition(_ newPosition: String) {
        position = newPosition
        updatePlayer()
    }
    
    private func updatePlayer() {
        let updatedPlayer = Player(
            name: playerName,
            seat: Int(seat) ?? player.seat,
            stack: Double(stack) ?? player.stack,
            position: position.isEmpty ? nil : position,
            isHero: player.isHero,
            cards: cards,
            finalHand: player.finalHand,
            finalCards: player.finalCards
        )
        
        onUpdate(updatedPlayer)
    }
}

struct StreetView: View {
    let street: Street
    let onUpdate: (Street) -> Void
    
    @State private var streetName: String
    @State private var cards: [String]
    @State private var actions: [Action]
    @State private var isExpanded: Bool = true
    @State private var editingActionIndex: Int? = nil
    
    init(street: Street, onUpdate: @escaping (Street) -> Void) {
        self.street = street
        self.onUpdate = onUpdate
        
        _streetName = State(initialValue: street.name)
        _cards = State(initialValue: street.cards)
        _actions = State(initialValue: street.actions)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Street header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    // Street name
                    Menu {
                        Button("Preflop") { selectStreetName("Preflop") }
                        Button("Flop") { selectStreetName("Flop") }
                        Button("Turn") { selectStreetName("Turn") }
                        Button("River") { selectStreetName("River") }
                    } label: {
                        Text(streetName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Cards display
                    if !cards.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(cards.indices, id: \.self) { index in
                                PokerCardView(card: cards[index])
                            }
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                // Card editor
                if !cards.isEmpty {
                    HStack {
                        Text("Cards:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 60, alignment: .leading)
                        
                        HStack(spacing: 6) {
                            ForEach(cards.indices, id: \.self) { index in
                                TextField("", text: Binding(
                                    get: { cards[index] },
                                    set: { 
                                        cards[index] = $0
                                        updateStreet()
                                    }
                                ))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(
                                    (cards[index].hasSuffix("h") || cards[index].hasSuffix("d")) 
                                    ? .red : .white
                                )
                                .frame(width: 32, height: 32)
                                .multilineTextAlignment(.center)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            (cards[index].hasSuffix("h") || cards[index].hasSuffix("d")) 
                                            ? Color.red.opacity(0.5) : Color.gray.opacity(0.5), 
                                            lineWidth: 1
                                        )
                                )
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                
                // Actions
                VStack(spacing: 0) {
                    // Actions header
                    HStack {
                        Text("Actions")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                let newAction = Action(
                                    playerName: "",
                                    action: "calls",
                                    amount: 0,
                                    cards: []
                                )
                                actions.append(newAction)
                                editingActionIndex = actions.count - 1
                                updateStreet()
                            }
                        }) {
                            Label("Add", systemImage: "plus.circle.fill")
                                .font(.system(size: 14))
                                        .foregroundColor(.green)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 8)
                    
                    if !actions.isEmpty {
                        VStack(spacing: 0) {
                            // Actions table header
                            HStack {
                                Text("#")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                                    .frame(width: 30, alignment: .center)
                                
                                Text("Player")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                
                                Text("Action")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                                    .frame(width: 80, alignment: .center)
                                
                                Text("Amount")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                                    .frame(width: 80, alignment: .trailing)
                                
                                Text("")
                                    .frame(width: 30)
                            }
                            .padding(.horizontal, 5)
                            .padding(.bottom, 2)
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.bottom, 5)
                            
                            // Action rows
                            ForEach(actions.indices, id: \.self) { index in
                                ActionRowView(
                                    action: actions[index],
                                    index: index,
                                    isEditing: editingActionIndex == index,
                                    onUpdate: { updatedAction in
                                        actions[index] = updatedAction
                                        updateStreet()
                                    },
                                    onDelete: {
                                        withAnimation {
                                            actions.remove(at: index)
                                            updateStreet()
                                        }
                                    },
                                    onEdit: {
                                        editingActionIndex = index
                                    }
                                )
                                .padding(.vertical, 3)
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(10)
                    } else {
                        Text("No actions")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(10)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.16, green: 0.16, blue: 0.22),
                        Color(red: 0.12, green: 0.12, blue: 0.16)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func selectStreetName(_ name: String) {
        streetName = name
        updateStreet()
    }
    
    private func updateStreet() {
        let updatedStreet = Street(
            name: streetName,
            cards: cards,
            actions: actions
        )
        
        onUpdate(updatedStreet)
    }
}

struct ActionRowView: View {
    let action: Action
    let index: Int
    let isEditing: Bool
    let onUpdate: (Action) -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    @State private var playerName: String
    @State private var actionType: String
    @State private var amount: String
    
    init(action: Action, index: Int, isEditing: Bool = false, onUpdate: @escaping (Action) -> Void, onDelete: @escaping () -> Void, onEdit: @escaping () -> Void) {
        self.action = action
        self.index = index
        self.isEditing = isEditing
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onEdit = onEdit
        
        _playerName = State(initialValue: action.playerName)
        _actionType = State(initialValue: action.action)
        _amount = State(initialValue: action.amount > 0 ? "\(Int(action.amount))" : "0")
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Index
            Text("\(index + 1)")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 30, alignment: .center)
            
            // Player name
            if isEditing {
                TextField("Player", text: $playerName)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .onChange(of: playerName) { newValue in
                        updateAction()
                    }
            } else {
                Text(playerName.isEmpty ? "Unknown" : playerName)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        onEdit()
                    }
            }
            
            // Action type
            Menu {
                Button("Folds") { selectAction("folds") }
                Button("Checks") { selectAction("checks") }
                Button("Calls") { selectAction("calls") }
                Button("Bets") { selectAction("bets") }
                Button("Raises") { selectAction("raises") }
                Button("All-In") { selectAction("all-in") }
            } label: {
                Text(actionType)
                    .font(.system(size: 14))
                    .foregroundColor(actionColor(actionType))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(6)
                    .frame(width: 80)
            }
            
            // Amount
            if isEditing || actionType.lowercased() != "folds" && actionType.lowercased() != "checks" {
                HStack(spacing: 0) {
                    Text("$")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                    
                    TextField("0", text: $amount)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .keyboardType(.numberPad)
                        .onChange(of: amount) { newValue in
                            updateAction()
                        }
                }
                .frame(width: 80, alignment: .trailing)
            } else {
                Text(actionType.lowercased() == "folds" || actionType.lowercased() == "checks" ? "" : "$\(amount)")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 80, alignment: .trailing)
                    .onTapGesture {
                        onEdit()
                    }
            }
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 30)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 5)
        .background(isEditing ? Color.gray.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
    
    private func selectAction(_ action: String) {
        actionType = action
        
        // Reset amount for actions that don't use it
        if action.lowercased() == "folds" || action.lowercased() == "checks" {
            amount = "0"
        }
        
        updateAction()
    }
    
    private func updateAction() {
        let updatedAction = Action(
            playerName: playerName,
            action: actionType,
            amount: Double(amount) ?? action.amount,
            cards: action.cards
        )
        
        onUpdate(updatedAction)
    }
    
    private func actionColor(_ action: String) -> Color {
        switch action.lowercased() {
        case "folds":
            return .red.opacity(0.8)
        case "calls":
            return .blue.opacity(0.8)
        case "raises", "bets", "all-in":
            return .green.opacity(0.8)
        case "checks":
            return .yellow.opacity(0.8)
        default:
            return .white.opacity(0.8)
        }
    }
}

struct PokerCardView: View {
    let card: String
    
    private var isRed: Bool {
        card.hasSuffix("h") || card.hasSuffix("d")
    }
    
    private var suitSymbol: String {
        if card.hasSuffix("h") { return "♥" }
        else if card.hasSuffix("d") { return "♦" }
        else if card.hasSuffix("c") { return "♣" }
        else if card.hasSuffix("s") { return "♠" }
        else { return "" }
    }
    
    private var rank: String {
        if card.count >= 2 {
            return String(card.prefix(card.count - 1))
        }
        return ""
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.1))
                .frame(width: 28, height: 35)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isRed ? Color.red.opacity(0.5) : Color.white.opacity(0.5), lineWidth: 1)
                )
            
            VStack(spacing: 0) {
                Text(rank)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isRed ? .red : .white)
                
                Text(suitSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isRed ? .red : .white)
            }
        }
    }
}

struct PotDistributionView: View {
    let distribution: PotDistribution
    let onUpdate: (PotDistribution) -> Void
    
    @State private var amount: String
    @State private var hand: String
    
    init(distribution: PotDistribution, onUpdate: @escaping (PotDistribution) -> Void) {
        self.distribution = distribution
        self.onUpdate = onUpdate
        
        _amount = State(initialValue: "\(Int(distribution.amount))")
        _hand = State(initialValue: distribution.hand)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Player name and amount header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.yellow)
                    
                    Text(distribution.playerName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                    
                    TextField("Amount", text: $amount)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: amount) { newValue in
                            updateDistribution()
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.1, green: 0.2, blue: 0.1))
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Hand and cards
            HStack(alignment: .center) {
                Text("Winning hand:")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                TextField("Hand", text: $hand)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .onChange(of: hand) { newValue in
                        updateDistribution()
                    }
                
                Spacer()
                
                // Cards display
                if !distribution.cards.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(distribution.cards, id: \.self) { card in
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        (card.hasSuffix("h") || card.hasSuffix("d")) 
                                        ? Color.red.opacity(0.3) : Color.white.opacity(0.3)
                                    )
                                    .frame(width: 22, height: 28)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(
                                                (card.hasSuffix("h") || card.hasSuffix("d")) 
                                                ? Color.red.opacity(0.5) : Color.white.opacity(0.5), 
                                                lineWidth: 1
                                            )
                                    )
                                
                                Text(card)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(
                                        (card.hasSuffix("h") || card.hasSuffix("d")) 
                                        ? .red : .white
                                    )
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.18, blue: 0.15),
                        Color(red: 0.12, green: 0.15, blue: 0.12)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func updateDistribution() {
        let updatedDistribution = PotDistribution(
            playerName: distribution.playerName,
            amount: Double(amount) ?? distribution.amount,
            hand: hand,
            cards: distribution.cards
        )
        
        onUpdate(updatedDistribution)
    }
}

struct EditableInfoRow: View {
    let label: String
    @Binding var value: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.8))
                    .frame(width: 20)
            }
            
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            TextField("Value", text: $value)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(.darkGray).opacity(0.3))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String?
    let content: Content
    @State private var isExpanded: Bool = true
    
    init(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                            )
                    }
                    
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.3))
                        )
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.20, green: 0.20, blue: 0.24),
                                Color(red: 0.16, green: 0.16, blue: 0.20)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.gray.opacity(0.5),
                                    Color.black.opacity(0.1)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                content
                    .padding(.horizontal, 5)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }
}

struct SectionContainer<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            content
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .foregroundColor(.white)
        }
    }
}

struct PlayerSummaryRow: View {
    let player: Player
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(player.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                
                if player.isHero {
                    Text("(Hero)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                }
                
                Spacer()
                
                Text("Seat \(player.seat)")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(player.position ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack {
                Text("Stack: $\(Int(player.stack))")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                if let cards = player.cards, !cards.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(cards, id: \.self) { card in
                            Text(card)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(
                                    card.hasSuffix("h") || card.hasSuffix("d") 
                                    ? .red : .white
                                )
                                .padding(4)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.2))
        .cornerRadius(8)
    }
}

struct StreetSummaryView: View {
    let street: Street
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(street.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if !street.cards.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(street.cards, id: \.self) { card in
                            Text(card)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(
                                    card.hasSuffix("h") || card.hasSuffix("d") 
                                    ? .red : .white
                                )
                                .padding(4)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            if !street.actions.isEmpty {
                ForEach(0..<street.actions.count, id: \.self) { index in
                    let action = street.actions[index]
                    HStack {
                        Text("\(index + 1).")
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 25, alignment: .leading)
                        
                        Text(action.playerName)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text(action.action)
                            .foregroundColor(actionColor(action.action))
                        
                        if action.amount > 0 {
                            Spacer()
                            Text("$\(Int(action.amount))")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    private func actionColor(_ action: String) -> Color {
        switch action.lowercased() {
        case "folds":
            return .red.opacity(0.8)
        case "calls":
            return .blue.opacity(0.8)
        case "raises", "bets":
            return .green.opacity(0.8)
        case "checks":
            return .yellow.opacity(0.8)
        default:
            return .white.opacity(0.8)
        }
    }
} 
