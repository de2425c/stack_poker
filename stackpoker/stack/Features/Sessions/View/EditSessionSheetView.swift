import SwiftUI
import FirebaseFirestore

struct EditSessionSheetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject var userService: UserService
    let session: Session
    let sessionStakes: [Stake]?
    @ObservedObject var stakeService: StakeService
    @ObservedObject var manualStakerService: ManualStakerService
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
    
    // Add Stake functionality
    @State private var showingAddStakeForm = false
    @State private var isAddingStake = false
    
    // Colors
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94)
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84)
    private let glassOpacity = 0.01
    private let materialOpacity = 0.2

    init(session: Session, sessionStore: SessionStore, sessionStakes: [Stake]? = nil, stakeService: StakeService, manualStakerService: ManualStakerService, onStakeUpdated: (() -> Void)? = nil) {
        self.session = session
        self.sessionStore = sessionStore
        self.sessionStakes = sessionStakes
        self.stakeService = stakeService
        self.manualStakerService = manualStakerService
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
            .sheet(isPresented: $showingAddStakeForm) {
                AddStakeFormView(
                    session: session,
                    buyIn: Double(buyInText) ?? session.buyIn,
                    cashOut: Double(cashOutText) ?? session.cashout,
                    stakeService: stakeService,
                    manualStakerService: manualStakerService,
                    userService: userService,
                    onStakeAdded: {
                        if sessionStakes == nil {
                            fetchStakes()
                        }
                        onStakeUpdated?()
                    }
                )
            }
        }
    }

    // MARK: - Staking Edit Section
    @ViewBuilder
    private func stakingEditSection() -> some View {
        let stakesToShow = sessionStakes ?? internalStakes
        
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Staking Information")
                    .font(.plusJakarta(.headline, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .padding(.leading, 6)
                
                Spacer()
                
                // Add Stake Button
                Button(action: {
                    showingAddStakeForm = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add Stake")
                            .font(.plusJakarta(.caption, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
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
                    
                    // Show message if no stakes exist
                    if stakesToShow.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.3.sequence")
                                .font(.system(size: 32))
                                .foregroundColor(secondaryTextColor.opacity(0.6))
                            
                            Text("No stakes added yet")
                                .font(.plusJakarta(.subheadline, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                            
                            Text("Tap 'Add Stake' to add staking details")
                                .font(.plusJakarta(.caption, weight: .regular))
                                .foregroundColor(secondaryTextColor.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            }
        }
        .padding(.horizontal)
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

// MARK: - Add Stake Form View
struct AddStakeFormView: View {
    @Environment(\.dismiss) private var dismiss
    
    let session: Session
    let buyIn: Double
    let cashOut: Double
    @ObservedObject var stakeService: StakeService
    @ObservedObject var manualStakerService: ManualStakerService
    @ObservedObject var userService: UserService
    let onStakeAdded: () -> Void
    
    @State private var isManualStaker = false
    @State private var selectedAppUser: UserProfile?
    @State private var selectedManualStaker: ManualStakerProfile?
    @State private var showingUserSearch = false
    @State private var showingManualStakerSearch = false
    @State private var userSearchQuery = ""
    @State private var manualStakerSearchQuery = ""
    @State private var userSearchResults: [UserProfile] = []
    @State private var manualStakerSearchResults: [ManualStakerProfile] = []
    
    @State private var stakePercentageText = "50"
    @State private var markupText = "1.0"
    
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94)
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84)
    private let glassOpacity = 0.01
    private let materialOpacity = 0.2
    
    private var currentUserId: String {
        userService.currentUserProfile?.id ?? ""
    }
    
    private var isFormValid: Bool {
        let hasValidStaker = isManualStaker ? selectedManualStaker != nil : selectedAppUser != nil
        let hasValidPercentage = Double(stakePercentageText) != nil
        let hasValidMarkup = Double(markupText) != nil
        return hasValidStaker && hasValidPercentage && hasValidMarkup && !isCreating
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Add Stake to Session")
                                .font(.plusJakarta(.title2, weight: .bold))
                                .foregroundColor(primaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("Add staking details to this completed session")
                                .font(.plusJakarta(.subheadline, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        VStack(spacing: 20) {
                            // Session Info
                            sessionInfoSection
                            
                            // Staker Selection
                            stakerSelectionSection
                            
                            // Stake Terms
                            stakeTermsSection
                            
                            // Create Button
                            createStakeButton
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle("Add Stake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            Task {
                try? await manualStakerService.fetchManualStakers(forUser: currentUserId)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Details")
                .font(.plusJakarta(.headline, weight: .medium))
                .foregroundColor(primaryTextColor)
                .padding(.leading, 6)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Game:")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text(session.gameName)
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
                
                HStack {
                    Text("Stakes:")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text(session.stakes)
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
                
                HStack {
                    Text("Buy-in:")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text("$\(Int(buyIn))")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
                
                HStack {
                    Text("Cash-out:")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text("$\(Int(cashOut))")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(cashOut >= buyIn ? .green : .red)
                }
                
                Divider()
                    .background(secondaryTextColor.opacity(0.3))
                
                HStack {
                    Text("Net Result:")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    let profit = cashOut - buyIn
                    Text(profit >= 0 ? "+$\(Int(profit))" : "-$\(abs(Int(profit)))")
                        .font(.plusJakarta(.subheadline, weight: .bold))
                        .foregroundColor(profit >= 0 ? .green : .red)
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
        }
    }
    
    @ViewBuilder
    private var stakerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select Staker")
                .font(.plusJakarta(.headline, weight: .medium))
                .foregroundColor(primaryTextColor)
                .padding(.leading, 6)
            
            VStack(spacing: 12) {
                // Toggle for staker type
                Toggle(isOn: $isManualStaker.animation()) {
                    Text("Use Manual Staker")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.horizontal, 4)
                
                if isManualStaker {
                    manualStakerSelection
                } else {
                    appUserSelection
                }
            }
        }
    }
    
    @ViewBuilder
    private var manualStakerSelection: some View {
        if let selected = selectedManualStaker {
            selectedManualStakerView(selected)
        } else {
            GlassyInputField(
                icon: "person.fill.questionmark",
                title: "Manual Staker",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                Button(action: {
                    showingManualStakerSearch = true
                }) {
                    HStack {
                        Text("Select Manual Staker")
                            .font(.plusJakarta(.body, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            .sheet(isPresented: $showingManualStakerSearch) {
                ManualStakerSelectionView(
                    manualStakerService: manualStakerService,
                    currentUserId: currentUserId,
                    onSelection: { staker in
                        selectedManualStaker = staker
                        showingManualStakerSearch = false
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func selectedManualStakerView(_ staker: ManualStakerProfile) -> some View {
        GlassyInputField(
            icon: "person.fill.checkmark",
            title: "Selected Manual Staker",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 12) {
                Circle()
                    .fill(primaryTextColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(staker.name.first ?? "?").uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(staker.name)
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    
                    if let contactInfo = staker.contactInfo, !contactInfo.isEmpty {
                        Text(contactInfo)
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    selectedManualStaker = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                }
            }
        }
    }
    
    @ViewBuilder
    private var appUserSelection: some View {
        if let selected = selectedAppUser {
            selectedAppUserView(selected)
        } else {
            GlassyInputField(
                icon: "person.fill.questionmark",
                title: "App User Staker",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                Button(action: {
                    showingUserSearch = true
                }) {
                    HStack {
                        Text("Select App User")
                            .font(.plusJakarta(.body, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            .sheet(isPresented: $showingUserSearch) {
                AppUserSelectionView(
                    userService: userService,
                    currentUserId: currentUserId,
                    onSelection: { user in
                        selectedAppUser = user
                        showingUserSearch = false
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func selectedAppUserView(_ user: UserProfile) -> some View {
        GlassyInputField(
            icon: "person.fill.checkmark",
            title: "Selected App User",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 12) {
                Circle()
                    .fill(primaryTextColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String((user.displayName ?? user.username).first ?? "?").uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName ?? user.username)
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    
                    Text("@\(user.username)")
                        .font(.plusJakarta(.caption, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                }
                
                Spacer()
                
                Button(action: {
                    selectedAppUser = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                }
            }
        }
    }
    
    @ViewBuilder
    private var stakeTermsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stake Terms")
                .font(.plusJakarta(.headline, weight: .medium))
                .foregroundColor(primaryTextColor)
                .padding(.leading, 6)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    GlassyInputField(
                        icon: "percent",
                        title: "Stake Percentage",
                        glassOpacity: glassOpacity,
                        labelColor: secondaryTextColor,
                        materialOpacity: materialOpacity
                    ) {
                        HStack {
                            TextField("50", text: $stakePercentageText)
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
                            TextField("1.0", text: $markupText)
                                .foregroundColor(primaryTextColor)
                                .font(.plusJakarta(.body, weight: .medium))
                                .keyboardType(.decimalPad)
                            Text("x")
                                .foregroundColor(secondaryTextColor)
                                .font(.plusJakarta(.body, weight: .medium))
                        }
                    }
                }
                
                // Show calculation preview
                if let percentage = Double(stakePercentageText),
                   let markup = Double(markupText),
                   percentage > 0 && percentage <= 100 && markup > 0 {
                    calculationPreview(percentage: percentage / 100.0, markup: markup)
                }
            }
        }
    }
    
    @ViewBuilder
    private func calculationPreview(percentage: Double, markup: Double) -> some View {
        VStack(spacing: 8) {
            Text("Settlement Preview")
                .font(.plusJakarta(.subheadline, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            let stakerCost = buyIn * percentage * markup
            let stakerShare = cashOut * percentage
            let settlement = stakerShare - stakerCost
            
            VStack(spacing: 6) {
                HStack {
                    Text("Staker Cost:")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text("$\(Int(stakerCost))")
                        .font(.plusJakarta(.caption, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
                
                HStack {
                    Text("Staker Share:")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text("$\(Int(stakerShare))")
                        .font(.plusJakarta(.caption, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
                
                Divider()
                    .background(secondaryTextColor.opacity(0.3))
                
                HStack {
                    Text("Settlement:")
                        .font(.plusJakarta(.caption, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text(settlement >= 0 ? "+$\(Int(settlement))" : "-$\(abs(Int(settlement)))")
                        .font(.plusJakarta(.caption, weight: .bold))
                        .foregroundColor(settlement >= 0 ? .green : .red)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    @ViewBuilder
    private var createStakeButton: some View {
        Button(action: createStake) {
            HStack {
                Text("Add Stake")
                    .font(.plusJakarta(.body, weight: .bold))
                if isCreating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .padding(.leading, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isFormValid ? Color.gray.opacity(0.7) : Color.gray.opacity(0.3))
            .foregroundColor(primaryTextColor)
            .cornerRadius(27)
        }
        .disabled(!isFormValid)
    }
    
    private func createStake() {
        guard let percentage = Double(stakePercentageText),
              let markup = Double(markupText),
              percentage > 0 && percentage <= 100 && markup > 0 else {
            errorMessage = "Please enter valid percentage and markup values"
            showError = true
            return
        }
        
        let stakerUserId: String
        let stakerDisplayName: String?
        let isOffApp: Bool
        
        if isManualStaker {
            guard let manualStaker = selectedManualStaker else {
                errorMessage = "Please select a manual staker"
                showError = true
                return
            }
            stakerUserId = manualStaker.id ?? UUID().uuidString
            stakerDisplayName = manualStaker.name
            isOffApp = true
        } else {
            guard let appUser = selectedAppUser else {
                errorMessage = "Please select an app user"
                showError = true
                return
            }
            stakerUserId = appUser.id
            stakerDisplayName = nil
            isOffApp = false
        }
        
        isCreating = true
        
        Task {
            do {
                // Calculate settlement amount
                let stakerCost = buyIn * (percentage / 100.0) * markup
                let stakerShare = cashOut * (percentage / 100.0)
                let settlementAmount = stakerShare - stakerCost
                
                let stake = Stake(
                    sessionId: session.id,
                    sessionGameName: session.gameName,
                    sessionStakes: session.stakes,
                    sessionDate: session.startDate,
                    stakerUserId: stakerUserId,
                    stakedPlayerUserId: currentUserId,
                    stakePercentage: percentage / 100.0,
                    markup: markup,
                    totalPlayerBuyInForSession: buyIn,
                    playerCashoutForSession: cashOut,
                    storedAmountTransferredAtSettlement: settlementAmount,
                    status: .awaitingSettlement,
                    proposedAt: Date(),
                    lastUpdatedAt: Date(),
                    isTournamentSession: session.gameType == SessionLogType.tournament.rawValue,
                    manualStakerDisplayName: stakerDisplayName,
                    isOffAppStake: isOffApp
                )
                
                try await stakeService.addStake(stake)
                
                await MainActor.run {
                    isCreating = false
                    onStakeAdded()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create stake: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Manual Staker Selection View
struct ManualStakerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manualStakerService: ManualStakerService
    let currentUserId: String
    let onSelection: (ManualStakerProfile) -> Void
    
    @State private var searchText = ""
    
    private var filteredStakers: [ManualStakerProfile] {
        let userStakers = manualStakerService.manualStakers.filter { $0.createdByUserId == currentUserId }
        if searchText.isEmpty {
            return userStakers
        } else {
            return userStakers.filter { staker in
                staker.name.localizedCaseInsensitiveContains(searchText) ||
                (staker.contactInfo?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                SearchBar(text: $searchText, placeholder: "Search manual stakers...")
                    .padding(.horizontal)
                
                if filteredStakers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No manual stakers found")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Create manual stakers in the staking section")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredStakers) { staker in
                        Button(action: {
                            onSelection(staker)
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String(staker.name.first ?? "?").uppercased())
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.blue)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(staker.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    if let contactInfo = staker.contactInfo, !contactInfo.isEmpty {
                                        Text(contactInfo)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Select Manual Staker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                try? await manualStakerService.fetchManualStakers(forUser: currentUserId)
            }
        }
    }
}

// MARK: - App User Selection View
struct AppUserSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userService: UserService
    let currentUserId: String
    let onSelection: (UserProfile) -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                SearchBar(text: $searchText, placeholder: "Search by username...")
                    .padding(.horizontal)
                    .onChange(of: searchText) { newValue in
                        searchUsers(query: newValue)
                    }
                
                if isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("Search for users")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Enter a username to find app users")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No users found")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Try a different username")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults.filter { $0.id != currentUserId }) { user in
                        Button(action: {
                            onSelection(user)
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String((user.displayName ?? user.username).first ?? "?").uppercased())
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.green)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.displayName ?? user.username)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Select App User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            do {
                let results = try await userService.searchUsers(query: query)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }
}

// MARK: - Search Bar Component
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}


