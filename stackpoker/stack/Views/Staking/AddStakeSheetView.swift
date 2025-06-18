import SwiftUI
import FirebaseAuth

struct AddStakeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var manualStakerService: ManualStakerService
    @EnvironmentObject var stakeService: StakeService
    
    @State private var selectedTab = 0
    var onStakerCreated: (() -> Void)? = nil
    
    private var currentUserId: String {
        userService.currentUserProfile?.id ?? ""
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom tab picker
                    tabPicker
                    
                    // Tab content
                    TabView(selection: $selectedTab) {
                        TournamentStakeFormView(
                            currentUserId: currentUserId,
                            onStakeCreated: {
                                onStakerCreated?()
                                dismiss()
                            }
                        )
                        .tag(0)
                        
                        addManualStakerTab
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Add")
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
    }
    
    @ViewBuilder
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(0..<2) { index in
                let tabTitle = index == 0 ? "Add Stake" : "Add Manual Staker"
                let isSelected = selectedTab == index
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 8) {
                        Text(tabTitle)
                            .font(.plusJakarta(.subheadline, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        
                        Rectangle()
                            .fill(isSelected ? Color.white : Color.clear)
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: isSelected)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var addManualStakerTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Create Manual Staker")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Create a profile for a staker who doesn't use the app")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Manual form fields
                ManualStakerFormFields(
                    manualStakerService: manualStakerService,
                    userId: currentUserId,
                    onStakerCreated: { _ in
                        onStakerCreated?()
                        dismiss()
                    }
                )
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Tournament Stake Form View
struct TournamentStakeFormView: View {
    let currentUserId: String
    let onStakeCreated: () -> Void
    
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var stakeService: StakeService
    
    // Tournament selection
    @State private var selectedEvent: Event? = nil
    @State private var showingEventSelector = false
    @State private var tournamentName = ""
    @State private var buyInAmount = ""
    @State private var casino = ""
    
    // Manual player details
    @State private var selectedManualStaker: ManualStakerProfile? = nil
    @State private var playerName = ""
    @State private var playerContact = ""
    @State private var showingManualStakerPicker = false
    @State private var isCreatingNewStaker = false
    
    // Staking details
    @State private var stakePercentage = "50"
    @State private var markup = "1.0"
    
    // UI state
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Validation
    private var isFormValid: Bool {
        !tournamentName.isEmpty &&
        !buyInAmount.isEmpty &&
        (selectedManualStaker != nil || (!playerName.isEmpty && isCreatingNewStaker)) &&
        Double(stakePercentage) != nil &&
        Double(markup) != nil &&
        !isCreating
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Stake Manual Player")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Set up staking for someone who doesn't use the app")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                VStack(spacing: 20) {
                    // Tournament Selection Section
                    tournamentSelectionSection
                    
                    // Manual Player Details Section
                    manualPlayerDetailsSection
                    
                    // Staking Terms Section
                    stakingTermsSection
                    
                    // Create Stake Button
                    createStakeButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingEventSelector) {
            NavigationView {
                ExploreView(onEventSelected: { event in
                    selectedEvent = event
                    tournamentName = event.event_name
                    casino = event.casino ?? ""
                    
                    // Set buy-in amount from event
                    if let usdBuyin = event.buyin_usd {
                        buyInAmount = String(format: "%.0f", usdBuyin)
                    } else if let parsedBuyin = parseBuyinToDouble(event.buyin_string) {
                        buyInAmount = String(format: "%.0f", parsedBuyin)
                    }
                    
                    showingEventSelector = false
                }, isSheetPresentation: true)
                .navigationTitle("Select Tournament")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") { showingEventSelector = false }
                            .foregroundColor(.white)
                    }
                }
            }
        }

        .sheet(isPresented: $showingManualStakerPicker) {
            ManualStakerPickerSheet(
                selectedStaker: $selectedManualStaker,
                isPresented: $showingManualStakerPicker
            )
            .environmentObject(userService)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Tournament Selection Section
    @ViewBuilder
    private var tournamentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tournament")
                .font(.plusJakarta(.headline, weight: .semibold))
                .foregroundColor(.white)
            
            Button(action: {
                showingEventSelector = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if selectedEvent != nil {
                            Text(tournamentName)
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            
                            if !casino.isEmpty {
                                Text(casino)
                                    .font(.plusJakarta(.caption, weight: .regular))
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("Select Tournament")
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
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
            .buttonStyle(PlainButtonStyle())
            
            // Manual entry option
            VStack(spacing: 12) {
                Text("Or enter manually:")
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                InputField(
                    title: "Tournament Name",
                    text: $tournamentName,
                    placeholder: "Enter tournament name"
                )
                
                HStack(spacing: 12) {
                    InputField(
                        title: "Buy-in Amount",
                        text: $buyInAmount,
                        placeholder: "500"
                    )
                    .keyboardType(.decimalPad)
                    
                    InputField(
                        title: "Casino/Venue",
                        text: $casino,
                        placeholder: "Optional"
                    )
                }
            }
        }
    }
    
    // MARK: - Manual Player Details Section
    @ViewBuilder
    private var manualPlayerDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Player Details")
                .font(.plusJakarta(.headline, weight: .semibold))
                .foregroundColor(.white)
            
            // Selection option
            Button(action: {
                showingManualStakerPicker = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let staker = selectedManualStaker {
                            Text(staker.name)
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white)
                            
                            if let contact = staker.contactInfo, !contact.isEmpty {
                                Text(contact)
                                    .font(.plusJakarta(.caption, weight: .regular))
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("Select Existing Player")
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
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
            .buttonStyle(PlainButtonStyle())
            
            // "Or create new" divider
            HStack {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 1)
                
                Text("OR")
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.vertical, 8)
            
            // Create new player toggle
            Button(action: {
                isCreatingNewStaker.toggle()
                if isCreatingNewStaker {
                    selectedManualStaker = nil
                } else {
                    playerName = ""
                    playerContact = ""
                }
            }) {
                HStack {
                    Image(systemName: isCreatingNewStaker ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isCreatingNewStaker ? .green : .white.opacity(0.5))
                    
                    Text("Create New Player")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(isCreatingNewStaker ? 0.08 : 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Show input fields if creating new
            if isCreatingNewStaker {
                VStack(spacing: 12) {
                    InputField(
                        title: "Player Name",
                        text: $playerName,
                        placeholder: "Enter player's name"
                    )
                    
                    InputField(
                        title: "Contact Info (Optional)",
                        text: $playerContact,
                        placeholder: "Phone, email, or other contact"
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Staking Terms Section
    @ViewBuilder
    private var stakingTermsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Staking Terms")
                .font(.plusJakarta(.headline, weight: .semibold))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                InputField(
                    title: "Stake Percentage",
                    text: $stakePercentage,
                    placeholder: "50"
                )
                .keyboardType(.decimalPad)
                
                InputField(
                    title: "Markup",
                    text: $markup,
                    placeholder: "1.0"
                )
                .keyboardType(.decimalPad)
            }
            
            // Terms preview
            if let percentageDouble = Double(stakePercentage),
               let markupDouble = Double(markup),
               let buyInDouble = Double(buyInAmount) {
                
                let stakerCost = (buyInDouble * (percentageDouble / 100.0)) * markupDouble
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stake Preview")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 4) {
                        HStack {
                            Text("You'll stake:")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(percentageDouble, specifier: "%.1f")% of action")
                                .font(.plusJakarta(.caption, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Text("Your cost:")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formatCurrency(stakerCost))
                                .font(.plusJakarta(.caption, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Text("Player pays:")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formatCurrency(buyInDouble - (buyInDouble * (percentageDouble / 100.0))))
                                .font(.plusJakarta(.caption, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
    }
    
    // MARK: - Create Stake Button
    @ViewBuilder
    private var createStakeButton: some View {
        Button(action: createStake) {
            HStack {
                if isCreating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text("Create Stake")
                        .font(.plusJakarta(.headline, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        isFormValid ? Color.green : Color.gray,
                        isFormValid ? Color.green.opacity(0.8) : Color.gray.opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .disabled(!isFormValid)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Functions
    private func createStake() {
        guard isFormValid,
              let percentageDouble = Double(stakePercentage),
              let markupDouble = Double(markup),
              let buyInDouble = Double(buyInAmount) else {
            return
        }
        
        isCreating = true
        
        Task {
            do {
                // Use existing manual staker or create new one
                let manualStaker: ManualStakerProfile
                
                if let existingStaker = selectedManualStaker {
                    manualStaker = existingStaker
                } else if isCreatingNewStaker {
                    // Create new manual staker
                    let newStaker = ManualStakerProfile(
                        id: UUID().uuidString,
                        createdByUserId: currentUserId,
                        name: playerName,
                        contactInfo: playerContact.isEmpty ? nil : playerContact,
                        notes: nil
                    )
                    
                    // Save the manual staker
                    _ = try await ManualStakerService().createManualStaker(newStaker)
                    manualStaker = newStaker
                } else {
                    throw NSError(domain: "AddStakeSheet", code: 1, userInfo: [NSLocalizedDescriptionKey: "No player selected"])
                }
                
                // Create session date from current date (can be modified later when actual session starts)
                let sessionDate = selectedEvent?.simpleDate.toDate() ?? Date()
                
                let stake = Stake(
                    id: nil,
                    sessionId: "tournament_\(UUID().uuidString)", // Create unique session ID
                    sessionGameName: tournamentName,
                    sessionStakes: "Tournament Stakes",
                    sessionDate: sessionDate,
                    stakerUserId: currentUserId, // Current user is the staker
                    stakedPlayerUserId: manualStaker.id ?? UUID().uuidString, // Use manual staker ID as player
                    stakePercentage: percentageDouble / 100.0, // Convert percentage to decimal
                    markup: markupDouble,
                    totalPlayerBuyInForSession: buyInDouble, // Set initial buy-in
                    playerCashoutForSession: 0, // Will be updated when tournament ends
                    storedAmountTransferredAtSettlement: 0, // Will be calculated when cashout is entered
                    status: .active, // Set to active immediately
                    proposedAt: Date(),
                    lastUpdatedAt: Date(),
                    settlementInitiatorUserId: nil,
                    settlementConfirmerUserId: nil,
                    isTournamentSession: true, // Mark as tournament session
                    manualStakerDisplayName: manualStaker.name, // Store player name for display
                    isOffAppStake: true // This is a manual stake
                )
                
                try await stakeService.addStake(stake)
                
                await MainActor.run {
                    isCreating = false
                    onStakeCreated()
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
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.0f", amount)
    }
    
    private func parseBuyinToDouble(_ buyinString: String) -> Double? {
        // Remove currency symbols and normalize whitespace
        let cleanedString = buyinString
            .replacingOccurrences(of: "[€£¥,]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var totalAmount: Double = 0
        
        // Split by + and - to handle additions and subtractions
        let components = cleanedString.components(separatedBy: CharacterSet(charactersIn: "+-"))
        let operators = cleanedString.filter { "+-".contains($0) }
        
        // Process each component
        for (index, component) in components.enumerated() {
            let numberString = component
                .replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let number = Double(numberString) else { continue }
            
            if index == 0 {
                totalAmount = number
            } else if index - 1 < operators.count {
                let operatorChar = String(operators[operators.index(operators.startIndex, offsetBy: index - 1)])
                if operatorChar == "+" {
                    totalAmount += number
                } else if operatorChar == "-" {
                    totalAmount -= number
                }
            }
        }
        
        return totalAmount > 0 ? totalAmount : nil
    }
}

// MARK: - Input Field Component
struct InputField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.plusJakarta(.caption, weight: .semibold))
                .foregroundColor(.white)
            
            TextField(placeholder, text: $text)
                .font(.plusJakarta(.body, weight: .medium))
                .foregroundColor(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Manual Staker Picker Sheet
struct ManualStakerPickerSheet: View {
    @Binding var selectedStaker: ManualStakerProfile?
    @Binding var isPresented: Bool
    
    @EnvironmentObject var userService: UserService
    @StateObject private var manualStakerService = ManualStakerService()
    
    @State private var manualStakers: [ManualStakerProfile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var currentUserId: String {
        userService.currentUserProfile?.id ?? ""
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isLoading {
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Loading players...")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if manualStakers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.system(size: 32))
                                .foregroundColor(.gray)
                            Text("No Manual Players")
                                .font(.plusJakarta(.subheadline, weight: .medium))
                                .foregroundColor(.gray)
                            Text("Create your first manual player profile")
                                .font(.plusJakarta(.caption, weight: .regular))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(manualStakers) { staker in
                                    ManualStakerCard(
                                        staker: staker,
                                        isSelected: selectedStaker?.id == staker.id,
                                        onSelect: {
                                            selectedStaker = staker
                                            isPresented = false
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
            .navigationTitle("Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                loadManualStakers()
            }
        }
    }
    
    private func loadManualStakers() {
        isLoading = true
        
        Task {
            do {
                let stakers = try await manualStakerService.fetchManualStakers(forUser: currentUserId)
                await MainActor.run {
                    self.manualStakers = stakers
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Manual Staker Card
struct ManualStakerCard: View {
    let staker: ManualStakerProfile
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .overlay(
                        Text(String(staker.name.prefix(1)))
                            .font(.plusJakarta(.body, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(staker.name)
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let contactInfo = staker.contactInfo, !contactInfo.isEmpty {
                        Text(contactInfo)
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    } else {
                        Text("No contact info")
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Extension to convert SimpleDate to Date
extension SimpleDate {
    func toDate() -> Date {
        let calendar = Calendar.current
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 18 // Default to 6 PM
        )) ?? Date()
    }
}

#Preview {
    AddStakeSheetView()
        .environmentObject(UserService())
        .environmentObject(ManualStakerService())
        .environmentObject(StakeService())
} 
