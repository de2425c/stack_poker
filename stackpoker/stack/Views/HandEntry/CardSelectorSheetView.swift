import SwiftUI

struct CardSelectorSheetView: View {
    enum SelectionQuantity {
        case single
        case pair
        case triple
    }
    
    let quantity: SelectionQuantity
    let title: String
    let initialUsedCards: Set<String>
    let currentSelections: [String?]
    let onComplete: ([String?]) -> Void
    
    @State private var selectedCards: [String?]
    @State private var usedCards: Set<String>
    @State private var showClearConfirmation = false
    @Environment(\.presentationMode) var presentationMode
    
    init(quantity: SelectionQuantity, title: String, initialUsedCards: Set<String>, currentSelections: [String?], onComplete: @escaping ([String?]) -> Void) {
        self.quantity = quantity
        self.title = title
        self.initialUsedCards = initialUsedCards
        self.currentSelections = currentSelections
        self.onComplete = onComplete
        
        // Initialize state variables
        _selectedCards = State(initialValue: currentSelections)
        _usedCards = State(initialValue: initialUsedCards)
    }
    
    // Card colors
    private let spadesColor = Color.white
    private let heartsColor = Color.red
    private let diamondsColor = Color(red: 0.95, green: 0.4, blue: 0.4)
    private let clubsColor = Color(white: 0.9)
    
    private let ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]
    private let suits = ["s", "h", "d", "c"]
    
    private var suitSymbols: [String: String] = [
        "s": "♠️",
        "h": "♥️",
        "d": "♦️",
        "c": "♣️"
    ]
    
    private var suitColors: [String: Color] = [
        "s": Color.white,
        "h": Color.red,
        "d": Color(red: 0.95, green: 0.4, blue: 0.4),
        "c": Color(white: 0.9)
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 12) {
            // Header
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        if !selectedCards.allSatisfy({ $0 == nil }) {
                            showClearConfirmation = true
                        }
                    }) {
                        Text("Clear")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.gray)
                            .opacity(selectedCards.contains { $0 != nil } ? 1.0 : 0.5)
                    }
                    .disabled(!selectedCards.contains { $0 != nil })
                    .padding(.trailing, 5)
                }
                .padding(.horizontal)
                .padding(.top, 5)
                
                // Selected cards display
                HStack(spacing: 16) {
                    ForEach(0..<getQuantityInt(), id: \.self) { index in
                        selectedCardView(index: index)
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.12))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Card selector grid
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(suits, id: \.self) { suit in
                            suitSection(suit: suit)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                
                // Action buttons
                HStack(spacing: 15) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color.gray.opacity(0.3))
                            )
                    }
                    
                    Button(action: {
                        saveAndDismiss()
                    }) {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(red: 0.0, green: 0.5, blue: 0.9), Color(red: 0.0, green: 0.5, blue: 0.9).opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(25)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 15)
            }
            .alert(isPresented: $showClearConfirmation) {
                Alert(
                    title: Text("Clear Selection"),
                    message: Text("Are you sure you want to clear all selected cards?"),
                    primaryButton: .destructive(Text("Clear")) {
                        for i in 0..<selectedCards.count {
                            if let card = selectedCards[i] {
                                usedCards.remove(card)
                            }
                            selectedCards[i] = nil
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    private func getQuantityInt() -> Int {
        switch quantity {
        case .single: return 1
        case .pair: return 2
        case .triple: return 3
        }
    }
    
    private func suitSection(suit: String) -> some View {
        VStack(spacing: 8) {
            // Suit header
            HStack {
                Text(suitSymbols[suit] ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(suitColors[suit])
                
                Spacer()
            }
            .padding(.leading, 5)
            
            // Cards grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(ranks, id: \.self) { rank in
                    let card = "\(rank)\(suit)"
                    cardButton(card: card)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12))
        )
    }
    
    private func cardButton(card: String) -> some View {
        let isSelected = selectedCards.contains(card)
        let isUsed = usedCards.contains(card) && !isSelected
        
        return Button(action: {
            handleCardSelection(card: card)
        }) {
            Text(card.prefix(1) + (suitSymbols[String(card.suffix(1))] ?? ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(getCardColor(card: card, isUsed: isUsed))
                .frame(width: 40, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(getCardBackground(isSelected: isSelected, isUsed: isUsed))
                        .shadow(color: Color.black.opacity(0.2), radius: isSelected ? 3 : 0, x: 0, y: isSelected ? 2 : 0)
                )
        }
        .disabled(isUsed)
        .contentShape(Rectangle())
    }
    
    private func getCardColor(card: String, isUsed: Bool) -> Color {
        if isUsed {
            return Color.gray.opacity(0.5)
        }
        
        if let suit = card.last {
            switch String(suit) {
            case "s": return spadesColor
            case "h": return heartsColor
            case "d": return diamondsColor
            case "c": return clubsColor
            default: return Color.white
            }
        }
        
        return Color.white
    }
    
    private func getCardBackground(isSelected: Bool, isUsed: Bool) -> Color {
        if isSelected {
            return Color(red: 0.0, green: 0.5, blue: 0.9).opacity(0.7)
        } else if isUsed {
            return Color(white: 0.18).opacity(0.5)
        } else {
            return Color(white: 0.18)
        }
    }
    
    private func selectedCardView(index: Int) -> some View {
        let hasSelection = index < selectedCards.count && selectedCards[index] != nil
        let card = hasSelection ? selectedCards[index]! : nil
        
        return ZStack {
            if let card = card {
                let suit = String(card.suffix(1))
                let rank = String(card.prefix(1))
                
                // Selected card display
                VStack(spacing: 2) {
                    Text(rank)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(suitColors[suit] ?? .white)
                    
                    Text(suitSymbols[suit] ?? "")
                        .font(.system(size: 22))
                        .foregroundColor(suitColors[suit] ?? .white)
                }
                .frame(width: 60, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.05))
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
                
                // Remove button
                Button(action: {
                    if let card = selectedCards[index] {
                        usedCards.remove(card)
                        selectedCards[index] = nil
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(Color.black)
                        .clipShape(Circle())
                }
                .offset(x: 22, y: -32)
            } else {
                // Empty card placeholder
                Text("?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.gray.opacity(0.5))
                    .frame(width: 60, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
        }
    }
    
    private func handleCardSelection(card: String) {
        // Find first empty slot
        if let index = selectedCards.firstIndex(where: { $0 == nil }) {
            // Check if the card is already selected in another slot
            if let existingIndex = selectedCards.firstIndex(where: { $0 == card }) {
                // If so, remove from that slot
                selectedCards[existingIndex] = nil
            }
            
            // Add to the new slot
            selectedCards[index] = card
            usedCards.insert(card)
        } else if let index = selectedCards.firstIndex(where: { $0 == card }) {
            // Card is already selected, remove it
            selectedCards[index] = nil
            usedCards.remove(card)
        } else if selectedCards.count > 0 {
            // All slots filled, replace the first one
            if let firstCard = selectedCards[0] {
                usedCards.remove(firstCard)
            }
            
            selectedCards[0] = card
            usedCards.insert(card)
        }
    }
    
    private func saveAndDismiss() {
        onComplete(selectedCards)
        presentationMode.wrappedValue.dismiss()
    }
}


