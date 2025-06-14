import SwiftUI
import FirebaseFirestore

struct EditSessionSheetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject var userService: UserService
    let session: Session
    let sessionStakes: [Stake]?
    @ObservedObject var stakeService: StakeService
    let onStakeUpdated: (() -> Void)?
    
    // Internal state for stakes
    @State private var internalStakes: [Stake] = []
    @State private var isLoadingStakes = false
    
    // Financial fields
    @State private var buyInText: String
    @State private var cashOutText: String
    @State private var hoursText: String
    
    // Game details
    @State private var gameNameText: String
    @State private var stakesText: String
    @State private var startDate: Date
    @State private var startTime: Date
    
    // Location (for cash games)
    @State private var locationText: String

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    // Colors
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94)
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84)
    private let glassOpacity = 0.01
    private let materialOpacity = 0.2

    init(session: Session, sessionStore: SessionStore, sessionStakes: [Stake]? = nil, stakeService: StakeService, onStakeUpdated: (() -> Void)? = nil) {
        self.session = session
        self.sessionStore = sessionStore
        self.sessionStakes = sessionStakes
        self.stakeService = stakeService
        self.onStakeUpdated = onStakeUpdated
        _buyInText = State(initialValue: String(format: "%.0f", session.buyIn))
        _cashOutText = State(initialValue: String(format: "%.0f", session.cashout))
        _hoursText = State(initialValue: String(format: "%.1f", session.hoursPlayed))
        _gameNameText = State(initialValue: session.gameName)
        _stakesText = State(initialValue: session.stakes)
        _startDate = State(initialValue: session.startDate)
        _startTime = State(initialValue: session.startDate)
        _locationText = State(initialValue: session.location ?? "")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                VStack(spacing: 0) {
                    // Content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Game Details Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Game Details")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .padding(.leading, 6)
                                    .padding(.bottom, 2)
                                
                                VStack(spacing: 12) {
                                    GlassyInputField(
                                        icon: "gamecontroller",
                                        title: "Game Name",
                                        glassOpacity: glassOpacity,
                                        labelColor: secondaryTextColor,
                                        materialOpacity: materialOpacity
                                    ) {
                                        TextFieldContent(text: $gameNameText, placeholder: "Enter game name...", textColor: primaryTextColor)
                                    }
                                    
                                    GlassyInputField(
                                        icon: "dollarsign.circle",
                                        title: "Stakes",
                                        glassOpacity: glassOpacity,
                                        labelColor: secondaryTextColor,
                                        materialOpacity: materialOpacity
                                    ) {
                                        TextFieldContent(text: $stakesText, placeholder: "e.g., $1/$2", textColor: primaryTextColor)
                                    }
                                    
                                    if session.gameType != SessionLogType.tournament.rawValue {
                                        GlassyInputField(
                                            icon: "location",
                                            title: "Location",
                                            glassOpacity: glassOpacity,
                                            labelColor: secondaryTextColor,
                                            materialOpacity: materialOpacity
                                        ) {
                                            TextFieldContent(text: $locationText, placeholder: "Enter location...", textColor: primaryTextColor)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            // Time & Duration Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Time & Duration")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .padding(.leading, 6)
                                    .padding(.bottom, 2)
                                
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
                                    
                                    GlassyInputField(
                                        icon: "timer",
                                        title: "Duration (Hours)",
                                        glassOpacity: glassOpacity,
                                        labelColor: secondaryTextColor,
                                        materialOpacity: materialOpacity
                                    ) {
                                        TextFieldContent(text: $hoursText, placeholder: "e.g., 4.5", keyboardType: .decimalPad, textColor: primaryTextColor)
                                    }
                                }
                            }
                            .padding(.horizontal)

                            // Financial Information Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Financial Details")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .padding(.leading, 6)
                                    .padding(.bottom, 2)
                                
                                VStack(spacing: 12) {
                                    GlassyInputField(
                                        icon: "dollarsign.circle",
                                        title: "Buy-in Amount",
                                        glassOpacity: glassOpacity,
                                        labelColor: secondaryTextColor,
                                        materialOpacity: materialOpacity
                                    ) {
                                        TextFieldContent(text: $buyInText, placeholder: "0.00", keyboardType: .decimalPad, prefix: "$", textColor: primaryTextColor, prefixColor: secondaryTextColor)
                                    }
                                    
                                    GlassyInputField(
                                        icon: "dollarsign.circle",
                                        title: "Cash-out Amount",
                                        glassOpacity: glassOpacity,
                                        labelColor: secondaryTextColor,
                                        materialOpacity: materialOpacity
                                    ) {
                                        TextFieldContent(text: $cashOutText, placeholder: "0.00", keyboardType: .decimalPad, prefix: "$", textColor: primaryTextColor, prefixColor: secondaryTextColor)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            // Staking Information Section
                            stakingEditSection()

                            Spacer()
                                .frame(height: 40)
                        }
                        .padding(.top, 8)
                    }
                    
                    // Save Button
                    VStack {
                        Button(action: saveChanges) {
                            HStack {
                                Text("Save Changes")
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
                        .disabled(isLoading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .background(Color.clear)
                }
                .frame(width: geometry.size.width)
            }
            .onAppear {
                if sessionStakes == nil {
                    fetchStakes()
                } else {
                    internalStakes = sessionStakes ?? []
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Session")
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
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Staking Edit Section
    @ViewBuilder
    private func stakingEditSection() -> some View {
        let stakesToShow = sessionStakes ?? internalStakes
        
        if !stakesToShow.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Staking Information")
                    .font(.plusJakarta(.headline, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .padding(.leading, 6)
                    .padding(.bottom, 2)
                
                if isLoadingStakes {
                    HStack {
                        ProgressView()
                        Text("Loading stakes...")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    }
                    .padding(.horizontal, 14)
                } else {
                    VStack(spacing: 12) {
                        ForEach(stakesToShow) { stake in
                            StakeEditCard(
                                stake: stake,
                                userService: userService,
                                stakeService: stakeService,
                                glassOpacity: glassOpacity,
                                materialOpacity: materialOpacity,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                                onStakeUpdated: {
                                    if sessionStakes == nil {
                                        fetchStakes()
                                    }
                                    onStakeUpdated?()
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func fetchStakes() {
        isLoadingStakes = true
        
        Task {
            do {
                let stakes = try await stakeService.fetchStakesForSession(session.id)
                
                // Fetch user profiles for stakers
                for stake in stakes {
                    if userService.loadedUsers[stake.stakerUserId] == nil {
                        Task { await userService.fetchUser(id: stake.stakerUserId) }
                    }
                    if userService.loadedUsers[stake.stakedPlayerUserId] == nil {
                        Task { await userService.fetchUser(id: stake.stakedPlayerUserId) }
                    }
                }
                
                await MainActor.run {
                    self.internalStakes = stakes
                    self.isLoadingStakes = false
                }
            } catch {
                await MainActor.run {
                    self.internalStakes = []
                    self.isLoadingStakes = false
                }
            }
        }
    }

    private func saveChanges() {
        guard let buyIn = Double(buyInText), 
              let cashOut = Double(cashOutText), 
              let hours = Double(hoursText) else {
            alertTitle = "Invalid Input"
            alertMessage = "Please ensure buy-in, cash-out, and duration are valid numbers."
            showAlert = true
            return
        }
        
        if buyIn < 0 || cashOut < 0 || hours < 0 {
            alertTitle = "Invalid Input"
            alertMessage = "Amounts and duration cannot be negative."
            showAlert = true
            return
        }

        isLoading = true
        
        // Combine date and time
        let calendar = Calendar.current
        let combinedStartDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                                minute: calendar.component(.minute, from: startTime),
                                                second: 0,
                                                of: startDate) ?? startDate

        var updatedData: [String: Any] = [
            "buyIn": buyIn,
            "cashout": cashOut,
            "hoursPlayed": hours,
            "profit": cashOut - buyIn,
            "gameName": gameNameText.trimmingCharacters(in: .whitespacesAndNewlines),
            "stakes": stakesText.trimmingCharacters(in: .whitespacesAndNewlines),
            "startDate": Timestamp(date: combinedStartDateTime),
            "startTime": Timestamp(date: combinedStartDateTime),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Only add location for cash games
        if session.gameType != SessionLogType.tournament.rawValue {
            updatedData["location"] = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        sessionStore.updateSessionDetails(sessionId: session.id, updatedData: updatedData) { error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    alertTitle = "Error"
                    alertMessage = "Failed to save changes: \(error.localizedDescription)"
                    showAlert = true
                } else {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Helper Views

// MARK: - StakeEditCard Component
struct StakeEditCard: View {
    let stake: Stake
    @ObservedObject var userService: UserService
    @ObservedObject var stakeService: StakeService
    let glassOpacity: Double
    let materialOpacity: Double
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let onStakeUpdated: (() -> Void)?
    
    @State private var percentageText: String
    @State private var markupText: String
    @State private var isEditing = false
    @State private var isSaving = false
    
    init(stake: Stake, userService: UserService, stakeService: StakeService, 
         glassOpacity: Double, materialOpacity: Double, 
         primaryTextColor: Color, secondaryTextColor: Color,
         onStakeUpdated: (() -> Void)? = nil) {
        self.stake = stake
        self.userService = userService
        self.stakeService = stakeService
        self.glassOpacity = glassOpacity
        self.materialOpacity = materialOpacity
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.onStakeUpdated = onStakeUpdated
        _percentageText = State(initialValue: String(format: "%.0f", stake.stakePercentage * 100))
        _markupText = State(initialValue: String(format: "%.2f", stake.markup))
    }
    
    private var stakerName: String {
        if stake.isOffAppStake == true {
            return stake.manualStakerDisplayName ?? "Manual Staker"
        } else if let stakerProfile = userService.loadedUsers[stake.stakerUserId] {
            return stakerProfile.displayName ?? stakerProfile.username
        } else {
            return "Loading..."
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with staker name and edit button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Staker: \(stakerName)")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    
                    Text("Status: \(stake.status.displayName)")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(stake.status == .settled ? .green : .orange)
                }
                
                Spacer()
                
                if stake.status != .settled {
                    Button(action: { isEditing.toggle() }) {
                        Text(isEditing ? "Cancel" : "Edit")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(isEditing ? .red : .blue)
                    }
                }
            }
            
            if isEditing && stake.status != .settled {
                // Edit mode - show input fields
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        GlassyInputField(
                            icon: "percent",
                            title: "Percentage",
                            glassOpacity: glassOpacity,
                            labelColor: secondaryTextColor,
                            materialOpacity: materialOpacity
                        ) {
                            HStack {
                                TextField("", text: $percentageText)
                                    .foregroundColor(primaryTextColor)
                                    .font(.plusJakarta(.body, weight: .medium))
                                    .keyboardType(.decimalPad)
                                Text("%")
                                    .foregroundColor(secondaryTextColor)
                                    .font(.plusJakarta(.body, weight: .medium))
                            }
                        }
                        
                        GlassyInputField(
                            icon: "arrow.up.circle",
                            title: "Markup",
                            glassOpacity: glassOpacity,
                            labelColor: secondaryTextColor,
                            materialOpacity: materialOpacity
                        ) {
                            HStack {
                                TextField("", text: $markupText)
                                    .foregroundColor(primaryTextColor)
                                    .font(.plusJakarta(.body, weight: .medium))
                                    .keyboardType(.decimalPad)
                                Text("x")
                                    .foregroundColor(secondaryTextColor)
                                    .font(.plusJakarta(.body, weight: .medium))
                            }
                        }
                    }
                    
                    Button(action: saveChanges) {
                        HStack {
                            Text("Save Changes")
                                .font(.plusJakarta(.body, weight: .semibold))
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: primaryTextColor))
                                    .scaleEffect(0.8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(primaryTextColor)
                        .cornerRadius(22)
                    }
                    .disabled(isSaving)
                }
            } else {
                // Display mode - show current values
                VStack(spacing: 8) {
                    HStack {
                        Text("Stake Percentage:")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                        Spacer()
                        Text("\(Int(stake.stakePercentage * 100))%")
                            .font(.plusJakarta(.body, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    }
                    
                    HStack {
                        Text("Markup:")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                        Spacer()
                        Text("\(stake.markup, specifier: "%.2f")x")
                            .font(.plusJakarta(.body, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    }
                    
                    Divider()
                        .background(secondaryTextColor.opacity(0.3))
                    
                    HStack {
                        Text("Settlement:")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                        Spacer()
                        Text(stake.amountTransferredAtSettlement.isFinite && !stake.amountTransferredAtSettlement.isNaN ? 
                             (stake.amountTransferredAtSettlement >= 0 ? 
                              "+$\(Int(stake.amountTransferredAtSettlement))" : 
                              "-$\(abs(Int(stake.amountTransferredAtSettlement)))") : 
                             "$0")
                            .font(.plusJakarta(.body, weight: .bold))
                            .foregroundColor(stake.amountTransferredAtSettlement >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func saveChanges() {
        guard let percentage = Double(percentageText),
              let markup = Double(markupText),
              let stakeId = stake.id else { return }
        
        let newPercentage = percentage / 100.0
        
        guard newPercentage > 0 && newPercentage <= 1.0 && markup > 0 else { return }
        
        isSaving = true
        
        Task {
            do {
                try await stakeService.updateStake(
                    stakeId: stakeId,
                    newPercentage: newPercentage,
                    newMarkup: markup
                )
                await MainActor.run {
                    isSaving = false
                    isEditing = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
        
        onStakeUpdated?()
    }
}


