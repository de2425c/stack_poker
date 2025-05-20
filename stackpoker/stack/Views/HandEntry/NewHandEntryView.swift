import SwiftUI
import FirebaseAuth // Required for HandStore

// Define this outside or ensure it's accessible if already defined elsewhere
enum CardSelectionTarget: Identifiable {
    case heroHand 
    case flopTriplet
    case turnCard, riverCard
    case villainHand(playerId: UUID)
    var id: String {
        switch self {
        case .heroHand: return "heroHand"
        case .flopTriplet: return "flopTriplet"
        case .turnCard: return "turnCard"
        case .riverCard: return "riverCard"
        case .villainHand(let id): return "villainHand_\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .heroHand: return "Hero Hand"
        case .flopTriplet: return "Flop Cards"
        case .turnCard: return "Turn Card"
        case .riverCard: return "River Card"
        case .villainHand: return "Opponent Cards"
        }
    }
}

enum StreetIdentifier: String, CaseIterable {
    case preflop, flop, turn, river
}

// Updated color scheme for a more modern and sleek look
extension Color {
    static let primaryBackground = Color.black
    static let secondaryBackground = Color(white: 0.1)
    static let tertiaryBackground = Color(white: 0.15)
    static let accentBlue = Color(red: 0.0, green: 0.5, blue: 0.9)
    static let accentGreen = Color(red: 0.0, green: 0.85, blue: 0.4) // Brighter, more neon green
    static let accentRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    static let accentOrange = Color.orange
    static let accentPurple = Color(red: 0.5, green: 0.3, blue: 0.8)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let cardBackground = Color(white: 0.18)
    static let cardHighlight = Color.accentBlue.opacity(0.7)
    static let inputBackground = Color(white: 0.13)
    static let sectionHeader = Color.accentGreen.opacity(0.9) // Changed to green
    static let dividerColor = Color(white: 0.2)
    // Suit colors
    static let spadeColor = Color.white
    static let heartColor = Color.red
    static let diamondColor = Color(red: 0.95, green: 0.4, blue: 0.4)
    static let clubColor = Color(white: 0.9)
}

struct NewHandEntryView: View {
    @StateObject var viewModel: NewHandEntryViewModel
    @StateObject private var handStore = HandStore(userId: Auth.auth().currentUser?.uid ?? "")
    @Environment(\.presentationMode) var presentationMode
    @State private var isSaving = false
    @State private var cardSelectionTarget: CardSelectionTarget? = nil
    @State private var showingCardSelectorSheet = false
    @State private var showingTableSetup = false
    @FocusState private var isBetAmountFieldFocused: Bool
    
    // Add sessionId property
    private let sessionId: String?

    // Initializer to accept sessionId
    init(sessionId: String? = nil) {
        self.sessionId = sessionId
        // Initialize viewModel with the sessionId
        _viewModel = StateObject(wrappedValue: NewHandEntryViewModel(sessionId: sessionId))
    }
    
    private var doubleFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    // Card design helper functions
    private func cardSymbol(for card: String?) -> (String, Color) {
        guard let card = card, card.count == 2 else {
            return ("?", Color.textSecondary)
        }
        
        let rank = String(card.prefix(1))
        let suit = String(card.suffix(1))
        
        let symbol: String
        let color: Color
        
        switch suit {
            case "s": symbol = "♠️"; color = .spadeColor
            case "h": symbol = "♥️"; color = .heartColor
            case "d": symbol = "♦️"; color = .diamondColor
            case "c": symbol = "♣️"; color = .clubColor
            default: symbol = "?"; color = .textSecondary
        }
        
        return (rank + symbol, color)
    }

    var body: some View {
        ZStack {
            Color.primaryBackground.edgesIgnoringSafeArea(.all)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Add title at the top
                    Text("Save Hand")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.accentGreen)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    // Game setup info
                    gameInfoPanel
                        .padding(.horizontal, 16)
                    
                    // Players section with more space
                    playersSectionView
                        .padding(.horizontal, 16)
                    
                    // Board and actions with more space
                    boardAndActionSection
                        .padding(.horizontal, 16)
                    
                    // Error message if any
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentRed.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentRed.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 30)
                    
