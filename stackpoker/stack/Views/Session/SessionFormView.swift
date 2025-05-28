import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Session Type Picker
// enum SessionLogType: String, CaseIterable, Identifiable { // This will be moved
//     case cashGame = "CASH GAME"
//     case tournament = "TOURNAMENT"
//     var id: String { self.rawValue }
// }

struct GameOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let stakes: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Game Type Section
struct GameTypeSelector: View {
    let gameTypes: [String]
    @Binding var selectedGameType: Int
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<gameTypes.count, id: \.self) { index in
                Button(action: { selectedGameType = index }) {
                    Text(gameTypes[index])
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedGameType == index ? .white : .gray)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Game Selection Section
struct GameSelectionSection: View {
    let gameOptions: [GameOption]
    @Binding var selectedGame: GameOption?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Game")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading, 2)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(gameOptions) { game in
                        GameOptionCard(
                            game: game,
                            isSelected: selectedGame?.id == game.id,
                            action: { selectedGame = game }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Time & Duration Section
struct TimeAndDurationSection: View {
    @Binding var startDate: Date
    @Binding var startTime: Date
    @Binding var endTime: Date
    let calculatedHoursPlayed: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time & Duration")
                .font(.plusJakarta(.headline, weight: .medium))
                .foregroundColor(primaryTextColor)
                .padding(.leading, 6)
                .padding(.bottom, 2)
            
            // Date and Time Grid
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    GlassyInputField(
                        icon: "calendar",
                        title: "Start Date",
                        glassOpacity: glassOpacity,
                        labelColor: secondaryTextColor,
                        materialOpacity: materialOpacity
                    ) {
                        DatePickerContent(date: $startDate, displayMode: .date)
                    }
                    
                    GlassyInputField(
                        icon: "clock",
                        title: "Start Time",
                        glassOpacity: glassOpacity,
                        labelColor: secondaryTextColor,
                        materialOpacity: materialOpacity
                    ) {
                        DatePickerContent(date: $startTime, displayMode: .hourAndMinute)
                    }
                }
                
                HStack(spacing: 12) {
                    GlassyInputField(
                        icon: "timer",
                        title: "Hours Played",
                        glassOpacity: glassOpacity,
                        labelColor: secondaryTextColor,
                        materialOpacity: materialOpacity
                    ) {
                        TextFieldContent(text: .constant(calculatedHoursPlayed), placeholder: "", isReadOnly: true, textColor: primaryTextColor)
                    }
                    
                    GlassyInputField(
                        icon: "clock",
                        title: "End Time",
                        glassOpacity: glassOpacity,
                        labelColor: secondaryTextColor,
                        materialOpacity: materialOpacity
                    ) {
                        DatePickerContent(date: $endTime, displayMode: .hourAndMinute)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Game Info Section
struct GameInfoSection: View {
    @Binding var buyIn: String
    @Binding var cashout: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Info")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading, 2)
            
            VStack(spacing: 16) {
                // Enhanced Buy-in field
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.gray)
                        Text("Buy in")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 18, weight: .semibold))
                        
                        TextField("0.00", text: $buyIn)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Enhanced Cashout field
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.gray)
                    Text("Cashout")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 18, weight: .semibold))
                        
                        TextField("0.00", text: $cashout)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 44)
                        
                        // Show profit/loss preview if both fields have values
                        if let buyInValue = Double(buyIn), let cashoutValue = Double(cashout) {
                            let profit = cashoutValue - buyInValue
                            let isProfit = profit >= 0
                            
                            Text(String(format: "%@$%.2f", isProfit ? "+" : "", profit))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isProfit ? 
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                    Color.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isProfit ? 
                                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.2)) : 
                                            Color.red.opacity(0.2))
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Tournament Info Section
struct TournamentInfoSection: View {
    @Binding var tournamentName: String
    var onSelectFromEvents: () -> Void // Closure to signal event selection request

