import SwiftUI

struct PlayerEntryStepView: View {
    @EnvironmentObject var viewModel: HandEntryViewModel
    
    // State for popovers
    @State private var showingCardPopover: UUID? = nil // Use Player ID + Card Index
    @State private var popoverTargetCardIndex: Int = 0 // 1 or 2
    @State private var animateHero: Bool = false // Animation state

    // Accent color matching design constants
    private let accentColor = Color(red: 123/255, green: 255/255, blue: 99/255)
    
    var body: some View {
        ScrollView { 
            VStack(alignment: .leading, spacing: 20) {
                // Add extra spacing at the top
                
                // Instructions
                Text("Only enter the villains involved in the hand, everything else will be automatically populated.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
                
                // Hero Section
                if let heroIndex = viewModel.players.firstIndex(where: { $0.isHero }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundColor(accentColor)
                                .font(.system(size: 18))
                            
                            Text("Hero")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 4)
                        
                        playerRowContent(for: $viewModel.players[heroIndex])
                            .padding()
                            .background(Color.black.opacity(0.25))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(accentColor.opacity(animateHero ? 0.7 : 0.3), lineWidth: 1.5)
                            )
                            .shadow(color: accentColor.opacity(animateHero ? 0.4 : 0), radius: 6)
                            .onAppear {
                                // Add subtle animation for hero card
                                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                    animateHero = true
                                }
                            }
                    }
                    .padding()
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(16)
                }
                
                // Villains Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(accentColor)
                            .font(.system(size: 18))
                        
                        Text("Villains")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: addVillain) {
                            Label("Add", systemImage: "plus.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .disabled(viewModel.players.count >= viewModel.tableSize)
                        .opacity(viewModel.players.count >= viewModel.tableSize ? 0.5 : 1)
                    }
                    .padding(.bottom, 4)
                    
                    if villainIndices.isEmpty {
                        Text("No villains added. Tap the Add button to include opponents.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(villainIndices, id: \.self) { index in
                                villainRow(for: $viewModel.players[index])
                            }
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(16)
                
                // Tips section
                infoPanel
            }
            .padding()
        }
    }
    
    // MARK: - Components
    
    // Villain row with delete button
    private func villainRow(for player: Binding<PlayerEntry>) -> some View {
        VStack {
            playerRowContent(for: player)
                .padding()
                .background(Color.black.opacity(0.25))
                .cornerRadius(12)
                .overlay(
                    HStack {
                        Spacer()
                        
                        Button(action: { removePlayer(id: player.id.wrappedValue) }) {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red.opacity(0.7))
                                .font(.system(size: 14))
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .offset(x: 10, y: -10)
                    }
                )
        }
    }
    
    // Common player row content
    private func playerRowContent(for player: Binding<PlayerEntry>) -> some View {
        VStack(spacing: 16) {
            // Name and Position row
            HStack {
                // Name display
                Text(player.wrappedValue.isHero ? "Hero" : player.name.wrappedValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(player.wrappedValue.isHero ? accentColor : .white)
                
                Spacer()
                
                // Dealer button indicator for BTN position
                if player.position.wrappedValue == "BTN" {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                        Text("D")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.trailing, 4)
                }
                
                // Position picker
                Menu {
                    ForEach(viewModel.availablePositions(for: player.id.wrappedValue), id: \.self) { pos in
                        Button(action: {
                            player.position.wrappedValue = pos
                        }) {
                            HStack {
                                Text(pos)
                                if player.position.wrappedValue == pos {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(player.position.wrappedValue ?? "Position")
                            .font(.system(size: 15))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(
                        player.position.wrappedValue != nil ? .white : .gray
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            // Stack and cards row
            HStack {
                // Stack input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stack")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                        
                        TextField("Amount", value: player.stack, formatter: currencyFormatter)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity)
                
                Spacer(minLength: 16)
                
                // Card buttons
                HStack(spacing: 8) {
                    cardButton(player: player, cardIndex: 1)
                    cardButton(player: player, cardIndex: 2)
                }
            }
        }
    }
    
    // Enhanced card button
    private func cardButton(player: Binding<PlayerEntry>, cardIndex: Int) -> some View {
        let cardBinding = (cardIndex == 1) ? player.card1 : player.card2
        let playerID = player.id.wrappedValue
        
        return Button {
            popoverTargetCardIndex = cardIndex
            showingCardPopover = playerID 
        } label: {
            ZStack {
                // Card display
                VStack {
                    if let card = cardBinding.wrappedValue {
                        Text(card)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(suitColorForCard(card) ?? .white)
                            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 16))
                            Text("Card \(cardIndex)")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.gray)
                    }
                }
                .frame(width: 50, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(cardBinding.wrappedValue != nil ? 
                              Color.black.opacity(0.4) : 
                              Color.black.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            cardBinding.wrappedValue != nil ? 
                            suitColorForCard(cardBinding.wrappedValue)?.opacity(0.8) ?? Color.gray.opacity(0.3) : 
                            Color.gray.opacity(0.3),
                            lineWidth: 1.5
                        )
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: Binding(
            get: { showingCardPopover == playerID && popoverTargetCardIndex == cardIndex },
            set: { if !$0 { showingCardPopover = nil } }
        ), arrowEdge: .bottom) {
            CardSelectorView(
                title: "Card \(cardIndex) for \(player.name.wrappedValue)",
                selectedCard: cardBinding,
                usedCards: viewModel.usedCards,
                ranks: viewModel.cardRanks,
                suits: viewModel.cardSuits
            )
            .padding()
            .frame(idealWidth: 300, idealHeight: 400)
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        }
    }
    
    // Info panel
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(accentColor.opacity(0.8))
                
                Text("Poker Order Tips")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                bulletPoint("The dealer (BTN) distributes the cards clockwise, starting with the small blind (SB).")
                bulletPoint("Action starts with SB posting the small blind, followed by BB posting the big blind.")
                bulletPoint("Preflop betting begins with the player after BB (UTG) and continues clockwise.")
                bulletPoint("Postflop betting starts with the SB and continues clockwise to the dealer (BTN).")
            }
        }
        .padding()
        .background(Color.black.opacity(0.15))
        .cornerRadius(12)
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.gray)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Helper Functions
    
    // Computed property for villain indices
    var villainIndices: [Int] {
        viewModel.players.indices.filter { !viewModel.players[$0].isHero }
    }
    
    private func suitColorForCard(_ card: String?) -> Color? {
        guard let card = card, card.count == 2 else { return nil }
        let suit = String(card.suffix(1))
        switch suit.lowercased() {
        case "h": return .red.opacity(0.9)
        case "d": return Color(red: 0.95, green: 0.4, blue: 0.4)
        case "c": return Color(red: 0.3, green: 0.8, blue: 0.5)
        case "s": return .white.opacity(0.95)
        default: return .gray
        }
    }
    
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    // MARK: - Actions
    
    func addVillain() {
        guard viewModel.players.count < viewModel.tableSize else { return }
        let newIndex = viewModel.players.count 
        let available = viewModel.availablePositions(for: nil) 
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.players.append(PlayerEntry(
                name: "Villain \(newIndex)", 
                position: available.first, 
                stack: viewModel.bigBlind * 100, 
                isHero: false, 
                card1: nil, 
                card2: nil
            ))
        }
    }

    // Updated remove function to use ID
    func removePlayer(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.players.removeAll { $0.id == id && !$0.isHero }
        }
    }
}

struct PlayerEntryStepView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlayerEntryStepView()
                .environmentObject(HandEntryViewModel())
                .background(AppBackgroundView())
        }
         .preferredColorScheme(.dark)
    }
} 
