import SwiftUI
import FirebaseAuth

struct EventStakingDetailsView: View {
    let event: Event
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var manualStakerService: ManualStakerService
    
    @StateObject private var eventStakingService = EventStakingService()
    
    // Global details - removed markup since it's now individual
    @State private var maxBullets: String = "1"
    
    // Staker configurations
    @State private var stakerConfigs: [StakerConfig] = []
    
    // UI state
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    @State private var showingSuccess = false
    @State private var showDeleteConfirmation = false
    @State private var configToDelete: StakerConfig? = nil
    
    // Colors
    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color.white.opacity(0.7)
    private let glassOpacity = 0.05
    private let materialOpacity = 0.2
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                    // Add tap to dismiss gesture
                    .onTapGesture {
                        dismiss()
                    }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Global Details (without markup)
                        globalDetailsSection
                        
                        // Total percentage validation warning
                        if totalPercentageExceeds100 {
                            percentageWarningSection
                        }
                        
                        // Stakers Section
                        stakersSection
                        
                        // Add Staker Button
                        addStakerButton
                        
                        // Create Button
                        createButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Staking Details")
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
        .alert("Error", isPresented: $showError, actions: { Button("OK") {} }, message: { Text(error ?? "An unknown error occurred.") })
        .alert("Success", isPresented: $showingSuccess, actions: { 
            Button("OK") { dismiss() }
        }, message: { 
            Text("Staking setup created successfully! Invites sent to app users. Active stakes created for manual stakers.")
        })
        .alert("Delete Staker", isPresented: $showDeleteConfirmation, actions: { 
            Button("Cancel", role: .cancel) {
                configToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let config = configToDelete {
                    removeStakerConfig(config)
                }
                configToDelete = nil
            }
        }, message: { 
            if let config = configToDelete {
                let stakerName = config.selectedStaker?.displayName ?? config.selectedStaker?.username ?? 
                                config.selectedManualStaker?.name ?? "this staker"
                return Text("Are you sure you want to remove \(stakerName) from this staking configuration?")
            }
            return Text("Are you sure you want to remove this staker?")
        })
        .onAppear {
            // Add initial staker if none with default markup
            if stakerConfigs.isEmpty {
                var initialConfig = StakerConfig()
                initialConfig.markup = "1.0" // Set default markup for individual staker
                stakerConfigs.append(initialConfig)
            }
        }
    }
    
    // MARK: - Percentage Validation
    private var totalPercentageExceeds100: Bool {
        let total = stakerConfigs.compactMap { Double($0.percentageSold) }.reduce(0, +)
        return total > 100
    }
    
    private var totalPercentageSold: Double {
        return stakerConfigs.compactMap { Double($0.percentageSold) }.reduce(0, +)
    }
    
    private var percentageWarningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                
                Text("Percentage Warning")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.orange)
            }
            
            Text("Total percentage sold: \(totalPercentageSold, specifier: "%.1f")%")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.orange)
            
            Text("You cannot sell more than 100% of yourself. Please adjust the percentages.")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.event_name)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(primaryTextColor)
            
            HStack {
                Label(event.simpleDate.displayMedium, systemImage: "calendar")
                    .font(.system(size: 16))
                    .foregroundColor(secondaryTextColor)
                
                Spacer()
                
                Text(event.buyin_string)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Global Details Section (removed markup)
    private var globalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Details")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(primaryTextColor)
            
            // Only Max Bullets now
            VStack(alignment: .leading, spacing: 8) {
                Text("Max Bullets")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(primaryTextColor)
                
                TextField("1", text: $maxBullets)
                    .keyboardType(.numberPad)
                    .font(.system(size: 16))
                    .foregroundColor(primaryTextColor)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            
            // Info about individual markup
            Text("Markup is now set individually for each staker below")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Stakers Section
    private var stakersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Stakers")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                
                Spacer()
                
                if !stakerConfigs.isEmpty {
                    Text("\(totalPercentageSold, specifier: "%.1f")% total")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(totalPercentageExceeds100 ? .orange : secondaryTextColor)
                }
            }
            
            VStack(spacing: 16) {
                ForEach(Array(stakerConfigs.enumerated()), id: \.element.id) { index, config in
                    EventStakerConfigView(
                        config: Binding(
                            get: { 
                                index < stakerConfigs.count ? stakerConfigs[index] : config
                            },
                            set: { newValue in
                                if index < stakerConfigs.count {
                                    stakerConfigs[index] = newValue
                                }
                            }
                        ),
                        userService: userService,
                        manualStakerService: manualStakerService,
                        userId: Auth.auth().currentUser?.uid ?? "",
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        glassOpacity: glassOpacity,
                        materialOpacity: materialOpacity,
                        canDelete: stakerConfigs.count > 1, // Only allow delete if more than 1 staker
                        onRemove: {
                            configToDelete = config
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper function to remove staker config
    private func removeStakerConfig(_ config: StakerConfig) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            stakerConfigs.removeAll { $0.id == config.id }
        }
    }
    
    // MARK: - Add Staker Button
    private var addStakerButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                var newConfig = StakerConfig()
                newConfig.markup = "1.0" // Set default markup for new staker
                stakerConfigs.append(newConfig)
            }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                Text("Add Another Staker")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(primaryTextColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Create Button
    private var createButton: some View {
        Button(action: createStakingInvites) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .frame(width: 20, height: 20)
                } else {
                    Text("Send Staking Invites")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 123/255, green: 255/255, blue: 99/255),
                        Color(red: 100/255, green: 220/255, blue: 80/255)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
        }
        .disabled(isLoading || !isValidConfiguration)
        .opacity(isValidConfiguration ? 1.0 : 0.6)
    }
    
    // MARK: - Validation (updated to include percentage cap and individual markup)
    private var isValidConfiguration: Bool {
        guard let maxBulletsInt = Int(maxBullets), maxBulletsInt > 0 else { return false }
        
        // Check total percentage doesn't exceed 100%
        guard !totalPercentageExceeds100 else { return false }
        
        let validStakers = stakerConfigs.filter { config in
            // Must have a staker selected
            guard config.selectedStaker != nil || (config.isManualEntry && config.selectedManualStaker != nil) else { return false }
            
            // Must have valid percentage
            guard let percentage = Double(config.percentageSold), percentage > 0, percentage <= 100 else { return false }
            
            // Must have valid individual markup
            guard let markup = Double(config.markup), markup >= 1.0 else { return false }
            
            return true
        }
        
        return !validStakers.isEmpty
    }
    
    // MARK: - Actions (updated to use individual markup)
    private func createStakingInvites() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard let maxBulletsInt = Int(maxBullets) else { return }
        
        isLoading = true
        error = nil
        
        Task {
            do {
                // Calculate event date from SimpleDate
                let eventDate = dateFromSimpleDate(event.simpleDate)
                
                // Extract valid staker information (now using individual markup)
                var appStakers: [(stakerUserId: String, percentageBought: Double, amountBought: Double, isManual: Bool, displayName: String?, markup: Double)] = []
                var manualStakers: [(stakerUserId: String, percentageBought: Double, amountBought: Double, isManual: Bool, displayName: String?, markup: Double)] = []
                
                print("EventStakingDetailsView: Processing \(stakerConfigs.count) staker configs")
                
                for (configIndex, config) in stakerConfigs.enumerated() {
                    print("EventStakingDetailsView: Config \(configIndex) - isManualEntry: \(config.isManualEntry), percentageSold: '\(config.percentageSold)', markup: '\(config.markup)'")
                    
                    guard let percentage = Double(config.percentageSold), percentage > 0 else { 
                        print("EventStakingDetailsView: Config \(configIndex) - Invalid percentage, skipping")
                        continue 
                    }
                    
                    guard let markupDouble = Double(config.markup), markupDouble >= 1.0 else {
                        print("EventStakingDetailsView: Config \(configIndex) - Invalid markup, skipping")
                        continue
                    }
                    
                    let stakerUserId: String
                    let isManual: Bool
                    let displayName: String?
                    
                    if config.isManualEntry, let manualStaker = config.selectedManualStaker {
                        print("EventStakingDetailsView: Config \(configIndex) - Processing as manual staker: \(manualStaker.name)")
                        
                        // Ensure manual staker has a valid ID
                        guard let manualStakerId = manualStaker.id, !manualStakerId.isEmpty else {
                            print("EventStakingDetailsView: Config \(configIndex) - Manual staker \(manualStaker.name) has no valid ID, skipping")
                            continue
                        }
                        stakerUserId = manualStakerId
                        isManual = true
                        displayName = manualStaker.name
                    } else if let appStaker = config.selectedStaker {
                        print("EventStakingDetailsView: Config \(configIndex) - Processing as app staker: \(appStaker.username)")
                        stakerUserId = appStaker.id
                        isManual = false
                        displayName = appStaker.displayName ?? appStaker.username
                    } else {
                        print("EventStakingDetailsView: Config \(configIndex) - No staker selected, skipping")
                        continue
                    }
                    
                    // Calculate amount bought using individual markup
                    let baseBuyinAmount = event.buyin_usd ?? 100.0 // Fallback to $100 if not available
                    let amountBought = baseBuyinAmount * (percentage / 100.0) * markupDouble
                    
                    let stakerInfo = (
                        stakerUserId: stakerUserId,
                        percentageBought: percentage,
                        amountBought: amountBought,
                        isManual: isManual,
                        displayName: displayName,
                        markup: markupDouble
                    )
                    
                    if isManual {
                        manualStakers.append(stakerInfo)
                    } else {
                        appStakers.append(stakerInfo)
                    }
                }
                
                // Create invites for app users (need to pass individual markup)
                var inviteIds: [String] = []
                let stakeService = StakeService() // Declare once for both app users and manual stakers
                if !appStakers.isEmpty {
                    // Since the service might expect a single markup, we'll use the first staker's markup
                    // Or modify the service to handle individual markups
                    let globalMarkup = appStakers.first?.markup ?? 1.0
                    
                    let stakersForInvite = appStakers.map { staker in
                        (stakerUserId: staker.stakerUserId, percentageBought: staker.percentageBought, amountBought: staker.amountBought, isManual: staker.isManual, displayName: staker.displayName)
                    }
                    
                    inviteIds = try await eventStakingService.createEventStakingInvites(
                        eventId: event.id,
                        eventName: event.event_name,
                        eventDate: eventDate,
                        stakedPlayerUserId: currentUserId,
                        maxBullets: maxBulletsInt,
                        markup: globalMarkup, // Using first staker's markup for now
                        stakers: stakersForInvite
                    )
                    
                    // CRITICAL FIX: Also create pending Stake records for app users
                    // This ensures they can be found later when the session starts
                    print("EventStakingDetailsView: Creating \(appStakers.count) pending stakes for app users")
                    for appStaker in appStakers {
                        let stake = Stake(
                            sessionId: "event_\(event.id)_pending",
                            sessionGameName: event.event_name,
                            sessionStakes: "Event Stakes",
                            sessionDate: eventDate,
                            stakerUserId: appStaker.stakerUserId,
                            stakedPlayerUserId: currentUserId,
                            stakePercentage: appStaker.percentageBought / 100.0,
                            markup: appStaker.markup,
                            totalPlayerBuyInForSession: 0,
                            playerCashoutForSession: 0,
                            storedAmountTransferredAtSettlement: 0,
                            status: .active, // Treat as active stake but mark as pending invite
                            proposedAt: Date(),
                            lastUpdatedAt: Date(),
                            isTournamentSession: true,
                            manualStakerDisplayName: nil, // Not manual
                            isOffAppStake: false,
                            invitePending: true
                        )
                        
                        let createdStakeId = try await stakeService.addStake(stake)
                        print("EventStakingDetailsView: Created pending stake for app user \(appStaker.stakerUserId) with ID: \(createdStakeId)")
                    }
                }
                
                // Create active stakes for manual stakers (using individual markup)
                var stakeIds: [String] = []
                
                print("EventStakingDetailsView: Processing \(manualStakers.count) manual stakers")
                for (index, manualStaker) in manualStakers.enumerated() {
                    print("EventStakingDetailsView: Manual staker \(index + 1): markup=\(manualStaker.markup)")
                    let stake = Stake(
                        sessionId: "event_\(event.id)_pending",
                        sessionGameName: event.event_name,
                        sessionStakes: "Event Stakes",
                        sessionDate: eventDate,
                        stakerUserId: manualStaker.stakerUserId,
                        stakedPlayerUserId: currentUserId,
                        stakePercentage: manualStaker.percentageBought / 100.0,
                        markup: manualStaker.markup, // Using individual markup
                        totalPlayerBuyInForSession: 0,
                        playerCashoutForSession: 0,
                        storedAmountTransferredAtSettlement: 0,
                        status: .active, // Manual stakers are considered active immediately
                        proposedAt: Date(),
                        lastUpdatedAt: Date(),
                        isTournamentSession: true,
                        manualStakerDisplayName: manualStaker.displayName,
                        isOffAppStake: true
                    )
                    
                    let createdStakeId = try await stakeService.addStake(stake)
                    stakeIds.append(createdStakeId)
                    print("EventStakingDetailsView: Successfully created manual stake with ID: \(createdStakeId)")
                }
                
                await MainActor.run {
                    self.isLoading = false
                    self.showingSuccess = true
                }
                
                print("Created \(inviteIds.count) staking invites and \(stakeIds.count) active stakes for event \(event.event_name)")
                
            } catch {
                await MainActor.run {
                    self.error = "Failed to create staking setup: \(error.localizedDescription)"
                    self.showError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func dateFromSimpleDate(_ simpleDate: SimpleDate) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: DateComponents(
            year: simpleDate.year,
            month: simpleDate.month,
            day: simpleDate.day,
            hour: 18 // Default to 6 PM
        )) ?? Date()
    }
}

// MARK: - Event Staker Config View (updated with individual markup and better delete handling)
struct EventStakerConfigView: View {
    @Binding var config: StakerConfig
    @ObservedObject var userService: UserService
    @ObservedObject var manualStakerService: ManualStakerService
    
    let userId: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    let canDelete: Bool // New parameter to control delete button visibility
    var onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with remove button
            HStack {
                Text("Staker Details")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                
                Spacer()
                
                // Only show delete button if canDelete is true
                if canDelete {
                    Button(action: onRemove) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
            
            // Staker selection
            StakerSearchField(
                config: $config,
                userService: userService,
                manualStakerService: manualStakerService,
                userId: userId,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                glassOpacity: glassOpacity,
                materialOpacity: materialOpacity
            )
            
            // Percentage and Markup (side by side)
            if config.selectedStaker != nil || (config.isManualEntry && config.selectedManualStaker != nil) {
                HStack(spacing: 16) {
                    // Percentage bought
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Percentage (%)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(primaryTextColor)
                        
                        TextField("Enter %", text: $config.percentageSold)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16))
                            .foregroundColor(primaryTextColor)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Individual markup
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Markup")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(primaryTextColor)
                        
                        TextField("1.0", text: $config.markup)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16))
                            .foregroundColor(primaryTextColor)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                }
                
                // Markup explanation
                if let markupValue = Double(config.markup), markupValue > 1.0 {
                    let markupPercentage = (markupValue - 1.0) * 100
                    Text("Markup: \(markupPercentage, specifier: "%.1f")% above buy-in cost")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
} 