                    // Save Button - floating style
                    Button(action: saveHand) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("SAVE")
                                    .font(.system(size: 16, weight: .bold))
                                    .tracking(0.5)
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentBlue, Color.accentPurple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, 25)
                    .padding(.bottom, 25)
                }
                .padding(.top, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Color.textSecondary)
                            .font(.system(size: 16))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingTableSetup.toggle()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color.accentGreen)
                            .font(.system(size: 16))
                    }
                }
            }
            .sheet(isPresented: $showingTableSetup) {
                tableSetupSheet
            }
            .sheet(item: $cardSelectionTarget) { target in
                cardSelectorSheet(for: target)
                    .preferredColorScheme(.dark)
            }
        }
    }
    
    // Reorganized game info panel with ante/straddle below
    private var gameInfoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: Blinds and Table Size
            HStack(alignment: .top, spacing: 20) {
                // Blinds Section - SB and BB side by side
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blinds")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentGreen)
                    
                    // SB and BB in one horizontal row
                    HStack(spacing: 10) {
                        // SB with smaller text box
                        HStack(spacing: 0) {
                            Text("SB")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                                .frame(width: 20, alignment: .leading)
                            
                            Spacer(minLength: 5)
                            
                            TextField("", value: $viewModel.smallBlind, formatter: doubleFormatter)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                                .frame(width: 40)
                                .background(Color.inputBackground)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.dividerColor.opacity(0.7), lineWidth: 0.5)
                                )
                        }
                        .frame(width: 70)
                        
                        // BB with smaller text box
                        HStack(spacing: 0) {
                            Text("BB")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                                .frame(width: 20, alignment: .leading)
                            
                            Spacer(minLength: 5)
                            
                            TextField("", value: $viewModel.bigBlind, formatter: doubleFormatter)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                                .frame(width: 40)
                                .background(Color.inputBackground)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.dividerColor.opacity(0.7), lineWidth: 0.5)
                                )
                        }
                        .frame(width: 70)
                    }
                }
                .padding(.trailing, 10)

                // Table Size Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Table Size")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentGreen)
                    
                    Picker("", selection: $viewModel.tableSize) {
                        Text("2-max").tag(2)
                        Text("6-max").tag(6)
                        Text("9-max").tag(9)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(minWidth: 150, idealWidth: 180)
                }
            }

            // Divider for visual separation
            Divider().background(Color.dividerColor.opacity(0.5)).padding(.vertical, 4)

            // Ante and Straddle Section - Side by Side for a cleaner look
            HStack(alignment: .top, spacing: 20) {
                // Ante Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Ante")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentGreen)
                        Spacer()
                        Toggle("", isOn: $viewModel.hasAnte.animation())
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .accentGreen))
                    }
                    .frame(width: 130) // Constrain width for better alignment with potential slider

                    if viewModel.hasAnte {
                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { viewModel.ante ?? 0 },
                                set: { viewModel.ante = $0 }
                            ), in: 0...(viewModel.bigBlind * 0.5), step: 0.1) // Max ante typically related to BB
                                .accentColor(Color.accentGreen)
                            inputField(label: "", value: $viewModel.ante, width: 50, showLabel: false)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .padding(.top, -4) // Reduce space slightly after toggle
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity) // Allow this VStack to expand

                // Straddle Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Straddle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentGreen)
                        Spacer()
                        Toggle("", isOn: $viewModel.hasStraddle.animation())
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .accentGreen))
                    }
                    .frame(width: 130)

                    if viewModel.hasStraddle {
                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { viewModel.straddle ?? viewModel.bigBlind * 2 },
                                set: { viewModel.straddle = $0 }
                            ), in: viewModel.bigBlind...(viewModel.bigBlind * 3), step: viewModel.bigBlind) // Straddle related to BB
                                .accentColor(Color.accentGreen)
                            inputField(label: "", value: $viewModel.straddle, width: 50, showLabel: false)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .padding(.top, -4)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity) // Allow this VStack to expand
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14) // Slightly increased corner radius
                .fill(Color.secondaryBackground)
                .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 3) // Slightly enhanced shadow
        )
    }
    
    // Helper for styled input fields to reduce repetition and ensure consistency
    @ViewBuilder
    private func inputField(label: String, value: Binding<Double?>, width: CGFloat = 55, showLabel: Bool = true) -> some View {
        HStack(spacing: showLabel ? 10 : 0) {
            if showLabel {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            TextField("", value: value, formatter: doubleFormatter)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold)) // Bolder input text
                .foregroundColor(.textPrimary)
                .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)) // Adjusted padding
                .frame(width: width)
                .background(Color.inputBackground)
                .cornerRadius(6) // Slightly softer corners
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.dividerColor.opacity(0.7), lineWidth: 0.5) // Subtle border
                )
        }
    }
    
    // Helper for Binding<Double?> from Binding<Double>
    private func optionalBinding(for binding: Binding<Double>) -> Binding<Double?> {
        Binding<Double?>(
            get: { binding.wrappedValue },
            set: { newValue in binding.wrappedValue = newValue ?? 0 }
        )
    }
    
    // Overload for Binding<Double>
    @ViewBuilder
    private func inputField(label: String, value: Binding<Double>, width: CGFloat = 50, showLabel: Bool = true) -> some View {
        inputField(label: label, value: optionalBinding(for: value), width: width, showLabel: showLabel)
    }
    
    // Fix hero section to be truly one line with more space for position picker
    private var playersSectionView: some View {
        VStack(spacing: 10) {
            // Hero section - all in one line
            HStack(alignment: .center, spacing: 10) {
                // Hero position with more space - complete redesign
                HStack(spacing: 0) {
                    Text("HERO")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accentGreen)
                        .lineLimit(1)
                        .frame(width: 40, alignment: .leading)
                    
                    Spacer(minLength: 10)
                    
                    Picker("", selection: $viewModel.heroPosition) {
                        ForEach(viewModel.availablePositions, id: \.self) { position in
                            Text(position).tag(position)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                }
                .frame(width: 130)
                
                // Hero cards
                HStack(spacing: 4) {
                    ForEach([viewModel.heroCard1, viewModel.heroCard2], id: \.self) { card in
                        let (symbol, color) = cardSymbol(for: card)
                        Button(action: { cardSelectionTarget = .heroHand }) {
                            Text(symbol)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(color)
                                .frame(width: 32, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(card == nil ? Color.cardBackground.opacity(0.5) : Color.cardBackground)
                                        .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                                )
                        }
                    }
                }
                
                Spacer()
                
                // Stack amount - fix wrapping
                HStack(spacing: 0) {
                    Text("STACK $")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .frame(width: 55, alignment: .leading)
                    
                    Spacer(minLength: 5)
                    
                    TextField("", value: $viewModel.effectiveStackAmount, formatter: doubleFormatter)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .padding(5)
                        .frame(width: 45)
                        .background(Color.inputBackground)
                        .cornerRadius(5)
                        .onChange(of: viewModel.effectiveStackAmount) { _ in
                            viewModel.updatePlayerStacksBasedOnEffectiveStack()
                            viewModel.effectiveStackType = .dollars
                        }
                }
                .frame(width: 105)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondaryBackground)
            )
            
            // Active villains section
            VStack(spacing: 8) {
                HStack {
                    Text("ACTIVE VILLAINS")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accentGreen)
                        .tracking(0.8)
                    
                    Spacer()
                }
                
                if viewModel.players.filter({ $0.isActive && !$0.isHero }).isEmpty {
                    // Empty state when no active villains
                    Text("No active villains - add positions below")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.tertiaryBackground)
                        .cornerRadius(8)
                } else {
                    // Active villains list
                    ForEach(viewModel.players.filter({ $0.isActive && !$0.isHero }), id: \.id) { player in
                        HStack(spacing: 10) {
                            // Position
                            Text(player.position)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 40, alignment: .leading)
                            
                            // Stack
                            Text("$\(Int(player.stack))")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                            
                            Spacer()
                            
                            // Cards
                            Button(action: { cardSelectionTarget = .villainHand(playerId: player.id) }) {
                                HStack(spacing: 2) {
                                    ForEach([player.card1, player.card2], id: \.self) { card in
                                        let (symbol, color) = cardSymbol(for: card)
                                        Text(symbol)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(color)
                                            .frame(width: 30, height: 36)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(card == nil ? Color.cardBackground.opacity(0.5) : Color.cardBackground)
                                            )
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            
                            // Remove button
                            Button(action: {
                                if let index = viewModel.players.firstIndex(where: { $0.id == player.id }) {
                                    viewModel.players[index].isActive = false
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentRed.opacity(0.7))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.tertiaryBackground)
                        )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondaryBackground)
            )
            
            // Available positions section - renamed to "ADD ACTIVE VILLAIN"
            VStack(spacing: 8) {
                HStack {
                    Text("ADD ACTIVE VILLAIN")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accentGreen)
                        .tracking(0.8)
                    
                    Spacer()
                }
                
                // Position buttons in a grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(viewModel.players.filter { !$0.isHero && !$0.isActive }, id: \.id) { player in
                        Button(action: {
                            if let index = viewModel.players.firstIndex(where: { $0.id == player.id }) {
                                viewModel.players[index].isActive = true
                            }
                        }) {
                            Text(player.position)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.tertiaryBackground.opacity(0.7))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.accentGreen.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondaryBackground)
            )
        }
    }
    
    // Fix street tabs with more space
    private var streetTabsView: some View {
        HStack(spacing: 2) {
            ForEach(StreetIdentifier.allCases, id: \.self) { street in
                let isActive = viewModel.currentActionStreet == street
                let hasContent = !viewModel.actionsForStreet(street).isEmpty || streetHasCards(street)
                let isEnabled = hasContent || (viewModel.waitingForNextStreetCards && viewModel.nextStreetNeeded == street)
                
                Button(action: {
                    if isEnabled {
                        viewModel.currentActionStreet = street
                    }
                }) {
                    VStack(spacing: 3) {
                        Text(street.rawValue.capitalized)
                            .font(.system(size: 14, weight: isActive ? .bold : .medium))
                            .foregroundColor(isActive ? colorForStreet(street) : (isEnabled ? .textPrimary : .textSecondary))
                        
                        // Indicator for active tab
                        RoundedRectangle(cornerRadius: 1)
                            .frame(height: 2)
                            .foregroundColor(isActive ? colorForStreet(street) : .clear)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.secondaryBackground)
                }
                .disabled(!isEnabled)
            }
        }
        // Use secondaryBackground to match the box below
        .background(Color.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentGreen.opacity(0.3), lineWidth: 1)
        )
    }
    
    // Board actions section with more appropriate spacing
    private var boardAndActionSection: some View {
        VStack(spacing: 12) {
            // Sleek street tabs
            streetTabsView
            
            // Current street content
            VStack(spacing: 8) {
                switch viewModel.currentActionStreet {
                case .preflop:
                    preflopContent
                case .flop:
                    flopContent
                case .turn:
                    turnContent
                case .river:
                    riverContent
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondaryBackground)
            )
        }
    }
    
    // Fix action display with more space
    @ViewBuilder
    private func displayActionsList(actions: [ActionInput], street: StreetIdentifier) -> some View {
        VStack(spacing: 6) {
            // Pot display with green accent
            HStack {
                Text("POT:")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textSecondary)
                
                Text("$\(potForStreet(street), specifier: "%.2f")")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentGreen.opacity(0.15))
                    )
                
                Spacer()
                
                // Waiting indicator
                if viewModel.waitingForNextStreetCards && viewModel.nextStreetNeeded == street.next {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 12))
                        Text("Need \(street.next.rawValue.capitalized)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(colorForStreet(street.next))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorForStreet(street.next).opacity(0.15))
                    )
                }
            }
            
            // Empty state or action list
            if actions.isEmpty && (viewModel.pendingActionInput == nil || viewModel.currentActionStreet != street) 
               && !(street != .preflop && viewModel.preflopActions.isEmpty && viewModel.actionsForStreet(street).isEmpty && streetHasCards(street) ) {
                // Empty state with minimalist design
                VStack(spacing: 3) {
                    Image(systemName: "person.crop.circle.badge.clock")
                        .font(.system(size: 18))
                        .foregroundColor(Color.accentGreen.opacity(0.5))
                        .padding(.bottom, 2)
                    
                    Text("Waiting for actions")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.tertiaryBackground.opacity(0.5))
                )
            } else {
                // Action list
                ForEach(actions.indices, id: \.self) { index in
                    if index < actions.count {
                        let action = actions[index]
                        HStack {
                            // Position with color indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(action.isSystemAction ? Color.gray.opacity(0.5) : colorForPlayer(name: action.playerName))
                                    .frame(width: 6, height: 6)
                                
                                Text(action.playerName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(action.isSystemAction ? Color.textSecondary : Color.textPrimary)
                            }
                            .frame(width: 40, alignment: .leading)
                            
                            // Action type
                            HStack(spacing: 3) {
                                actionIcon(for: action.actionType)
                                    .foregroundColor(actionColor(for: action.actionType))
                                    .font(.system(size: 11))
                                
                                Text(action.actionType.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(action.isSystemAction ? Color.textSecondary : actionColor(for: action.actionType))
                            }
                            
                            // Amount
                            if let amount = action.amount, amount > 0 {
                                Spacer()
                                
                                Text("$\(amount, specifier: "%.0f")")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(action.isSystemAction ? Color.textSecondary : Color.textPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.tertiaryBackground)
                                    )
                            }
                            
                            Spacer()
                            
                            // Undo button for last action
                            if index == actions.count - 1 && street == viewModel.currentActionStreet {
                                Button(action: {
                                    viewModel.undoLastAction()
                                }) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .foregroundColor(Color.accentRed)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index % 2 == 0 ? Color.tertiaryBackground.opacity(0.7) : Color.tertiaryBackground.opacity(0.4))
                        )
                    }
                }
            }
        }
        
        // Pending action
        if let pendingAction = viewModel.pendingActionInput, viewModel.currentActionStreet == street {
            pendingActionView(pendingAction: pendingAction)
                .padding(.top, 6)
        }
    }
    
    // Fix pending action view
    @ViewBuilder
    private func pendingActionView(pendingAction: ActionInput) -> some View {
        // Bindings (unchanged)
        let actionTypeBinding = Binding<PokerActionType>(
            get: { viewModel.pendingActionInput?.actionType ?? .fold },
            set: { newActionType in
                if viewModel.pendingActionInput != nil {
                    viewModel.pendingActionInput!.actionType = newActionType
                    if newActionType == .call {
                        viewModel.pendingActionInput!.amount = viewModel.callAmountForPendingPlayer
                    } else if newActionType == .fold || newActionType == .check {
                        viewModel.pendingActionInput!.amount = nil
                    } else if newActionType == .bet || newActionType == .raise {
                        if viewModel.pendingActionInput!.amount == nil || viewModel.pendingActionInput!.amount == 0 {
                            viewModel.pendingActionInput!.amount = viewModel.minBetRaiseAmountForPendingPlayer
                        }
                    }
                }
            }
        )
        
        let canCommit = pendingAction.actionType != .bet && pendingAction.actionType != .raise || 
                      (pendingAction.amount ?? 0) >= viewModel.minBetRaiseAmountForPendingPlayer
        
        let heroStack = viewModel.players.first(where: { $0.isHero })?.stack ?? 0
        
        let sliderBinding = Binding<Double>(
            get: { viewModel.pendingActionInput?.amount ?? viewModel.minBetRaiseAmountForPendingPlayer },
            set: { newValue in 
                if viewModel.pendingActionInput != nil {
                    let clampedValue = max(viewModel.minBetRaiseAmountForPendingPlayer, min(newValue, heroStack))
                    viewModel.pendingActionInput!.amount = clampedValue
                }
            }
        )
        
        // Pending action UI
        VStack(spacing: 8) {
            // Header with player name
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(colorForPlayer(name: pendingAction.playerName))
                        .frame(width: 7, height: 7)
                    
                    Text(pendingAction.playerName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                
                Text("TO ACT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentGreen)
                    .tracking(0.8)
                
                Spacer()
            }
            
            // Action buttons in a row
            HStack(spacing: 6) {
                ForEach(viewModel.legalActionsForPendingPlayer, id: \.self) { action in
                    Button(action: {
                        actionTypeBinding.wrappedValue = action
                    }) {
                        Text(action.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(pendingAction.actionType == action ? .white : .textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(pendingAction.actionType == action ? 
                                          actionColor(for: action) : Color.tertiaryBackground)
                            )
                    }
                }
            }
            
            // Amount controls for bet/raise
            if pendingAction.actionType == .bet || pendingAction.actionType == .raise {
                VStack(spacing: 4) {
                    // Slider with amount display
                    HStack {
                        // TextField for bet amount
                        let actingPlayerPositionForField = pendingAction.playerName
                        let actingPlayerStackForField = viewModel.players.first(where: { $0.position == actingPlayerPositionForField })?.stack ?? 0
                        let minBetAmountForField = viewModel.minBetRaiseAmountForPendingPlayer

                        TextField("Amount", value: Binding(
                            get: { viewModel.pendingActionInput?.amount ?? 0.0 },
                            set: { newValue in
                                if viewModel.pendingActionInput != nil {
                                    let clampedValue = max(minBetAmountForField, min(newValue, actingPlayerStackForField))
                                    viewModel.pendingActionInput!.amount = clampedValue
                                }
                            }
                        ), formatter: doubleFormatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .focused($isBetAmountFieldFocused)
                            .onSubmit {
                                isBetAmountFieldFocused = false // Dismiss keyboard on standard submit (if keyboard type allows)
                            }
                            .toolbar { // Toolbar for the keyboard
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer() // Push button to the right
                                    Button("Done") {
                                        isBetAmountFieldFocused = false // Dismiss keyboard
                                    }
                                }
                            }
                        
                        Spacer()
                        
                        // Quick bet buttons
                        HStack(spacing: 4) {
                            quickBetButton(label: "Min", amount: viewModel.minBetRaiseAmountForPendingPlayer)
                            quickBetButton(label: "½", amount: potForStreet(viewModel.currentActionStreet) * 0.5)
                            quickBetButton(label: "Pot", amount: potForStreet(viewModel.currentActionStreet))
                            quickBetButton(label: "2×", amount: potForStreet(viewModel.currentActionStreet) * 2)
                        }
                    }
                    
                    // Slider
                    let actingPlayerPosition = pendingAction.playerName
                    let actingPlayerStack = viewModel.players.first(where: { $0.position == actingPlayerPosition })?.stack ?? 0
                    let sliderLowerBound = viewModel.minBetRaiseAmountForPendingPlayer
                    let sliderUpperBound = max(sliderLowerBound, actingPlayerStack)

                    Slider(
                        value: sliderBinding,
                        in: sliderLowerBound...sliderUpperBound,
                        step: 1
                    )
                    .accentColor(Color.accentGreen)
                }
            } else if pendingAction.actionType == .call {
                // Call amount display
                HStack {
                    Text("Call amount:")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    
                    Spacer()
                    
                    Text("$\(String(format: "%.0f", viewModel.callAmountForPendingPlayer))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentGreen)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Color.tertiaryBackground)
                        .cornerRadius(4)
                }
            }
            
            // Commit button
            Button(action: { viewModel.commitPendingAction() }) {
                Text("COMMIT")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [canCommit ? Color.accentGreen : Color.gray,
                                                       canCommit ? Color.accentGreen.opacity(0.7) : Color.gray.opacity(0.7)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(6)
            }
            .disabled(!canCommit)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentGreen.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    // Quick bet button
    private func quickBetButton(label: String, amount: Double) -> some View {
        Button(action: {
            viewModel.pendingActionInput?.amount = amount
        }) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentGreen.opacity(0.6))
                )
        }
    }
    
    // Helper to get appropriate icon for action type
    @ViewBuilder
    private func actionIcon(for type: PokerActionType) -> some View {
        switch type {
        case .fold:
            Image(systemName: "x.circle")
                .font(.system(size: 11))
        case .check:
            Image(systemName: "hand.tap")
                .font(.system(size: 11))
        case .call:
            Image(systemName: "equal.circle")
                .font(.system(size: 11))
        case .bet:
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 11))
        case .raise:
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 11))
        }
    }
    
    // Helper to get color for action type
    private func actionColor(for type: PokerActionType) -> Color {
        switch type {
        case .fold:
            return .accentRed
        case .check:
            return .textPrimary
        case .call:
            return .accentBlue
        case .bet:
            return .accentGreen
        case .raise:
            return .accentOrange
        }
    }
    
    // Helper to get pot amount for a street
    private func potForStreet(_ street: StreetIdentifier) -> Double {
        switch street {
        case .preflop:
            return viewModel.currentPotPreflop
        case .flop:
            return viewModel.currentPotFlop
        case .turn:
            return viewModel.currentPotTurn
        case .river:
            return viewModel.currentPotRiver
        }
    }
    
    @ViewBuilder
    private func cardSelectorSheet(for target: CardSelectionTarget) -> some View {
        switch target {
        case .heroHand:
            enhancedCardSelector(
                quantity: .pair,
                title: target.title,
                initialUsedCards: viewModel.usedCardsExcludingHeroHand,
                currentSelections: [viewModel.heroCard1, viewModel.heroCard2],
                onComplete: { cards in
                    // Safe array access
                    viewModel.heroCard1 = cards.count > 0 ? cards[0] : nil
                    viewModel.heroCard2 = cards.count > 1 ? cards[1] : nil
                }
            )
        case .flopTriplet:
            enhancedCardSelector(
                quantity: .triple,
                title: target.title,
                initialUsedCards: viewModel.usedCards,
                currentSelections: [viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3],
                onComplete: { cards in
                    // Safe array access
                    viewModel.flopCard1 = cards.count > 0 ? cards[0] : nil
                    viewModel.flopCard2 = cards.count > 1 ? cards[1] : nil
                    viewModel.flopCard3 = cards.count > 2 ? cards[2] : nil
                }
            )
        case .turnCard:
            enhancedCardSelector(
                quantity: .single,
                title: target.title,
                initialUsedCards: viewModel.usedCards,
                currentSelections: [viewModel.turnCard],
                onComplete: { cards in 
                    viewModel.turnCard = cards.count > 0 ? cards[0] : nil 
                }
            )
        case .riverCard:
            enhancedCardSelector(
                quantity: .single,
                title: target.title,
                initialUsedCards: viewModel.usedCards,
                currentSelections: [viewModel.riverCard],
                onComplete: { cards in 
                    viewModel.riverCard = cards.count > 0 ? cards[0] : nil 
                }
            )
        case .villainHand(let playerId):
            if let playerIndex = viewModel.players.firstIndex(where: { $0.id == playerId }) {
                enhancedCardSelector(
                    quantity: .pair,
                    title: target.title,
                    initialUsedCards: viewModel.usedCardsExcludingPlayer(playerId: playerId),
                    currentSelections: [viewModel.players[playerIndex].card1, viewModel.players[playerIndex].card2],
                    onComplete: { cards in
                        // Safe array access
                        let card1 = cards.count > 0 ? cards[0] : nil
                        let card2 = cards.count > 1 ? cards[1] : nil
                        viewModel.updatePlayerCards(playerId: playerId, card1: card1, card2: card2)
                    }
                )
            }
        }
    }
    
    // Enhanced card selector with a more visual layout
    @ViewBuilder
    private func enhancedCardSelector(
        quantity: CardSelectorSheetView.SelectionQuantity,
        title: String,
        initialUsedCards: Set<String>,
        currentSelections: [String?],
        onComplete: @escaping ([String?]) -> Void
    ) -> some View {
        // Just wrap the existing card selector with a more visually appealing frame
        CardSelectorSheetView(
            quantity: quantity,
            title: title,
            initialUsedCards: initialUsedCards,
            currentSelections: currentSelections,
            onComplete: onComplete
        )
        .background(Color.primaryBackground)
    }
    
    private func saveHand() {
        isSaving = true
        viewModel.errorMessage = nil

        Task {
            if let handToSave = viewModel.createParsedHandHistory() {
                do {
                    // Use the view model's sessionId or the view's sessionId for saving
                    try await handStore.saveHand(handToSave, sessionId: self.sessionId ?? viewModel.sessionId)
                    await MainActor.run {
                        isSaving = false
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isSaving = false
                        viewModel.errorMessage = "Error saving hand: \(error.localizedDescription)"
                    }
                }
            } else {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
    
    // Helper function to get color for player
    private func colorForPlayer(name: String) -> Color {
        switch name {
        case "SB": return .accentBlue
        case "BB": return .accentGreen
        case "UTG": return .accentOrange
        case "MP": return .accentPurple
        case "CO": return Color.yellow
        case "BTN": return Color.cyan
        default: return .accentBlue
        }
    }

    // Add back table setup sheet
    private var tableSetupSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("BLINDS")) {
                    HStack {
                        Text("Small Blind")
                        Spacer()
                        TextField("1", value: $viewModel.smallBlind, formatter: doubleFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Big Blind")
                        Spacer()
                        TextField("2", value: $viewModel.bigBlind, formatter: doubleFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
                
                Section(header: Text("TABLE SIZE")) {
                    Picker("Table Size", selection: $viewModel.tableSize) {
                        Text("2-max").tag(2)
                        Text("6-max").tag(6)
                        Text("9-max").tag(9)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("EFFECTIVE STACK")) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("100", value: $viewModel.effectiveStackAmount, formatter: doubleFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onChange(of: viewModel.effectiveStackAmount) { _ in
                                viewModel.updatePlayerStacksBasedOnEffectiveStack()
                            }
                    }
                }
            }
            .navigationTitle("Game Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingTableSetup = false
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // Update color function to use more green
    private func colorForStreet(_ street: StreetIdentifier) -> Color {
        switch street {
        case .preflop: return .accentBlue
        case .flop: return .accentGreen
        case .turn: return .accentOrange
        case .river: return .accentPurple
        }
    }

    private func streetHasCards(_ street: StreetIdentifier) -> Bool {
        switch street {
        case .preflop:
            return true // Preflop always has content
        case .flop:
            return viewModel.flopCard1 != nil || viewModel.flopCard2 != nil || viewModel.flopCard3 != nil
        case .turn:
            return viewModel.turnCard != nil
        case .river:
            return viewModel.riverCard != nil
        }
    }

    // Add back the missing street content views
    private var preflopContent: some View {
        VStack(spacing: 10) {
            // Preflop actions
            displayActionsList(
                actions: viewModel.preflopActions,
                street: .preflop
            )
        }
    }

    private var flopContent: some View {
        VStack(spacing: 10) {
            // Flop cards - elegant display
            Button(action: { cardSelectionTarget = .flopTriplet }) {
                HStack(spacing: 8) {
                    ForEach([viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3], id: \.self) { card in
                        let (symbol, color) = cardSymbol(for: card)
                        Text(symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(color)
                            .frame(width: 42, height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cardBackground)
                                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                viewModel.waitingForNextStreetCards && viewModel.nextStreetNeeded == .flop
                                                ? Color.accentGreen.opacity(0.8) : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            )
                    }
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Divider()
                .background(Color.dividerColor)
                .padding(.vertical, 5)
            
            // Flop actions
            displayActionsList(
                actions: viewModel.flopActions,
                street: .flop
            )
        }
    }

    private var turnContent: some View {
        VStack(spacing: 10) {
            // Board cards (flop + turn)
            HStack(spacing: 8) {
                // Flop cards (smaller and dimmed)
                ForEach([viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3], id: \.self) { card in
                    let (symbol, color) = cardSymbol(for: card)
                    Text(symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(color.opacity(0.7))
                        .frame(width: 36, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.cardBackground.opacity(0.7))
                        )
                }
                
                Spacer()
                    .frame(width: 10)
                
                // Turn card (highlighted)
                Button(action: { cardSelectionTarget = .turnCard }) {
                    let (symbol, color) = cardSymbol(for: viewModel.turnCard)
                    Text(symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(color)
                        .frame(width: 42, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.cardBackground)
                                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            viewModel.waitingForNextStreetCards && viewModel.nextStreetNeeded == .turn
                                            ? Color.accentGreen.opacity(0.8) : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        )
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .center)
            
            Divider()
                .background(Color.dividerColor)
                .padding(.vertical, 5)
            
            // Turn actions
            displayActionsList(
                actions: viewModel.turnActions,
                street: .turn
            )
        }
    }

    private var riverContent: some View {
        VStack(spacing: 10) {
            // Board cards (flop + turn + river)
            HStack(spacing: 8) {
                // Flop cards (smaller and dimmed)
                ForEach([viewModel.flopCard1, viewModel.flopCard2, viewModel.flopCard3], id: \.self) { card in
                    let (symbol, color) = cardSymbol(for: card)
                    Text(symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(color.opacity(0.7))
                        .frame(width: 30, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.cardBackground.opacity(0.7))
                        )
                }
                
                // Turn card (dimmed)
                let (turnSymbol, turnColor) = cardSymbol(for: viewModel.turnCard)
                Text(turnSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(turnColor.opacity(0.7))
                    .frame(width: 30, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.cardBackground.opacity(0.7))
                    )
                
                Spacer()
                    .frame(width: 8)
                
                // River card (highlighted)
                Button(action: { cardSelectionTarget = .riverCard }) {
                    let (symbol, color) = cardSymbol(for: viewModel.riverCard)
                    Text(symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(color)
                        .frame(width: 42, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.cardBackground)
                                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            viewModel.waitingForNextStreetCards && viewModel.nextStreetNeeded == .river
                                            ? Color.accentGreen.opacity(0.8) : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        )
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .center)
            
            Divider()
                .background(Color.dividerColor)
                .padding(.vertical, 5)
            
            // River actions
            displayActionsList(
                actions: viewModel.riverActions,
                street: .river
            )
        }
    }
}

// Extension for StreetIdentifier to get next street
extension StreetIdentifier {
    var next: StreetIdentifier {
        switch self {
        case .preflop: return .flop
        case .flop: return .turn
        case .turn: return .river
        case .river: return .river // No next street after river
        }
    }
}

// Modern card style view modifier
extension Text {
    func modernCardStyle(isPlaceholder: Bool = false, isSmall: Bool = false) -> some View {
        self
            .font(.system(size: isSmall ? 13 : 15, weight: .bold))
            .frame(width: isSmall ? 24 : 32, height: isSmall ? 24 : 32)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isPlaceholder ? Color.cardBackground.opacity(0.3) : Color.cardBackground)
            )
            .foregroundColor(isPlaceholder ? Color.textSecondary : Color.textPrimary)
    }
    
    func cardDisplayModifier(isPlaceholder: Bool = false) -> some View {
        self
            .padding(5)
            .frame(minWidth: 35)
            .background(Color.gray.opacity(isPlaceholder ? 0.1 : 0.25))
            .cornerRadius(3)
            .lineLimit(1)
            .foregroundColor(isPlaceholder ? .gray : .primary)
    }
}

// Fun group box style
struct FunGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .padding(.leading, 8)
            
            VStack(alignment: .leading) {
                configuration.content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.secondaryBackground, Color(white: 0.11)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
        }
    }
}

// More compact group box style
struct CompactGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
                .padding(.leading, 6)
            
            VStack(alignment: .leading) {
                configuration.content
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondaryBackground)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
}

// Original Card Text Display Modifier - kept for backwards compatibility
struct CardTextDisplayModifier: ViewModifier {
    var isPlaceholder: Bool = false
    var isButton: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(isButton ? 5 : 3)
            .frame(minWidth: isButton ? 30 : 25, idealWidth: isButton ? 40 : 30, maxWidth: isButton ? 50 : 35,
                   minHeight: isButton ? 30 : 20, idealHeight: isButton ? 30 : 25, maxHeight: isButton ? 30 : 30)
            .background(Color.gray.opacity(isPlaceholder ? 0.1 : (isButton ? 0.2 : 0.15)))
            .cornerRadius(isButton ? 5 : 3)
            .lineLimit(1)
            .font(isButton ? .body : .caption)
            .foregroundColor(isPlaceholder ? .gray : (isButton ? .white : .primary))
    }
}

// Extension for NumberFormatter.currency
extension NumberFormatter {
    static var currency: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }
}

struct NewHandEntryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NewHandEntryView(sessionId: "previewSessionId") // Pass a dummy sessionId for preview
                .preferredColorScheme(.dark)
        }
    }
} 
