import SwiftUI

// Reusable Card Selector View with Grid
struct CardSelectorView: View {
    let title: String 
    @Binding var selectedCard: String?
    let usedCards: Set<String>
    let ranks: [String]
    let suits: [String]
    @Environment(\.dismiss) var dismiss
    
    // Create a computed property for all possible card combinations
    private var allCards: [String] {
        ranks.flatMap { rank in
            suits.map { suit in "\(rank)\(suit)" }
        }
    }

    // Grid layout definition - Tighter spacing
    // Let's define columns more simply based on number of suits
    private var columns: [GridItem] { 
        Array(repeating: .init(.flexible(), spacing: 5), count: suits.count) 
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Display selected card visually
                Text("Selected: \(selectedCard ?? "None")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedCard != nil ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    
                Spacer()
                
                // Clear button
                if selectedCard != nil {
                    Button {
                        selectedCard = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2) 
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)

            // Card Grid - FIXED: Iterate over unique card strings
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(allCards, id: \.self) { card in // Iterate unique card strings
                    // Extract rank and suit for the button view
                    let rank = String(card.prefix(1))
                    let suit = String(card.suffix(1))
                    
                    CardButtonView(
                        rank: rank,
                        suit: suit,
                        selectedCard: $selectedCard,
                        usedCards: usedCards
                    )
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .cornerRadius(10)
        }
    }
    
    // Helper View for each card button in the grid
    struct CardButtonView: View {
        let rank: String
        let suit: String
        @Binding var selectedCard: String?
        let usedCards: Set<String>
        @Environment(\.dismiss) var dismiss
        
        private var card: String { "\(rank)\(suit)" }
        private var isUsed: Bool { usedCards.contains(card) && card != selectedCard }
        private var isSelected: Bool { card == selectedCard }
        
        private var cardColor: Color {
            suitColor(suit: suit)
        }
        
        var body: some View {
            Button {
                if !isUsed {
                    selectedCard = card
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        dismiss()
                    }
                }
            } label: {
                VStack(spacing: 1) { // Stack rank and suit vertically
                    Text(rank)
                        .font(.system(size: 16, weight: .bold))
                     Text(suitSymbol(suit: suit))
                         .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 45) // Taller buttons
                .background(isSelected ? Color.green.opacity(0.5) : Color.black.opacity(isUsed ? 0.1 : 0.4))
                .foregroundColor(isUsed ? .gray.opacity(0.5) : cardColor)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.green : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )
                 .shadow(color: isSelected ? .green.opacity(0.3) : .clear, radius: 3)
            }
            .buttonStyle(PlainButtonStyle()) 
            .disabled(isUsed)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .animation(.easeOut(duration: 0.15), value: isUsed)
        }
    }
} 