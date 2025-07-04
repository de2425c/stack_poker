import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Shared Data Models

struct SessionConfiguration {
    let sessionType: SessionLogType
    let gameName: String
    let stakes: String
    let buyIn: Double
    let isTournament: Bool
    let tournamentDetails: TournamentDetails?
    let stakerConfigs: [StakerConfig]
    let casino: String?
    let tournamentGameType: TournamentGameType?
    let tournamentFormat: TournamentFormat?
    let tournamentStartingChips: Double?
    let pokerVariant: String?
}

struct TournamentDetails {
    let name: String
    let type: String
    let baseBuyIn: Double
}

// MARK: - Setup Delegate Protocol

protocol LiveSessionSetupDelegate: AnyObject {
    func didCompleteSetup(with configuration: SessionConfiguration)
    func didCancelSetup()
}

// MARK: - Live Session Setup View

struct LiveSessionSetupView: View {
    let userId: String
    var preselectedEvent: Event? = nil
    weak var delegate: LiveSessionSetupDelegate?
    
    // Services
    @StateObject private var cashGameService = CashGameService(userId: Auth.auth().currentUser?.uid ?? "")
    @StateObject private var stakeService = StakeService()
    @StateObject private var manualStakerService = ManualStakerService()
    @StateObject private var userService = UserService()
    
    // UI States
    @State private var selectedLogType: SessionLogType = .cashGame
    @State private var buyIn = ""
    @State private var selectedGame: CashGame? = nil
    @State private var showingAddGame = false
    
    // Tournament States
    @State private var tournamentName: String = ""
    @State private var showingEventSelector = false
    @State private var tournamentCasino: String = ""
    @State private var baseBuyInTournament: String = ""
    @State private var selectedTournamentGameType: TournamentGameType = .nlh
    @State private var selectedTournamentFormat: TournamentFormat = .standard
    @State private var tournamentStartingChips: Double = 20000
    
    // Staking States
    @State private var stakerConfigs: [StakerConfig] = []
    @State private var showStakingSection = false
    @State private var showingStakingPopup = false
    
    // Colors & Styling (matching the main app)
    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color.gray
    private let glassOpacity = 0.01
    private let materialOpacity = 0.2
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Session Type Picker
                            sessionTypePicker
                            
                            // Conditional Content Based on Session Type
                            if selectedLogType == .cashGame {
                                cashGameSetupSection
                            } else {
                                tournamentSetupSection
                            }
                            
                            // Buy-in Section
                            buyInSection
                            
                            // Staking Section Trigger
                            stakingSectionTrigger
                            
