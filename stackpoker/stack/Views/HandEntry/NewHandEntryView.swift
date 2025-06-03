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
    static let sectionHeader = Color(red: 0.4, green: 0.7, blue: 1.0) // Changed to a nice blue
    static let dividerColor = Color(white: 0.2)
    // Suit colors
    static let spadeColor = Color.white
    static let heartColor = Color.red
    static let diamondColor = Color(red: 0.3, green: 0.7, blue: 1.0) // A light blue for diamonds
    static let clubColor = Color(red: 0.3, green: 0.9, blue: 0.4)   // A distinct green for clubs
}

// Helper for applying a glassy section style
struct GlassySectionModifier: ViewModifier {
    var cornerRadius: CGFloat = 14 // Consistent with original panel
    var materialOpacity: Double = 0.25 // Slightly more pronounced material
    var glassOpacity: Double = 0.02   // Subtle white overlay

    func body(content: Content) -> some View {
        content
            .padding() // Add internal padding to the content before applying background
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(glassOpacity))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1) // Subtle border
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassySectionStyle() -> some View {
        self.modifier(GlassySectionModifier())
    }
}

// New Enum for multi-step entry process
enum HandEntryStep: Identifiable {
    case gameSetup
    case llmInput
    case summary

    var id: Int { hashValue }
}

struct NewHandEntryView: View {
    @StateObject var viewModel: NewHandEntryViewModel
    @StateObject private var handStore = HandStore(userId: Auth.auth().currentUser?.uid ?? "")
    @Environment(\.presentationMode) var presentationMode
    @State private var isSaving = false
    @State private var cardSelectionTarget: CardSelectionTarget? = nil
    @State private var showingTableSetup = false
    @FocusState private var isBetAmountFieldFocused: Bool
    @State private var playLottieAnimation = false
    
    // State for managing the current step in the hand entry process
    @State private var currentStep: HandEntryStep = .gameSetup
    
    private let sessionId: String?

    init(sessionId: String? = nil) {
        self.sessionId = sessionId
        _viewModel = StateObject(wrappedValue: NewHandEntryViewModel(sessionId: sessionId))
    }
    
