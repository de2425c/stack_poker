import SwiftUI
import FirebaseAuth

struct EventStakingDetailsView: View {
    let event: Event
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var manualStakerService: ManualStakerService
    
    @StateObject private var eventStakingService = EventStakingService()
    
    // Global details
    @State private var maxBullets: String = "1"
    @State private var markup: String = "1.0"
    
    // Staker configurations
    @State private var stakerConfigs: [StakerConfig] = []
    
    // UI state
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    @State private var showingSuccess = false
    
    // Colors
    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color.white.opacity(0.7)
    private let glassOpacity = 0.05
    private let materialOpacity = 0.2
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Global Details
                        globalDetailsSection
                        
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
        .onAppear {
            // Add initial staker if none
            if stakerConfigs.isEmpty {
                stakerConfigs.append(StakerConfig())
            }
        }
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
    
    // MARK: - Global Details Section
    private var globalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Details")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(primaryTextColor)
            
            HStack(spacing: 16) {
                // Max Bullets
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
                
                // Markup
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markup")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(primaryTextColor)
                    
                    TextField("1.0", text: $markup)
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
            if let markupValue = Double(markup), markupValue > 1.0 {
                let markupPercentage = (markupValue - 1.0) * 100
                Text("Markup: \(markupPercentage, specifier: "%.1f")% above buy-in cost")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(secondaryTextColor)
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
    
    // MARK: - Stakers Section
    private var stakersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stakers")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(primaryTextColor)
            
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
                        onRemove: {
                            stakerConfigs.removeAll { $0.id == config.id }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Add Staker Button
    private var addStakerButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                stakerConfigs.append(StakerConfig())
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
    
    // MARK: - Validation
    private var isValidConfiguration: Bool {
        guard let maxBulletsInt = Int(maxBullets), maxBulletsInt > 0 else { return false }
        guard let markupDouble = Double(markup), markupDouble >= 1.0 else { return false }
        
        let validStakers = stakerConfigs.filter { config in
            // Must have a staker selected
            guard config.selectedStaker != nil || (config.isManualEntry && config.selectedManualStaker != nil) else { return false }
            
            // Must have valid percentage
            guard let percentage = Double(config.percentageSold), percentage > 0, percentage <= 100 else { return false }
            
            return true
        }
        
        return !validStakers.isEmpty
    }
    
    // MARK: - Actions
    private func createStakingInvites() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard let maxBulletsInt = Int(maxBullets) else { return }
        guard let markupDouble = Double(markup) else { return }
        
        isLoading = true
        error = nil
        
        Task {
            do {
                // Calculate event date from SimpleDate
                let eventDate = dateFromSimpleDate(event.simpleDate)
                
                // Extract valid staker information
                var appStakers: [(stakerUserId: String, percentageBought: Double, amountBought: Double, isManual: Bool, displayName: String?)] = []
                var manualStakers: [(stakerUserId: String, percentageBought: Double, amountBought: Double, isManual: Bool, displayName: String?)] = []
                
                print("EventStakingDetailsView: Processing \(stakerConfigs.count) staker configs")
                
                for (configIndex, config) in stakerConfigs.enumerated() {
                    print("EventStakingDetailsView: Config \(configIndex) - isManualEntry: \(config.isManualEntry), percentageSold: '\(config.percentageSold)', selectedManualStaker: \(config.selectedManualStaker?.name ?? "nil"), selectedStaker: \(config.selectedStaker?.username ?? "nil")")
                    
                    guard let percentage = Double(config.percentageSold), percentage > 0 else { 
                        print("EventStakingDetailsView: Config \(configIndex) - Invalid percentage, skipping")
                        continue 
                    }
                    
                    let stakerUserId: String
                    let isManual: Bool
                    let displayName: String?
                    
                    if config.isManualEntry, let manualStaker = config.selectedManualStaker {
                        print("EventStakingDetailsView: Config \(configIndex) - Processing as manual staker: \(manualStaker.name)")
                        print("EventStakingDetailsView: Config \(configIndex) - Manual staker ID: '\(manualStaker.id ?? "nil")'")
                        print("EventStakingDetailsView: Config \(configIndex) - Manual staker contactInfo: '\(manualStaker.contactInfo ?? "nil")'")
                        print("EventStakingDetailsView: Config \(configIndex) - Manual staker createdByUserId: '\(manualStaker.createdByUserId)'")
                        
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
                    
                    // For now, we'll calculate amount bought based on a base amount
                    // In a real implementation, you might want to get the actual buy-in amount from the user
                    let baseBuyinAmount = event.buyin_usd ?? 100.0 // Fallback to $100 if not available
                    let amountBought = baseBuyinAmount * (percentage / 100.0) * markupDouble
                    
                    let stakerInfo = (
                        stakerUserId: stakerUserId,
                        percentageBought: percentage,
                        amountBought: amountBought,
                        isManual: isManual,
                        displayName: displayName
                    )
                    
                    if isManual {
                        manualStakers.append(stakerInfo)
                    } else {
                        appStakers.append(stakerInfo)
                    }
                }
                
                // Create invites for app users
                var inviteIds: [String] = []
                if !appStakers.isEmpty {
                    inviteIds = try await eventStakingService.createEventStakingInvites(
                        eventId: event.id,
                        eventName: event.event_name,
                        eventDate: eventDate,
                        stakedPlayerUserId: currentUserId,
                        maxBullets: maxBulletsInt,
                        markup: markupDouble,
                        stakers: appStakers
                    )
                }
                
                // Create active stakes ONLY for manual stakers
                // App users will get stakes created when they accept their invites
                let stakeService = StakeService()
                var stakeIds: [String] = []
                
                // Don't create stakes for app users here - they get created when invite is accepted
                print("EventStakingDetailsView: Skipping stake creation for \(appStakers.count) app stakers (will be created on invite acceptance)")
                
                print("EventStakingDetailsView: Processing \(manualStakers.count) manual stakers")
                for (index, manualStaker) in manualStakers.enumerated() {
                    print("EventStakingDetailsView: Manual staker \(index + 1): stakerUserId='\(manualStaker.stakerUserId)', displayName='\(manualStaker.displayName ?? "nil")', percentage=\(manualStaker.percentageBought)")
                    let stake = Stake(
                        sessionId: "event_\(event.id)_\(UUID().uuidString)",
                        sessionGameName: event.event_name,
                        sessionStakes: "Event Stakes",
                        sessionDate: eventDate,
                        stakerUserId: manualStaker.stakerUserId,
                        stakedPlayerUserId: currentUserId,
                        stakePercentage: manualStaker.percentageBought / 100.0,
                        markup: markupDouble,
                        totalPlayerBuyInForSession: 0, // Will be updated when session starts
                        playerCashoutForSession: 0, // Will be updated when session ends
                        storedAmountTransferredAtSettlement: 0, // Will be calculated when results are entered
                        status: .active, // Active immediately for manual stakers
                        proposedAt: Date(),
                        lastUpdatedAt: Date(),
                        isTournamentSession: true,
                        manualStakerDisplayName: manualStaker.displayName,
                        isOffAppStake: true
                    )
                    
                    print("EventStakingDetailsView: Creating stake with:")
                    print("  - sessionGameName: '\(stake.sessionGameName)'")
                    print("  - stakedPlayerUserId: '\(stake.stakedPlayerUserId)'")
                    print("  - isOffAppStake: '\(stake.isOffAppStake ?? false)'")
                    print("  - manualStakerDisplayName: '\(stake.manualStakerDisplayName ?? "nil")'")
                    print("  - stakerUserId: '\(stake.stakerUserId)'")
                    
                    let createdStakeId = try await stakeService.addStake(stake)
                    stakeIds.append(createdStakeId)
                    print("EventStakingDetailsView: Successfully created manual stake with ID: \(createdStakeId)")
                }
                
                await MainActor.run {
                    self.isLoading = false
                    self.showingSuccess = true
                }
                
                print("Created \(inviteIds.count) staking invites and \(stakeIds.count) active stakes (\(manualStakers.count) manual) for event \(event.event_name)")
                
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

// MARK: - Event Staker Config View
struct EventStakerConfigView: View {
    @Binding var config: StakerConfig
    @ObservedObject var userService: UserService
    @ObservedObject var manualStakerService: ManualStakerService
    
    let userId: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    var onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with remove button
            HStack {
                Text("Staker Details")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                
                Spacer()
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red.opacity(0.8))
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
            
            // Percentage bought
            if config.selectedStaker != nil || (config.isManualEntry && config.selectedManualStaker != nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Percentage Bought")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(primaryTextColor)
                    
                    TextField("Enter percentage", text: $config.percentageSold)
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