                            // Spacer for bottom padding
                            Spacer()
                                .frame(height: 40)
                        }
                        .padding(.top, 5)
                        .padding(.bottom, 40)
                    }
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    
                    // Start Session Button
                    startSessionButton
                }
            }
        }
        .onAppear {
            handlePreselectedEvent()
        }
        .sheet(isPresented: $showingAddGame) {
            AddCashGameView(cashGameService: cashGameService)
        }
        .sheet(isPresented: $showingEventSelector) {
            eventSelectorSheet
        }
    }
    
    // MARK: - UI Components
    
    private var headerView: some View {
        HStack {
            Button(action: { delegate?.didCancelSetup() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("New Session")
                .font(.plusJakarta(.headline, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Invisible spacer to balance the back button
            Color.clear
                .frame(width: 24)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var sessionTypePicker: some View {
        Picker("Session Type", selection: $selectedLogType) {
            ForEach(SessionLogType.allCases) { type in
                Text(type.rawValue.capitalized).tag(type)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
        .padding(.bottom, 10)
        .onChange(of: selectedLogType) { _ in
            clearFieldsOnTypeChange()
        }
    }
    
    private var cashGameSetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Select Game")
                    .font(.plusJakarta(.headline, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .padding(.leading, 6)
                
                Spacer()
                
                Button(action: { showingAddGame = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.gray.opacity(0.3)))
                }
                .padding(.trailing, 6)
            }
            .padding(.bottom, 2)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cashGameService.cashGames) { game in
                        gameCard(for: game)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            
            if selectedGame == nil {
                Text("Game details can be added later in the Details tab")
                    .font(.plusJakarta(.caption))
                    .foregroundColor(.gray)
                    .padding(.leading, 6)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
    
    private var tournamentSetupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tournament Details")
                    .font(.plusJakarta(.headline, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { showingEventSelector = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.plus")
                        Text("Select Event")
                    }
                    .font(.plusJakarta(.caption, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.leading, 6)
            
            // Tournament Name Field
            GlassyInputField(
                icon: "trophy",
                title: "Tournament Name",
                glassOpacity: glassOpacity,
                labelColor: .gray,
                materialOpacity: materialOpacity
            ) {
                TextFieldContent(text: $tournamentName, keyboardType: .default, textColor: .white)
            }
            
            // Casino Field
            GlassyInputField(
                icon: "building.2",
                title: "Casino",
                glassOpacity: glassOpacity,
                labelColor: .gray,
                materialOpacity: materialOpacity
            ) {
                TextFieldContent(text: $tournamentCasino, keyboardType: .default, textColor: .white)
            }
            
            // Game Type and Format Selection
            tournamentGameTypeAndFormatSection
        }
        .padding(.horizontal)
    }
    
    private var tournamentGameTypeAndFormatSection: some View {
        HStack(spacing: 12) {
            // Tournament Game Type Picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gamecontroller")
                        .foregroundColor(.gray)
                    Text("Game Type")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                HStack {
                    ForEach(TournamentGameType.allCases, id: \.self) { gameType in
                        Button(action: {
                            selectedTournamentGameType = gameType
                        }) {
                            Text(gameType.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedTournamentGameType == gameType ? .white : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTournamentGameType == gameType ? Color.white.opacity(0.2) : Color.clear)
                                )
                        }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassyBackground(cornerRadius: 16)
            
            // Tournament Format Picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "star.circle")
                        .foregroundColor(.gray)
                    Text("Format")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Picker("Tournament Format", selection: $selectedTournamentFormat) {
                    ForEach(TournamentFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassyBackground(cornerRadius: 16)
        }
    }
    
    private var buyInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedLogType == .cashGame ? "Buy-in Amount" : "Tournament Buy-in")
                .font(.plusJakarta(.headline, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading, 6)
                .padding(.bottom, 2)
            
            if selectedLogType == .tournament {
                GlassyInputField(
                    icon: "dollarsign.circle",
                    title: "Buy in",
                    glassOpacity: glassOpacity,
                    labelColor: .gray,
                    materialOpacity: materialOpacity
                ) {
                    TextFieldContent(text: $baseBuyInTournament, keyboardType: .decimalPad, prefix: "$", textColor: .white, prefixColor: .gray)
                }
                
                // Starting Chips Field for Tournaments
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "circle.stack")
                            .foregroundColor(.gray)
                        Text("Starting Chips")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    TextField("20000", value: $tournamentStartingChips, format: .number)
                        .keyboardType(.numberPad)
                        .font(.plusJakarta(.body, weight: .regular))
                        .foregroundColor(.white)
                        .frame(height: 35)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassyBackground(cornerRadius: 16)
            } else {
                GlassyInputField(
                    icon: "dollarsign.circle",
                    title: "Buy in",
                    glassOpacity: glassOpacity,
                    labelColor: .gray,
                    materialOpacity: materialOpacity
                ) {
                    TextFieldContent(text: $buyIn, keyboardType: .decimalPad, prefix: "$", textColor: .white, prefixColor: .gray)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var stakingSectionTrigger: some View {
        Button(action: {
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
                    
                    if validStakerCount == 0 {
                        Text("Tap to add staking details")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    } else {
                        Text("\(validStakerCount) staker\(validStakerCount == 1 ? "" : "s") configured")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if validStakerCount > 0 {
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
            .glassyBackground(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(validStakerCount == 0 ? primaryTextColor.opacity(0.2) : Color.green.opacity(0.5), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
    
    private var startSessionButton: some View {
        VStack {
            Button(action: startSession) {
                Text("Start Session")
                    .font(.plusJakarta(.body, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 27)
                            .fill(canStartSession ? Color.gray.opacity(0.7) : Color.gray.opacity(0.3))
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 27))
                    )
            }
            .disabled(!canStartSession)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.clear)
    }
    
    private var eventSelectorSheet: some View {
        NavigationView {
            ExploreView(onEventSelected: { selectedEvent in
                self.tournamentName = selectedEvent.event_name
                
                if let usdBuyin = selectedEvent.buyin_usd {
                    self.baseBuyInTournament = String(format: "%.0f", usdBuyin)
                } else if let parsedBuyin = parseBuyinToDouble(selectedEvent.buyin_string) {
                    self.baseBuyInTournament = String(format: "%.0f", parsedBuyin)
                } else {
                    self.baseBuyInTournament = ""
                }
                
                DispatchQueue.main.async {
                    self.tournamentCasino = selectedEvent.casino ?? ""
                }
                
                // Set starting chips from event data
                if let startingChips = selectedEvent.startingChips {
                    self.tournamentStartingChips = Double(startingChips)
                } else if let chipsFormatted = selectedEvent.chipsFormatted, !chipsFormatted.isEmpty {
                    let cleanChipsString = chipsFormatted.replacingOccurrences(of: ",", with: "")
                    if let parsedChips = Double(cleanChipsString) {
                        self.tournamentStartingChips = parsedChips
                    }
                }
                
                self.showingEventSelector = false
            }, isSheetPresentation: true)
            .navigationTitle("Select Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showingEventSelector = false }
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var validStakerCount: Int {
        stakerConfigs.filter { config in
            if config.isManualEntry {
                guard config.selectedManualStaker != nil else { return false }
            } else {
                guard config.selectedStaker != nil else { return false }
            }
            guard let percentage = Double(config.percentageSold), percentage > 0, percentage <= 100 else { return false }
            guard let markup = Double(config.markup), markup >= 1.0 else { return false }
            return true
        }.count
    }

    // MARK: - Helper Methods
    
    private var canStartSession: Bool {
        if selectedLogType == .cashGame {
            return !buyIn.isEmpty && Double(buyIn) ?? 0 > 0
        } else {
            return !tournamentName.isEmpty && !baseBuyInTournament.isEmpty && Double(baseBuyInTournament) ?? 0 > 0
        }
    }
    
    private func gameCard(for game: CashGame) -> some View {
        GameCard(
            stakes: game.stakes,
            name: game.name,
            gameType: game.gameType,
            isSelected: selectedGame?.id == game.id,
            titleColor: primaryTextColor,
            subtitleColor: secondaryTextColor,
            glassOpacity: glassOpacity,
            materialOpacity: materialOpacity
        )
        .onTapGesture {
            selectedGame = game
        }
    }
    
    private func clearFieldsOnTypeChange() {
        if selectedLogType == .cashGame {
            tournamentName = ""
            baseBuyInTournament = ""
            tournamentCasino = ""
        } else {
            selectedGame = nil
            buyIn = ""
        }
    }
    
    private func handlePreselectedEvent() {
        if let event = preselectedEvent {
            selectedLogType = .tournament
            tournamentName = event.event_name
            
            if let usdBuyin = event.buyin_usd {
                baseBuyInTournament = String(format: "%.0f", usdBuyin)
            } else if let parsedBuyin = parseBuyinToDouble(event.buyin_string) {
                baseBuyInTournament = String(format: "%.0f", parsedBuyin)
            }
            
            tournamentCasino = event.casino ?? ""
            
            if let startingChips = event.startingChips {
                tournamentStartingChips = Double(startingChips)
            } else if let chipsFormatted = event.chipsFormatted, !chipsFormatted.isEmpty {
                let cleanChipsString = chipsFormatted.replacingOccurrences(of: ",", with: "")
                if let parsedChips = Double(cleanChipsString) {
                    tournamentStartingChips = parsedChips
                }
            }
        }
    }
    
    private func startSession() {
        let configuration = createSessionConfiguration()
        delegate?.didCompleteSetup(with: configuration)
    }
    
    private func createSessionConfiguration() -> SessionConfiguration {
        if selectedLogType == .cashGame {
            return SessionConfiguration(
                sessionType: .cashGame,
                gameName: selectedGame?.name ?? "Live Session",
                stakes: selectedGame?.stakes ?? "TBD",
                buyIn: Double(buyIn) ?? 0,
                isTournament: false,
                tournamentDetails: nil,
                stakerConfigs: stakerConfigs,
                casino: nil,
                tournamentGameType: nil,
                tournamentFormat: nil,
                tournamentStartingChips: nil,
                pokerVariant: selectedGame?.gameType.rawValue
            )
        } else {
            let baseBuyIn = Double(baseBuyInTournament) ?? 0
            return SessionConfiguration(
                sessionType: .tournament,
                gameName: tournamentName,
                stakes: "$\(Int(baseBuyIn)) Tournament",
                buyIn: baseBuyIn,
                isTournament: true,
                tournamentDetails: TournamentDetails(
                    name: tournamentName,
                    type: "NLH",
                    baseBuyIn: baseBuyIn
                ),
                stakerConfigs: stakerConfigs,
                casino: tournamentCasino.isEmpty ? nil : tournamentCasino,
                tournamentGameType: selectedTournamentGameType,
                tournamentFormat: selectedTournamentFormat,
                tournamentStartingChips: tournamentStartingChips,
                pokerVariant: nil
            )
        }
    }
    
    // Helper to parse buy-in string to Double
    private func parseBuyinToDouble(_ buyinString: String) -> Double? {
        let currencySymbols = CharacterSet(charactersIn: "$,€£¥")
        var cleanedString = buyinString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanedString = cleanedString.components(separatedBy: currencySymbols).joined()
        cleanedString = cleanedString.replacingOccurrences(of: ",", with: "")
        
        if let mainBuyinPart = cleanedString.split(whereSeparator: { "+-/".contains($0) }).first {
            cleanedString = String(mainBuyinPart).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return Double(cleanedString)
    }
}

// MARK: - Extensions

extension View {
    func glassyBackground(cornerRadius: CGFloat) -> some View {
        self.background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.01))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
} 