    private var doubleFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = nil  // Remove minimum constraint to allow deletion
        formatter.maximum = 999999  // Allow large stack sizes
        formatter.usesGroupingSeparator = false  // Prevent comma separators that might cause issues
        formatter.allowsFloats = true
        formatter.generatesDecimalNumbers = false
        return formatter
    }
    
    private var optionalDoubleFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.allowsFloats = true
        formatter.generatesDecimalNumbers = false
        // No minimum or maximum - allows completely empty values
        return formatter
    }
    
    // Helper to create optional bindings for the blind inputs
    private var smallBlindBinding: Binding<Double?> {
        Binding<Double?>(
            get: { viewModel.smallBlind == 0 ? nil : viewModel.smallBlind },
            set: { viewModel.smallBlind = $0 ?? 0 }
        )
    }
    
    private var bigBlindBinding: Binding<Double?> {
        Binding<Double?>(
            get: { viewModel.bigBlind == 0 ? nil : viewModel.bigBlind },
            set: { viewModel.bigBlind = $0 ?? 0 }
        )
    }
    
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
            AppBackgroundView().edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Custom Navigation / Title Bar
                HStack {
                    if currentStep != .gameSetup { // Show back button for steps after game setup
                        Button(action: { navigateBack() }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(Color.textSecondary)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .padding(.leading)
                    }
                    Spacer()
                    Text(titleForStep(currentStep))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    // Close button always visible
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Color.textSecondary)
                            .font(.system(size: 16))
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 10)
                .frame(height: 50)
                .background(Color.secondaryBackground.opacity(0.5))
                // .overlay(Divider(), alignment: .bottom) // Optional divider

                // Main content based on current step
                switch currentStep {
                case .gameSetup:
                    gameSetupScreenView
                case .llmInput:
                    llmInputScreenView
                case .summary:
                    summaryScreenView
                }
            }
            
            // NEW: Full-screen Lottie loading view
            if viewModel.isParsingLLM {
                ZStack {
                    // Color.black.edgesIgnoringSafeArea(.all) // Full screen black background
                    AppBackgroundView().edgesIgnoringSafeArea(.all) // USE AppBackgroundView
                    VStack {
                        LottieView(name: "lottie_white", loopMode: .loop, play: $playLottieAnimation)
                            // .frame(width: 250, height: 250) // REMOVED to allow full screen
                        Text("Parsing hand...")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.top, 20)
                    }
                }
                .zIndex(1) // Ensure it's on top
                .onAppear {
                    self.playLottieAnimation = true
                }
                .onDisappear {
                    self.playLottieAnimation = false
                }
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside of input fields
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(item: $cardSelectionTarget) { target in // Still needed if summary allows card edits
            cardSelectorSheet(for: target)
                .preferredColorScheme(.dark)
        }
        // Removed .toolbar for custom navigation handling
    }

    // MARK: - Step Navigation and Titles
    private func titleForStep(_ step: HandEntryStep) -> String {
        switch step {
        case .gameSetup: return "Game Setup"
        case .llmInput: return "Parse Hand (AI)"
        case .summary: return "Summary & Save"
        }
    }

    private func navigateBack() {
        withAnimation {
            switch currentStep {
            case .llmInput:
                currentStep = .gameSetup
            case .summary:
                currentStep = .llmInput
            default:
                break // Should not happen from a back button
            }
        }
    }

    // MARK: - Screen Views (Stubs for now, will populate)
    @ViewBuilder
    private var gameSetupScreenView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Blinds Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blinds")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.sectionHeader)
                    
                    HStack(spacing: 12) {
                        // Small Blind
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Small Blind")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                            
                            HStack(spacing: 6) {
                                Text("$")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                
                                TextField("", value: smallBlindBinding, formatter: doubleFormatter)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                        
                        // Big Blind
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Big Blind")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                            
                            HStack(spacing: 6) {
                                Text("$")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                
                                TextField("", value: bigBlindBinding, formatter: doubleFormatter)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .glassySectionStyle()
                
                // Position and Table Size Section (Side by Side)
                HStack(spacing: 16) {
                    // Hero Position
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hero Position")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.sectionHeader)
                        
                        Menu {
                            ForEach(viewModel.availablePositions, id: \.self) { position in
                                Button(position) {
                                    viewModel.heroPosition = position
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "location")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                
                                Text(viewModel.heroPosition)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Table Size
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Table Size")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.sectionHeader)
                        
                        Menu {
                            Button("2 players") { viewModel.tableSize = 2 }
                            Button("6 players") { viewModel.tableSize = 6 }
                            Button("9 players") { viewModel.tableSize = 9 }
                        } label: {
                        HStack {
                                Image(systemName: "person.2")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                
                                Text("\(viewModel.tableSize) players")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                
                            Spacer()
                                
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .glassySectionStyle()
                
                // Effective Stack Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Effective Stack")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.sectionHeader)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "banknote")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                        
                        TextField("200", value: $viewModel.effectiveStackAmount, formatter: doubleFormatter)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .onChange(of: viewModel.effectiveStackAmount) { newValue in
                                viewModel.updatePlayerStacksBasedOnEffectiveStack()
                            }
                    }
                }
                .glassySectionStyle()
                
                // Ante and Straddle Section (Side by Side when enabled)
                HStack(spacing: 16) {
                    // Ante Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ante")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.sectionHeader)
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.hasAnte.animation())
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .accentGreen))
                        }
                        
                        if viewModel.hasAnte {
                            HStack(spacing: 6) {
                                Text("$")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                
                                TextField("", value: $viewModel.ante, formatter: doubleFormatter)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Straddle Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Straddle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.sectionHeader)
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.hasStraddle.animation())
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .accentGreen))
                        }
                        
                        if viewModel.hasStraddle {
                            HStack(spacing: 6) {
                                Text("$")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                
                                TextField("", value: $viewModel.straddle, formatter: doubleFormatter)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .glassySectionStyle()
                
                Spacer(minLength: 20)
                
                // Next Button
                Button(action: {
                    withAnimation { currentStep = .llmInput }
                }) {
                    HStack(spacing: 10) {
                        Text("Next")
                            .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentBlue, Color.accentPurple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var llmInputScreenView: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero instruction section with improved design
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Hand Parser")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Describe your hand in natural language and let AI parse the actions, positions, and cards automatically.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                
                // Input section with enhanced design
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Hand History")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if !viewModel.llmInputText.isEmpty {
                            Text("\(viewModel.llmInputText.count) characters")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        // Background with subtle gradient
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .frame(minHeight: 140)
                        
                        TextEditor(text: $viewModel.llmInputText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.textPrimary)
                            .background(Color.clear)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                        
                        if viewModel.llmInputText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Describe your hand here...")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.textSecondary.opacity(0.7))
                                
                                Text("e.g., \"Hero raises to 6bb from CO with AKo, BB calls...\"")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.textSecondary.opacity(0.5))
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 140)
                    
                    // Enhanced example section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.yellow.opacity(0.8))
                            
                            Text("Example Format")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ExampleTextRow(text: "Utg raises 20 w AsKd, btn calls, bb calls w 44.")
                            ExampleTextRow(text: "Flop is A26, bb checks, utg checks, bb checks")
                            ExampleTextRow(text: "Turn is a 3, bb checks, utg bets 30, btn folds, bb calls.")
                            ExampleTextRow(text: "River is a 4, bb checks, utg checks.")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Status messages
                    if let llmError = viewModel.llmError {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Parsing Error")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text(llmError)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Enhanced parse button
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        Task {
                            await viewModel.parseHandWithLLM()
                            if viewModel.llmError == nil {
                                withAnimation {
                                    currentStep = .summary
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            if viewModel.isParsingLLM {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            
                            Text(viewModel.isParsingLLM ? "Parsing..." : "Parse Hand & Continue")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.8),
                                    Color.purple.opacity(0.6)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .disabled(viewModel.isParsingLLM || viewModel.llmInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((viewModel.isParsingLLM || viewModel.llmInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.6 : 1.0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // Helper view for example text rows
    @ViewBuilder
    private func ExampleTextRow(text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: 4)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary.opacity(0.9))
        }
    }

    @ViewBuilder
    private var summaryScreenView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review Parsed Hand")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.sectionHeader)
                    .padding(.bottom, 5)

                // Display summarized game info (from viewModel)
                summaryGameInfoView
                
                // Display players involved (from viewModel)
                summaryPlayersView

                // Display board cards (from viewModel)
                summaryBoardView
                
                // Display actions (from viewModel)
                summaryActionsView
                    
                Spacer(minLength: 30)
                    
                Button(action: saveHand) { // Existing saveHand action
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                        } else {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("SAVE HAND")
                        }
                        Spacer()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.accentGreen, Color.accentGreen.opacity(0.7)]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                }
                .disabled(isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Reused UI Components (from existing view)
    // These will be used by the new screen views
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
                            
                            TextField("", value: smallBlindBinding, formatter: doubleFormatter)
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
                            
                            TextField("", value: bigBlindBinding, formatter: doubleFormatter)
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
                        Text("2 players").tag(2)
                        Text("6 players").tag(6)
                        Text("9 players").tag(9)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(minWidth: 150, idealWidth: 180)
                }
            }

            Divider().background(Color.dividerColor.opacity(0.5)).padding(.vertical, 4)

            HStack(alignment: .top, spacing: 20) {
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
                    .frame(width: 130)
                    if viewModel.hasAnte {
                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { viewModel.ante ?? 0 },
                                set: { viewModel.ante = $0 }
                            ), in: 0...(viewModel.bigBlind * 0.5), step: 0.1)
                                .accentColor(Color.accentGreen)
                            inputField(label: "", value: $viewModel.ante, width: 50, showLabel: false)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .padding(.top, -4)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)

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
                            ), in: viewModel.bigBlind...(viewModel.bigBlind * 3), step: viewModel.bigBlind)
                                .accentColor(Color.accentGreen)
                            inputField(label: "", value: $viewModel.straddle, width: 50, showLabel: false)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .padding(.top, -4)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }

            // Hero Position (part of game setup)
                HStack(alignment: .center, spacing: 10) {
                Text("HERO IS AT:")
                    .font(.system(size: 13, weight: .semibold)) // Consistent with other labels
                            .foregroundColor(.accentGreen)
                            .lineLimit(1)
                    .frame(width: 100, alignment: .leading) // Increased width for label
                        
                Picker("Hero Position", selection: $viewModel.heroPosition) {
                            ForEach(viewModel.availablePositions, id: \.self) { position in
                                Text(position).tag(position)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                .frame(minWidth: 80, maxWidth: .infinity) // Allow picker to take available space
            }.padding(.top, 8) // Increased top padding

            // Effective Stack (part of game setup)
            HStack(spacing: 10) { // Added spacing for better visual separation
                Text("EFFECTIVE STACK:")
                    .font(.system(size: 13, weight: .semibold)) // Consistent styling
                    .foregroundColor(.accentGreen) // Use accent color for headers
                            .lineLimit(1)
                    .frame(width: 140, alignment: .leading) // Adjusted width
                        
                TextField("Amount", value: $viewModel.effectiveStackAmount, formatter: doubleFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                    .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)) // Increased padding
                    .frame(minWidth: 60, maxWidth: 80) // Adjusted frame for text field
                            .background(Color.inputBackground)
                    .cornerRadius(6)
                    .onChange(of: viewModel.effectiveStackAmount) { newValue in // Use newValue
                                viewModel.updatePlayerStacksBasedOnEffectiveStack()
                        // viewModel.effectiveStackType = .dollars // Consider if this should always reset
                    }
                Text("$") // Indicate currency unit more clearly
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            
                Spacer() // Push to left
            }.padding(.top, 8) // Increased top padding
            }
            .glassySectionStyle()
    }

    // MARK: - Summary Screen Components (New)
    @ViewBuilder
    private var summaryGameInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Details")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.sectionHeader)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Table:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(viewModel.tableSize)-max")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.textSecondary) 
                }
                
                HStack { 
                    Text("Blinds:")
                        .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                    Spacer() 
                    Text(String(format: "$%.2f / $%.2f", viewModel.smallBlind, viewModel.bigBlind))
                        .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.textSecondary)
                }
                            
                if viewModel.hasAnte, let ante = viewModel.ante { 
                    HStack { 
                        Text("Ante:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                            Spacer()
                        Text(String(format: "$%.2f", ante))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.textSecondary) 
                    } 
                }
                
                if viewModel.hasStraddle, let straddle = viewModel.straddle { 
                    HStack { 
                        Text("Straddle:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Spacer() 
                        Text(String(format: "$%.2f", straddle))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.textSecondary) 
                    } 
                }
                
                HStack { 
                    Text("Hero Position:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Spacer() 
                    Text(viewModel.heroPosition)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.sectionHeader) 
                }
                
                HStack { 
                    Text("Effective Stack:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Spacer() 
                    Text(String(format: "$%.0f", viewModel.effectiveStackAmount))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.textSecondary) 
                }
            }
        }
        .padding(16)
                        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var summaryPlayersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Players & Cards")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.sectionHeader)
            
            VStack(spacing: 10) {
                ForEach(viewModel.players.filter { $0.isActive }) { player in
                    HStack(spacing: 12) {
                        // Position and Hero indicator
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.position)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(player.isHero ? .sectionHeader : .textPrimary)
                            
                            if player.isHero {
                                Text("(Hero)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.sectionHeader.opacity(0.8))
                            }
                        }
                        .frame(width: 60, alignment: .leading)
                        
                        // Cards - make them editable
                        HStack(spacing: 8) {
                            let card1 = player.isHero ? viewModel.heroCard1 : player.card1
                            let card2 = player.isHero ? viewModel.heroCard2 : player.card2
                            
                        Button(action: {
                                if player.isHero {
                                    cardSelectionTarget = .heroHand
                                } else {
                                    cardSelectionTarget = .villainHand(playerId: player.id)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    cardDisplayView(card: card1)
                                    cardDisplayView(card: card2)
                                    
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.sectionHeader.opacity(0.7))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        
                        Spacer()
                        
                        // Stack size
                        Text(String(format: "($%.0f)", player.stack))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary.opacity(0.8))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var summaryBoardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board Cards")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.sectionHeader)
            
            VStack(spacing: 10) {
                // Flop
                HStack(spacing: 12) {
                    Text("Flop:")
                        .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                        .frame(width: 50, alignment: .leading)
                    
                    Button(action: {
                        cardSelectionTarget = .flopTriplet
                    }) {
                    HStack(spacing: 4) {
                            cardDisplayView(card: viewModel.flopCard1)
                            cardDisplayView(card: viewModel.flopCard2)
                            cardDisplayView(card: viewModel.flopCard3)
                            
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.sectionHeader.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    
                    Spacer()
                }
                
                // Turn
                HStack(spacing: 12) {
                    Text("Turn:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .frame(width: 50, alignment: .leading)
                    
                    Button(action: {
                        cardSelectionTarget = .turnCard
                    }) {
                        HStack(spacing: 4) {
                            cardDisplayView(card: viewModel.turnCard)
                            
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.sectionHeader.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    
                                Spacer()
                }
                
                // River
                HStack(spacing: 12) {
                    Text("River:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .frame(width: 50, alignment: .leading)
                    
                                Button(action: {
                        cardSelectionTarget = .riverCard
                    }) {
                        HStack(spacing: 4) {
                            cardDisplayView(card: viewModel.riverCard)
                            
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.sectionHeader.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var summaryActionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions Log")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.sectionHeader)

            VStack(spacing: 8) {
                if !viewModel.preflopActions.isEmpty {
                    DisclosureGroup("Preflop (Pot: \(String(format: "$%.0f", viewModel.currentPotPreflop)))") {
                        VStack(spacing: 4) {
                            ForEach(viewModel.preflopActions) { action in 
                                summaryActionRow(action) 
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                }
                
                if !viewModel.flopActions.isEmpty {
                    DisclosureGroup("Flop (Pot: \(String(format: "$%.0f", viewModel.currentPotFlop)))") {
                        VStack(spacing: 4) {
                            ForEach(viewModel.flopActions) { action in 
                                summaryActionRow(action) 
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
                
                if !viewModel.turnActions.isEmpty {
                    DisclosureGroup("Turn (Pot: \(String(format: "$%.0f", viewModel.currentPotTurn)))") {
                        VStack(spacing: 4) {
                            ForEach(viewModel.turnActions) { action in 
                                summaryActionRow(action) 
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                }
                
                if !viewModel.riverActions.isEmpty {
                    DisclosureGroup("River (Pot: \(String(format: "$%.0f", viewModel.currentPotRiver)))") {
                VStack(spacing: 4) {
                            ForEach(viewModel.riverActions) { action in 
                                summaryActionRow(action) 
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private func summaryActionRow(_ action: ActionInput) -> some View {
        HStack(spacing: 8) {
            Text("\(action.playerName):")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(viewModel.players.first(where: {$0.position == action.playerName})?.isHero ?? false ? .sectionHeader : .textPrimary)
            
            Text(action.actionType.rawValue.capitalized)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(actionColor(for: action.actionType))
            
            if let amount = action.amount, amount > 0 {
                Text(String(format: "$%.2f", amount))
                    .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
            }
                    
                    Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
    }

    // Helper view for displaying individual cards
    @ViewBuilder
    private func cardDisplayView(card: String?) -> some View {
        if let card = card {
            let (cardText, cardColor) = cardSymbol(for: card)
            Text(cardText)
                    .font(.system(size: 14, weight: .bold))
                .foregroundColor(cardColor)
                .frame(width: 28, height: 20)
                    .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(cardColor.opacity(0.3), lineWidth: 1)
                        )
                )
        } else {
            Text("?")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textSecondary.opacity(0.5))
                .frame(width: 28, height: 20)
        .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))
                .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
        }
    }

    // Helper for styled input fields
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                .frame(width: width)
                .background(Color.inputBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.dividerColor.opacity(0.7), lineWidth: 0.5)
                )
        }
    }
    
    private func optionalBinding(for binding: Binding<Double>) -> Binding<Double?> {
        Binding<Double?>(
            get: { binding.wrappedValue },
            set: { newValue in binding.wrappedValue = newValue ?? 0 }
        )
    }
    
    @ViewBuilder
    private func inputField(label: String, value: Binding<Double>, width: CGFloat = 50, showLabel: Bool = true) -> some View {
        inputField(label: label, value: optionalBinding(for: value), width: width, showLabel: showLabel)
    }

    // Card Selector Sheet
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
                        let card1 = cards.count > 0 ? cards[0] : nil
                        let card2 = cards.count > 1 ? cards[1] : nil
                        viewModel.updatePlayerCards(playerId: playerId, card1: card1, card2: card2)
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func enhancedCardSelector(
        quantity: CardSelectorSheetView.SelectionQuantity,
        title: String,
        initialUsedCards: Set<String>,
        currentSelections: [String?],
        onComplete: @escaping ([String?]) -> Void
    ) -> some View {
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
