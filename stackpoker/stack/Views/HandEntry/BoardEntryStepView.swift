import SwiftUI

struct BoardEntryStepView: View {
    @EnvironmentObject var viewModel: HandEntryViewModel
    
    // State for popovers (using simple Int index)
    @State private var showingBoardPopoverIndex: Int? = nil // 1=F1, 2=F2, 3=F3, 4=T, 5=R
    
    // Separate state variables for each street's expanded state
    @State private var isFlopExpanded: Bool = true
    @State private var isTurnExpanded: Bool = false
    @State private var isRiverExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Add extra spacing at the top
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap any card position to select a community card")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 4)
                
                // Flop Section
                boardStreetSection(
                    title: "Flop",
                    systemIcon: "3.square.fill",
                    isExpanded: $isFlopExpanded,
                    content: {
                        HStack(spacing: 16) {
                            boardCardButton(title: "Flop 1", cardBinding: $viewModel.flopCard1, index: 1)
                            boardCardButton(title: "Flop 2", cardBinding: $viewModel.flopCard2, index: 2)
                            boardCardButton(title: "Flop 3", cardBinding: $viewModel.flopCard3, index: 3)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                )
                
                // Turn Section
                boardStreetSection(
                    title: "Turn",
                    systemIcon: "4.square.fill",
                    isExpanded: $isTurnExpanded,
                    content: {
                        HStack {
                            boardCardButton(title: "Turn", cardBinding: $viewModel.turnCard, index: 4)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                )
                
                // River Section
                boardStreetSection(
                    title: "River",
                    systemIcon: "5.square.fill",
                    isExpanded: $isRiverExpanded,
                    content: {
                        HStack {
                            boardCardButton(title: "River", cardBinding: $viewModel.riverCard, index: 5)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                )
                
                // Board Preview
                boardPreview
                
                Spacer()
            }
            .padding()
        }
    }
    
    // MARK: - Component Views
    
    // Street section with expand/collapse functionality
    private func boardStreetSection<Content: View>(
        title: String,
        systemIcon: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with toggle
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.wrappedValue.toggle()
                }
            }) {
                HStack {
                    Image(systemName: systemIcon)
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .font(.system(size: 18))
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                        .animation(.easeInOut, value: isExpanded.wrappedValue)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Content section (conditionally visible)
            if isExpanded.wrappedValue {
                content()
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
    }
    
    // Improved card button with visual feedback
    private func boardCardButton(title: String, cardBinding: Binding<String?>, index: Int) -> some View {
        Button { 
            showingBoardPopoverIndex = index
        } label: {
            VStack(spacing: 8) {
                cardDisplay(cardBinding.wrappedValue, placeholder: title)
                    .frame(width: 60, height: 84)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(cardBinding.wrappedValue != nil ? 
                                  Color.black.opacity(0.4) : 
                                  Color.black.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                cardBinding.wrappedValue != nil ? 
                                suitColorForCard(cardBinding.wrappedValue)?.opacity(0.8) ?? Color.gray.opacity(0.5) : 
                                Color.gray.opacity(0.3),
                                lineWidth: 1.5
                            )
                    )
                
                if cardBinding.wrappedValue == nil {
                    Text("Select")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: Binding(
            get: { showingBoardPopoverIndex == index },
            set: { if !$0 { showingBoardPopoverIndex = nil } }
        ), arrowEdge: .bottom) {
             CardSelectorView(
                 title: title,
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
    
    // Visual card display
    private func cardDisplay(_ card: String?, placeholder: String) -> some View {
        ZStack {
            if let card = card {
                Text(card)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(suitColorForCard(card) ?? .white)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                    .padding(8)
            } else {
                VStack {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.gray.opacity(0.8))
                }
            }
        }
    }
    
    // MARK: - Board Preview
    
    private var boardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board Preview")
                .font(.headline)
                .foregroundColor(.white)
            
            // Store board cards in a local constant to simplify expressions
            let boardCards = getDisplayableCards()
            
            HStack(alignment: .center, spacing: 8) {
                if boardCards.isEmpty {
                    emptyBoardMessage
                } else {
                    boardCardDisplay(cards: boardCards)
                }
            }
            .frame(height: 80)
            .padding()
            .background(Color.black.opacity(0.2))
            .cornerRadius(12)
        }
        .padding()
        .background(Color.black.opacity(0.15))
        .cornerRadius(16)
    }
    
    // Extract card display logic into a separate view
    private func boardCardDisplay(cards: [String]) -> some View {
        ForEach(cards, id: \.self) { card in
            // Extract card styling into separate view builder
            cardPreviewItem(card: card)
        }
    }
    
    // Helper for individual card rendering
    private func cardPreviewItem(card: String) -> some View {
        Text(card)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(suitColorForCard(card) ?? .white)
            .frame(width: 50, height: 70)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(suitColorForCard(card)?.opacity(0.4) ?? Color.gray.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
    
    // Empty board message when no cards selected
    private var emptyBoardMessage: some View {
        Text("No cards selected")
            .font(.system(size: 14))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // Helper function to get all available cards
    private func getDisplayableCards() -> [String] {
        return [viewModel.flopCard1, 
                viewModel.flopCard2, 
                viewModel.flopCard3, 
                viewModel.turnCard, 
                viewModel.riverCard].compactMap { $0 }
    }
    
    // MARK: - Helper Functions
    
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
}

struct BoardEntryStepView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { 
            BoardEntryStepView()
                .environmentObject(HandEntryViewModel())
                .background(AppBackgroundView())
                .navigationTitle("Board") 
        }
        .preferredColorScheme(.dark)
    }
} 