    // Colors & Font (assuming these are accessible or passed in if needed)
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94)
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84)
    private let glassOpacity = 0.01
    private let materialOpacity = 0.2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tournament Details")
                    .font(.plusJakarta(.headline, weight: .medium))
                    .foregroundColor(primaryTextColor)
                Spacer()
                Button(action: { 
                    // print("Select from Events button tapped in TournamentInfoSection")
                    onSelectFromEvents() // Call the closure
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Select from Events")
                    }
                    .font(.plusJakarta(.caption, weight: .semibold))
                    .foregroundColor(primaryTextColor.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 6) // Ensure padding for the button too
            .padding(.bottom, 2)

            VStack(spacing: 12) {
                GlassyInputField(
                    icon: "trophy",
                    title: "Tournament Name",
                    glassOpacity: glassOpacity,
                    labelColor: secondaryTextColor,
                    materialOpacity: materialOpacity
                ) {
                    TextFieldContent(text: $tournamentName, placeholder: "Enter tournament name...", textColor: primaryTextColor)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Buy-in with Rebuy Stepper Component
struct BuyInWithRebuyField: View {
    @Binding var totalBuyIn: String
    @Binding var rebuyCount: Int
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    
    // Calculate base buy-in per rebuy
    private var baseBuyInAmount: Double {
        let total = Double(totalBuyIn) ?? 0
        return rebuyCount > 0 ? total / Double(rebuyCount) : total
    }
    
    // Add one rebuy (increase total by base amount)
    private func addRebuy() {
        let currentTotal = Double(totalBuyIn) ?? 0
        if rebuyCount == 1 && currentTotal > 0 {
            // First time hitting +, use current amount as base and double it
            let newTotal = currentTotal * 2
            totalBuyIn = String(format: "%.2f", newTotal)
            rebuyCount = 2
        } else if rebuyCount > 1 && currentTotal > 0 {
            // Add one more rebuy worth
            let baseAmount = currentTotal / Double(rebuyCount)
            let newTotal = currentTotal + baseAmount
            totalBuyIn = String(format: "%.2f", newTotal)
            rebuyCount += 1
        }
    }
    
    // Remove one rebuy (decrease total by base amount)
    private func removeRebuy() {
        if rebuyCount > 1 {
            let currentTotal = Double(totalBuyIn) ?? 0
            let baseAmount = currentTotal / Double(rebuyCount)
            let newTotal = currentTotal - baseAmount
            totalBuyIn = String(format: "%.2f", newTotal)
            rebuyCount -= 1
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(secondaryTextColor)
                    .font(.system(size: 16))
                Text("Total Buy-in")
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            
            HStack(spacing: 0) {
                // Dollar sign prefix
                Text("$")
                    .font(.plusJakarta(.body, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .padding(.leading, 20) // Increased padding to move text field right
                
                // Buy-in text field
                TextField("0.00", text: $totalBuyIn)
                    .keyboardType(.decimalPad)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 4) // Small additional padding
                
                // Rebuy stepper section
                VStack(spacing: 2) {
                    Text("\(rebuyCount) rebuy\(rebuyCount == 1 ? "" : "s")")
                        .font(.plusJakarta(.caption2, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            removeRebuy()
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(rebuyCount > 1 ? primaryTextColor.opacity(0.8) : secondaryTextColor.opacity(0.5))
                                .font(.system(size: 20))
                        }
                        .disabled(rebuyCount <= 1)
                        
                        Button(action: {
                            if rebuyCount < 10 {
                                addRebuy()
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(rebuyCount < 10 ? primaryTextColor.opacity(0.8) : secondaryTextColor.opacity(0.5))
                                .font(.system(size: 20))
                        }
                        .disabled(rebuyCount >= 10)
                    }
                }
                .padding(.trailing, 16)
            }
            .frame(height: 50)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(glassOpacity))
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Tournament Buy-in Section
struct TournamentBuyInSection: View {
    @Binding var baseBuyIn: String
    @Binding var rebuyCount: Int
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    
    var body: some View {
        BuyInWithRebuyField(
            totalBuyIn: $baseBuyIn,
            rebuyCount: $rebuyCount,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            glassOpacity: glassOpacity,
            materialOpacity: materialOpacity
        )
    }
}

// MARK: - SessionFormView Helper Structs/Views

// New struct for individual staker configuration
struct StakerConfig: Identifiable {
    let id = UUID()
    var searchQuery: String = ""
    var searchResults: [UserProfile] = []
    var selectedStaker: UserProfile? = nil
    var isSearching: Bool = false
    var markup: String = "1.0" // Default markup
    var percentageSold: String = ""
}

// New View for individual staker inputs
// This has been moved to ImprovedStakerInputView.swift - remove the old implementation
// struct ImprovedStakerInputView: View {... }

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss
    let userId: String
    private let db = Firestore.firestore() // Define db instance here
    
    // Form Data (Common)
    @State private var selectedLogType: SessionLogType = .cashGame // For the picker
    @State private var startDate = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var hoursPlayed = ""
    @State private var buyIn = "" // For cash game OR single tournament entry
    @State private var cashout = ""
    @State private var isLoading = false
    @State private var showingAddGame = false // For cash games
    @State private var gameToDelete: CashGame? = nil // For delete confirmation
    @State private var showingDeleteGameAlert = false // For delete confirmation

    // Cash Game Specific Data
    @State private var selectedGame: GameOption?

    // Tournament Specific Data
    @State private var tournamentName: String = ""
    @State private var showingEventSelector = false // State to control ExploreView presentation
    @State private var selectedEventSeries: String? = nil // To store series from selected event
    @State private var rebuyCount: Int = 1 // New state for rebuy count
    @State private var baseBuyIn: String = "" // Store the base buy-in amount

    // Staking State Variables - REPLACED
    // @State private var stakerSearchQuery = ""
    // @State private var stakerSearchResults: [UserProfile] = []
    // @State private var selectedStaker: UserProfile? = nil
    // @State private var isSearchingStakers = false
    // @State private var searchDebounceTimer: Timer? = nil
    // @State private var stakeMarkup = ""
    // @State private var stakePercentageSold = ""
    @State private var stakerConfigs: [StakerConfig] = [] // New state for multiple stakers

    @State private var showStakingSection = false // To toggle visibility of staking fields
    @State private var showingStakingPopup = false // New state for floating popup

    @StateObject private var cashGameService = CashGameService(userId: Auth.auth().currentUser?.uid ?? "")
    @StateObject private var stakeService = StakeService() // Add StakeService
    @StateObject private var userService = UserService() // Add UserService to potentially fetch staker by username/ID later
    
    // Colors & Font
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94) // Light cream for high contrast
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84) // Slightly darker cream
    private let glassOpacity = 0.01 // Ultra-low opacity for extreme transparency
    private let materialOpacity = 0.2 // Lower material opacity
    
    init(userId: String) {
        self.userId = userId
    }
    
    private var calculatedHoursPlayed: String {
        let calendar = Calendar.current
        let startDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                        minute: calendar.component(.minute, from: startTime),
                                        second: 0,
                                        of: startDate) ?? startDate
        
        var endDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                      minute: calendar.component(.minute, from: endTime),
                                      second: 0,
                                      of: startDate) ?? startDate
        
        // If end time is before start time, it means the session went into the next day
        if endDateTime < startDateTime {
            endDateTime = calendar.date(byAdding: .day, value: 1, to: endDateTime) ?? endDateTime
        }
        
        let components = calendar.dateComponents([.minute], from: startDateTime, to: endDateTime)
        let totalMinutes = Double(components.minute ?? 0)
        let hours = totalMinutes / 60.0
        return String(format: "%.1f", hours)
    }
    
    private func formatStakes(game: CashGame) -> String {
        var stakes = "$\(Int(game.smallBlind))/$\(Int(game.bigBlind))"
        if let straddle = game.straddle, straddle > 0 {
            stakes += " $\(Int(straddle))"
        }
        return stakes
    }
    
    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ZStack {
                    // Background
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Content
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 20) {
                                Spacer()
                                    .frame(height: 64)
                                    
                                // Session Type Picker
                                Picker("Session Type", selection: $selectedLogType) {
                                    ForEach(SessionLogType.allCases) { type in
                                        Text(type.rawValue.capitalized).tag(type)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .padding(.horizontal)
                                .padding(.bottom, 10)
                                .cornerRadius(8)
                                .onChange(of: selectedLogType) { _ in // Clear specific fields on type change
                                    if selectedLogType == .cashGame {
                                        tournamentName = ""
                                        selectedEventSeries = nil // Reset series
                                        baseBuyIn = "" // Reset base buy-in
                                        rebuyCount = 1 // Reset rebuy count
                                    } else {
                                        selectedGame = nil
                                        // When switching to tournament, if fields are empty, 
                                        // they might be populated by event selector later.
                                        // If not, they remain empty for manual input.
                                        // selectedEventSeries will be set if an event is chosen.
                                    }
                                }

                                // Game Selection Section (Conditional)
                                if selectedLogType == .cashGame {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Select Game")
                                            .font(.plusJakarta(.headline, weight: .medium))
                                            .foregroundColor(primaryTextColor)
                                            .padding(.leading, 6)
                                            .padding(.bottom, 2)
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(cashGameService.cashGames) { game in
                                                    let stakes = formatStakes(game: game)
                                                    GameCard(
                                                        stakes: stakes,
                                                        name: game.name,
                                                        isSelected: selectedGame?.name == game.name && selectedGame?.stakes == stakes,
                                                        titleColor: primaryTextColor,
                                                        subtitleColor: secondaryTextColor,
                                                        glassOpacity: glassOpacity,
                                                        materialOpacity: materialOpacity
                                                    )
                                                    .onTapGesture {
                                                        selectedGame = GameOption(
                                                            name: game.name,
                                                            stakes: stakes
                                                        )
                                                    }
                                                    .contextMenu { // Added context menu for deletion
                                                        Button(role: .destructive) {
                                                            gameToDelete = game // Store the actual CashGame object
                                                            showingDeleteGameAlert = true
                                                        } label: {
                                                            Label("Delete Game", systemImage: "trash")
                                                        }
                                                    }
                                                }
                                                // Add Game Button
                                                AddGameButton(
                                                    textColor: primaryTextColor,
                                                    glassOpacity: glassOpacity,
                                                    materialOpacity: materialOpacity
                                                )
                                                .onTapGesture {
                                                    showingAddGame = true
                                                }
                                            }
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                        }
                                    }
                                    .padding(.horizontal)
                                }

                                // Tournament Info Section (Conditional)
                                if selectedLogType == .tournament {
                                    TournamentInfoSection(
                                        tournamentName: $tournamentName,
                                        onSelectFromEvents: { // Pass the closure action
                                            self.showingEventSelector = true
                                        }
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                
                                // Time & Duration Section
                                TimeAndDurationSection(
                                    startDate: $startDate,
                                    startTime: $startTime,
                                    endTime: $endTime,
                                    calculatedHoursPlayed: calculatedHoursPlayed,
                                    primaryTextColor: primaryTextColor,
                                    secondaryTextColor: secondaryTextColor,
                                    glassOpacity: glassOpacity,
                                    materialOpacity: materialOpacity
                                )
                                .padding(.horizontal)

                                // Game Info Section
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Game Info")
                                        .font(.plusJakarta(.headline, weight: .medium))
                                        .foregroundColor(primaryTextColor)
                                        .padding(.leading, 6)
                                        .padding(.bottom, 2)
                                    
                                    VStack(spacing: 12) {
                                        // Buy-in field with rebuy picker for tournaments
                                        if selectedLogType == .tournament {
                                            TournamentBuyInSection(
                                                baseBuyIn: $baseBuyIn,
                                                rebuyCount: $rebuyCount,
                                                primaryTextColor: primaryTextColor,
                                                secondaryTextColor: secondaryTextColor,
                                                glassOpacity: glassOpacity,
                                                materialOpacity: materialOpacity
                                            )
                                        } else {
                                            GlassyInputField(
                                                icon: "dollarsign.circle",
                                                title: "Buy in",
                                                glassOpacity: glassOpacity,
                                                labelColor: secondaryTextColor,
                                                materialOpacity: materialOpacity
                                            ) {
                                                TextFieldContent(text: $buyIn, placeholder: "0.00", keyboardType: .decimalPad, prefix: "$", textColor: primaryTextColor, prefixColor: secondaryTextColor)
                                            }
                                        }
                                        
                                        GlassyInputField(
                                            icon: "dollarsign.circle",
                                            title: "Cashout",
                                            glassOpacity: glassOpacity,
                                            labelColor: secondaryTextColor,
                                            materialOpacity: materialOpacity
                                        ) {
                                            TextFieldContent(text: $cashout, placeholder: "0.00", keyboardType: .decimalPad, prefix: "$", textColor: primaryTextColor, prefixColor: secondaryTextColor)
                                        }
                                    }
                                }
                                .padding(.horizontal)

                                // Staking Section Trigger - Extracted to a computed property
                                stakingSectionTriggerButton

                                Spacer()
                            }
                        }
                        
                        // Add Session Button
                        VStack {
                            Button(action: addSession) {
                                HStack {
                                    Text(selectedLogType == .cashGame ? "Add Session" : "Add Tournament Log")
                                        .font(.plusJakarta(.body, weight: .bold))
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .padding(.leading, 8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.gray.opacity(0.7))
                                .foregroundColor(primaryTextColor)
                                .cornerRadius(27)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 34)
                        }
                        .background(Color.clear)
                        .padding(.bottom, 50)
                    }
                    .frame(width: geometry.size.width)
                }
                .navigationTitle("Past Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white) // Keep back button white
                        }
                    }
                    ToolbarItem(placement: .principal) { // For NavigationTitle font
                        Text("Past Session")
                            .font(.plusJakarta(.headline, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("Done") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            .font(.plusJakarta(.body, weight: .medium))
                            .foregroundColor(primaryTextColor)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddGame) {
            AddCashGameView(cashGameService: cashGameService)
        }
        .alert("Delete Cash Game?", isPresented: $showingDeleteGameAlert, presenting: gameToDelete) { gameToDelete in // Added delete confirmation alert
            Button("Delete \(gameToDelete.name)", role: .destructive) {
                Task {
                    do {
                        try await cashGameService.deleteCashGame(gameToDelete)
                        // Optionally clear selection if the deleted game was selected
                        if selectedGame?.name == gameToDelete.name && selectedGame?.stakes == formatStakes(game: gameToDelete) {
                            selectedGame = nil
                        }
                    } catch {

                        // Handle error (e.g., show another alert to the user)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { gameToDelete in
            Text("Are you sure you want to delete the cash game \"\(gameToDelete.name) - \(formatStakes(game: gameToDelete))\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingEventSelector) { // Present ExploreView as a sheet
            NavigationView { // Embed in NavigationView for title/toolbar if ExploreView needs it
                ExploreView(onEventSelected: { selectedEvent in
                    self.tournamentName = selectedEvent.event_name
                    
                    if let usdBuyin = selectedEvent.buyin_usd {
                        self.baseBuyIn = String(format: "%.2f", usdBuyin)
                    } else if let buyinValue = parseBuyinToDouble(selectedEvent.buyin_string) {
                        self.baseBuyIn = String(format: "%.2f", buyinValue)
                    } else {
                        self.baseBuyIn = "" // Clear or set to default if parsing fails
                    }
                    
                    // Location and Type are no longer set from the event
                    // self.tournamentLocation = "" // REMOVED state variable
                    // self.selectedTournamentType = "NLH" // REMOVED state variable

                    self.selectedEventSeries = selectedEvent.series_name // Series can still be used for other purposes if needed

                    self.selectedLogType = .tournament // Switch to tournament tab
                    self.showingEventSelector = false // Dismiss the sheet
                }, isSheetPresentation: true)
                .navigationTitle("Select Event")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") {
                            showingEventSelector = false
                        }
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(primaryTextColor)
                    }
                }
            }
        }
        .overlay(
            // Add floating staking popup overlay
            FloatingStakingPopup(
                isPresented: $showingStakingPopup,
                stakerConfigs: $stakerConfigs,
                userService: userService,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                glassOpacity: glassOpacity,
                materialOpacity: materialOpacity
            )
        )
    }
    
    // Extracted Staking Section Trigger Button
    private var stakingSectionTriggerButton: some View {
        Button(action: {
            // Add initial config if none exist
            if stakerConfigs.isEmpty {
                stakerConfigs.append(StakerConfig())
            }
            showingStakingPopup = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Staking Configuration")
                        .font(.plusJakarta(.headline, weight: .medium))
                        .foregroundColor(primaryTextColor)
                    
                    if stakerConfigs.isEmpty {
                        Text("Tap to add staking details")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    } else {
                        Text("\(stakerConfigs.count) staker\(stakerConfigs.count == 1 ? "" : "s") configured")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if !stakerConfigs.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    }
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(primaryTextColor.opacity(0.6))
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(stakerConfigs.isEmpty ? primaryTextColor.opacity(0.2) : Color.green.opacity(0.5), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    private func addSession() {
        isLoading = true
        
        let calendar = Calendar.current
        let startDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                        minute: calendar.component(.minute, from: startTime),
                                        second: 0,
                                        of: startDate) ?? startDate
        
        var endDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                      minute: calendar.component(.minute, from: endTime),
                                      second: 0,
                                      of: startDate) ?? startDate
        
        // If end time is before start time, it means the session went into the next day
        if endDateTime < startDateTime {
            endDateTime = calendar.date(byAdding: .day, value: 1, to: endDateTime) ?? endDateTime
        }
        
        let calculatedHrsPlayed = Double(calculatedHoursPlayed) ?? 0
        let finalCashout = Double(cashout) ?? 0
        
        // Calculate final buy-in based on session type
        let finalBuyIn: Double
        if selectedLogType == .tournament {
            let baseAmount = Double(baseBuyIn) ?? 0
            finalBuyIn = baseAmount * Double(rebuyCount)
        } else {
            finalBuyIn = Double(buyIn) ?? 0
        }

        var sessionDetails: [String: Any] = [
            "userId": userId,
            "startDate": Timestamp(date: startDateTime),
            "startTime": Timestamp(date: startDateTime),
            "endTime": Timestamp(date: endDateTime),
            "hoursPlayed": calculatedHrsPlayed,
            "buyIn": finalBuyIn,
            "cashout": finalCashout,
            "createdAt": FieldValue.serverTimestamp()
        ]

        var gameNameForStake: String
        var stakesForStake: String
        var isStakingTournament: Bool = false
        var tournamentTotalInvestmentForStake: Double? = nil
        var tournamentNameForStakeOptional: String? = nil

        if selectedLogType == .cashGame {
            guard let game = selectedGame else {

                isLoading = false
                // TODO: Show alert to user
                return
            }
            sessionDetails["gameType"] = selectedLogType.rawValue // "CASH GAME"
            sessionDetails["gameName"] = game.name
            sessionDetails["stakes"] = game.stakes
            sessionDetails["profit"] = finalCashout - finalBuyIn

            gameNameForStake = game.name
            stakesForStake = game.stakes
            isStakingTournament = false
            tournamentTotalInvestmentForStake = finalBuyIn // For cash games, this is just the buy-in

        } else { // Tournament Log
            guard !tournamentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                isLoading = false
                // TODO: Show alert to user
                return
            }
            let trimmedTournamentName = tournamentName.trimmingCharacters(in: .whitespacesAndNewlines)
            sessionDetails["gameType"] = selectedLogType.rawValue // "TOURNAMENT"
            sessionDetails["gameName"] = trimmedTournamentName // Tournament's name
            
            // Stakes for a tournament log will be a generic placeholder or based on buy-in.
            // Type and Location are removed.
            if let buyInDouble = Double(baseBuyIn) {
                sessionDetails["stakes"] = "$\(Int(buyInDouble)) Tournament" // e.g., "$1000 Tournament"
            } else {
                sessionDetails["stakes"] = "Tournament" // Fallback if buy-in isn't parsed
            }
            // sessionDetails["tournamentType"] = ... // REMOVED
            // sessionDetails["location"] = ... // REMOVED
            
            let totalInvestment = finalBuyIn 
            sessionDetails["profit"] = finalCashout - totalInvestment
            
            if let eventSeries = selectedEventSeries, !eventSeries.isEmpty {
                sessionDetails["series"] = eventSeries // Store series if available
            }

            gameNameForStake = trimmedTournamentName
            // For staking records, stakesForStake can be more descriptive if needed.
            stakesForStake = selectedEventSeries ?? trimmedTournamentName 
            isStakingTournament = true
            tournamentTotalInvestmentForStake = totalInvestment
            tournamentNameForStakeOptional = trimmedTournamentName
        }
        
        handleStakingAndSave(sessionDataToSave: sessionDetails, 
                             gameNameForStake: gameNameForStake, 
                             stakesForStake: stakesForStake, 
                             startDateTimeForStake: startDateTime, 
                             sessionBuyInForStake: finalBuyIn, // Original form buy-in (could be single entry if we change back)
                             sessionCashout: finalCashout,
                             isTournamentFlagForStake: isStakingTournament,
                             tournamentTotalInvestmentForStake: tournamentTotalInvestmentForStake,
                             tournamentNameForStake: tournamentNameForStakeOptional)
    }

    // Unified function to handle staking and saving
    private func handleStakingAndSave(
        sessionDataToSave: [String: Any],
        gameNameForStake: String,
        stakesForStake: String,
        startDateTimeForStake: Date,
        sessionBuyInForStake: Double, 
        sessionCashout: Double,
        isTournamentFlagForStake: Bool,
        tournamentTotalInvestmentForStake: Double?,
        tournamentNameForStake: String?
    ) {
        let actualBuyInForStaking = tournamentTotalInvestmentForStake ?? sessionBuyInForStake

        // Filter out configs that are truly empty or invalid before deciding to save session only or with stakes.
        let validConfigs = stakerConfigs.filter { config in
            guard let _ = config.selectedStaker, // Must have a staker
                  let percentage = Double(config.percentageSold), percentage > 0, // Percentage must be valid and > 0
                  let _ = Double(config.markup), // Markup must be a valid double (can be 0 or more)
                  actualBuyInForStaking > 0 else { // Session buy-in must be > 0 for staking
                return false
            }
            return true
        }

        if validConfigs.isEmpty {
            // If no valid staking configurations are provided (either stakerConfigs is empty or all entries are invalid)

            saveSessionDataOnly(sessionData: sessionDataToSave)
        } else {
            // If there are valid staking configurations

            saveSessionDataAndIndividualStakes(
                sessionData: sessionDataToSave,
                gameName: gameNameForStake,
                stakes: stakesForStake,
                startDateTime: startDateTimeForStake,
                actualSessionBuyInForStaking: actualBuyInForStaking,
                sessionCashout: sessionCashout,
                tournamentName: tournamentNameForStake,
                isTournamentStake: isTournamentFlagForStake,
                configs: validConfigs // Pass the array of valid configs
            )
        }
    }

    private func saveSessionDataOnly(sessionData: [String: Any]) {
        db.collection("sessions").addDocument(data: sessionData) { error in
            DispatchQueue.main.async {
                isLoading = false
                if error == nil {
                    dismiss()
                } else {

                    // Handle error (e.g., show an alert)
                }
            }
        }
    }

    private func saveSessionDataAndIndividualStakes( // Renamed and takes array
        sessionData: [String: Any],
        gameName: String,
        stakes: String,
        startDateTime: Date,
        actualSessionBuyInForStaking: Double,
        sessionCashout: Double,
        tournamentName: String?,
        isTournamentStake: Bool,
        configs: [StakerConfig] // Takes an array of StakerConfig
    ) {
        let newDocumentId = db.collection("sessions").document().documentID
        var mutableSessionData = sessionData
        // mutableSessionData["id"] = newDocumentId // Optional

        db.collection("sessions").document(newDocumentId).setData(mutableSessionData) { error in
            if let error = error {

                DispatchQueue.main.async {
                    isLoading = false
                    // Handle error
                }
                return
            }

            // Session/Log added successfully, now add stakes for each config
            Task {
                var allStakesSuccessful = true
                var savedStakeCount = 0

                for config in configs {
                    // Basic validation already done in handleStakingAndSave,
                    // but ensure crucial parts are still present for constructing Stake object.
                    guard let stakerProfile = config.selectedStaker,
                          let percentageSoldDouble = Double(config.percentageSold),
                          let markupDouble = Double(config.markup) else {

                        allStakesSuccessful = false
                        continue
                    }

                    let newStake = Stake(
                        sessionId: newDocumentId,
                        sessionGameName: tournamentName ?? gameName,
                        sessionStakes: stakes,
                        sessionDate: startDateTime,
                        stakerUserId: stakerProfile.id, // Use ID from config
                        stakedPlayerUserId: self.userId,
                        stakePercentage: percentageSoldDouble / 100.0, // Convert to decimal
                        markup: markupDouble,
                        totalPlayerBuyInForSession: actualSessionBuyInForStaking,
                        playerCashoutForSession: sessionCashout,
                        status: .awaitingSettlement,
                        isTournamentSession: isTournamentStake
                    )
                    do {
                        _ = try await stakeService.addStake(newStake)

                        savedStakeCount += 1
                    } catch {

                        allStakesSuccessful = false
                        // Potentially collect errors
                    }
                } // End of for loop

                DispatchQueue.main.async {
                    isLoading = false
                    if allStakesSuccessful && savedStakeCount == configs.count && savedStakeCount > 0 {

                        dismiss()
                    } else if savedStakeCount > 0 {

                        // Still dismiss as session is saved and some stakes might be too.
                        // User can verify on dashboard.
                        dismiss()
                    }
                    else {

                        // Provide more specific feedback or error handling
                        // For now, we will dismiss as the session itself was likely saved.
                        dismiss() 
                    }
                }
            } // End of Task
        } // End of setData completion
    }

    // Helper to parse buy-in string (e.g., "$1,000 + $100", "€550") to Double
    private func parseBuyinToDouble(_ buyinString: String) -> Double? {
        let currencySymbols = CharacterSet(charactersIn: "$,€£¥") // Add more as needed
        // Remove currency symbols and common separators like commas
        var cleanedString = buyinString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanedString = cleanedString.components(separatedBy: currencySymbols).joined()
        cleanedString = cleanedString.replacingOccurrences(of: ",", with: "")

        // Handle cases like "1,000 + 100" by taking the first number part
        if let mainBuyinPart = cleanedString.split(whereSeparator: { "+-/".contains($0) }).first {
            cleanedString = String(mainBuyinPart).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return Double(cleanedString)
    }
}

// Extracted View for Staking Inputs - This is now replaced by StakerInputView and the loop in SessionFormView
// struct StakingInputFieldsView: View { ... }

// MARK: - Component Views

// Game card with stakes and name
struct GameCard: View {
    let stakes: String
    let name: String
    let isSelected: Bool
    var titleColor: Color = Color(white: 0.25)
    var subtitleColor: Color = Color(white: 0.4)
    var glassOpacity: Double = 0.01
    var materialOpacity: Double = 0.2
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stakes)
                .font(.plusJakarta(.title3, weight: .bold))
                .foregroundColor(titleColor)
            
            Text(name)
                .font(.plusJakarta(.caption, weight: .medium))
                .foregroundColor(subtitleColor)
        }
        .frame(width: 130)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                // Ultra-transparent glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                // Almost invisible white overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Add game button
struct AddGameButton: View {
    var textColor: Color = Color(white: 0.25)
    var glassOpacity: Double = 0.01
    var materialOpacity: Double = 0.2
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 24)) // System font for icon
                .foregroundColor(textColor)
            
            Text("Add")
                .font(.plusJakarta(.body, weight: .medium))
                .foregroundColor(textColor)
        }
        .frame(width: 130)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                // Ultra-transparent glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                // Almost invisible white overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DatePickerContent: View {
    @Binding var date: Date
    let displayMode: DatePickerComponents
    
    var body: some View {
        DatePicker("", selection: $date, displayedComponents: displayMode)
            .labelsHidden()
            .colorScheme(.dark)
            .scaleEffect(0.95)
            .frame(height: 35)
    }
}

struct TextFieldContent: View {
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var prefix: String? = nil
    var isReadOnly: Bool = false
    var textColor: Color = .white
    var prefixColor: Color = .gray
    
    var body: some View {
        HStack {
            if let prefix = prefix {
                Text(prefix)
                    .font(.plusJakarta(.body, weight: .semibold))
                    .foregroundColor(prefixColor)
            }
            
            if isReadOnly {
                Text(text)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(textColor)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(textColor)
            }
        }
        .frame(height: 35)
    }
}

struct GameOptionCard: View {
    let game: GameOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.stakes)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text(game.name)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .frame(width: 120, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

struct DateInputField: View {
    let title: String
    let systemImage: String
    @Binding var date: Date
    let displayMode: DatePickerComponents
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            DatePicker("", selection: $date, displayedComponents: displayMode)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.5))
        )
    }
}

struct CustomInputField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            TextField("", text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.5))
        )
    }
} 
