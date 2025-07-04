import SwiftUI
import FirebaseFirestore

// Sheet manager to work around SwiftUI state bugs
class StakingSheetManager: ObservableObject {
    @Published var selectedStake: Stake? = nil
    @Published var showingStakeDetail = false
    
    func presentStakeDetail(stake: Stake) {
        selectedStake = stake
        // Small delay to ensure state is properly set before presentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.showingStakeDetail = true
        }
    }
    
    func dismissStakeDetail() {
        showingStakeDetail = false
        // Clear selection after a small delay to prevent issues
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.selectedStake = nil
        }
    }
}

struct StakingDashboardView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var stakeService: StakeService
    @EnvironmentObject var manualStakerService: ManualStakerService

    @State private var stakes: [Stake] = []
    @State private var manualStakers: [ManualStakerProfile] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedTab: StakingTab = .calendar
    
    // Add state for tracking if this is the initial load
    @State private var hasInitiallyLoaded = false
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var isBackgroundRefreshing = false
    
    @StateObject private var eventStakingService = EventStakingService()
    @StateObject private var sheetManager = StakingSheetManager()
    
    // Complete rethink: Use optional data that drives sheet presentation
    struct PartnerSheetData: Identifiable {
        let id = UUID()
        let partnerName: String
        let stakes: [Stake]
        let groupKey: String?
        let manualStakers: [ManualStakerProfile]
    }
    
    @State private var presentedPartnerData: PartnerSheetData? = nil
    @State private var showingAddStakeSheet = false

    private var currentUserId: String? {
        userService.currentUserProfile?.id
    }
    
    enum StakingTab {
        case calendar
        case dashboard
    }
    


    // Analytics for staking performance (when user is the staker)
    private var stakingPerformanceStakes: [Stake] {
        stakes.filter { $0.stakerUserId == currentUserId && $0.status == .settled }
    }
    
    private var totalStakingProfit: Double {
        stakingPerformanceStakes.reduce(0) { total, stake in
            // FIXED: Inverse logic - when user is staker, negative amountTransferredAtSettlement = staker profit
            total - stake.amountTransferredAtSettlement
        }
    }
    
    private var totalAmountStaked: Double {
        stakingPerformanceStakes.reduce(0) { total, stake in
            total + stake.stakerCost
        }
    }
    
    private var stakingROI: Double {
        guard totalAmountStaked > 0 else { return 0 }
        return (totalStakingProfit / totalAmountStaked) * 100
    }
    
    private var stakingWinRate: Double {
        let totalStakes = stakingPerformanceStakes.count
        guard totalStakes > 0 else { return 0 }
        let winningStakes = stakingPerformanceStakes.filter { $0.amountTransferredAtSettlement < 0 }.count
        return Double(winningStakes) / Double(totalStakes) * 100
    }
    
    // Analytics where user is the staked player
    private var backedPerformanceStakes: [Stake] {
        stakes.filter { $0.stakedPlayerUserId == currentUserId && $0.status == .settled }
    }
    
    private var totalBackedProfit: Double {
        backedPerformanceStakes.reduce(0) { total, stake in
            // FIXED: Inverse logic - when user is player, positive amountTransferredAtSettlement = player profit
            total + stake.amountTransferredAtSettlement
        }
    }
    
    private var totalPlayerCost: Double {
        backedPerformanceStakes.reduce(0) { total, stake in
            let playerCost = stake.totalPlayerBuyInForSession * (1 - stake.stakePercentage)
            return total + playerCost
        }
    }
    
    private var backedROI: Double {
        guard totalPlayerCost > 0 else { return 0 }
        return (totalBackedProfit / totalPlayerCost) * 100
    }
    
    private var backedWinRate: Double {
        let total = backedPerformanceStakes.count
        guard total > 0 else { return 0 }
        let wins = backedPerformanceStakes.filter { $0.amountTransferredAtSettlement > 0 }.count
        return Double(wins) / Double(total) * 100
    }
    
    // Group stakes by month for card display
    private var stakesByMonth: [(String, [Stake])] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        
        let grouped = Dictionary(grouping: stakes.sorted { $0.sessionDate > $1.sessionDate }) { stake in
            dateFormatter.string(from: stake.sessionDate)
        }
        
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    // Group by partner
    private struct PartnerGroup: Identifiable {
        let key: String
        let stakes: [Stake]
        var id: String { key }
    }
    
    private var stakesByPartner: [PartnerGroup] {
        guard let currentUserId = currentUserId else { return [] }
        var grouped: [String: [Stake]] = [:]
        
        // Group existing stakes by partner
        for stake in stakes {
            let partnerKey: String
            if stake.isOffAppStake == true {
                let manualName = stake.manualStakerDisplayName ?? "Manual Staker"
                partnerKey = "manual_" + manualName
            } else {
                partnerKey = (stake.stakedPlayerUserId == currentUserId) ? stake.stakerUserId : stake.stakedPlayerUserId
            }
            grouped[partnerKey, default: []].append(stake)
        }
        
        // Add manual stakers with no stakes yet
        for manualStaker in manualStakers {
            let manualKey = "manual_" + manualStaker.name
            if grouped[manualKey] == nil {
                grouped[manualKey] = []
            }
        }
        
        return grouped.map { key, val in PartnerGroup(key: key, stakes: val) }
            .sorted { lhs, rhs in
                let lhsHasStakes = !lhs.stakes.isEmpty
                let rhsHasStakes = !rhs.stakes.isEmpty

                // Partners with stakes should appear before those without.
                if lhsHasStakes && !rhsHasStakes {
                    return true
                }
                if !lhsHasStakes && rhsHasStakes {
                    return false
                }

                // If both have stakes, sort by the most recent stake's creation date.
                if lhsHasStakes && rhsHasStakes {
                    // Find the most recent 'proposedAt' date to sort partners by their latest activity.
                    let lhsDate = lhs.stakes.map { $0.proposedAt }.max() ?? Date.distantPast
                    let rhsDate = rhs.stakes.map { $0.proposedAt }.max() ?? Date.distantPast
                    
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                }
                
                // For partners with no stakes, or if dates are equal, sort by name for stability.
                return lhs.key < rhs.key
            }
    }
    
    private func partnerName(for stakes: [Stake], groupKey: String? = nil) -> String {
        print("Dashboard: partnerName called with \(stakes.count) stakes, groupKey: \(groupKey ?? "nil")")
        
        if stakes.isEmpty {
            // This must be a manual staker with no stakes
            if let groupKey = groupKey, groupKey.hasPrefix("manual_") {
                let name = String(groupKey.dropFirst(7)) // Remove "manual_" prefix
                print("Dashboard: Empty stakes, returning manual staker name: '\(name)'")
                return name
            }
            print("Dashboard: Empty stakes, no valid groupKey, returning 'Manual Staker'")
            return "Manual Staker"
        }
        
        guard let sample = stakes.first else {
            print("Dashboard: No sample stake available, returning 'Unknown'")
            return "Unknown"
        }
        
        // Check if it's a manual/off-app stake
        if sample.isOffAppStake == true, let manualName = sample.manualStakerDisplayName, !manualName.isEmpty {
            print("Dashboard: Manual stake with name: '\(manualName)'")
            return manualName
        }
        
        guard let currentUserId = currentUserId else {
            print("Dashboard: No currentUserId, returning 'Unknown'")
            return "Unknown"
        }
        
        let partnerId = (sample.stakedPlayerUserId == currentUserId) ? sample.stakerUserId : sample.stakedPlayerUserId
        print("Dashboard: Looking for partnerId: '\(partnerId)' in loaded users")
        
        if let profile = userService.loadedUsers[partnerId] {
            let name = profile.displayName ?? profile.username
            print("Dashboard: Found user profile, name: '\(name)'")
            return name
        } else {
            print("Dashboard: No user profile found for partnerId: '\(partnerId)', available users: \(Array(userService.loadedUsers.keys))")
            return "Unknown User"
        }
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab Bar at very top
                HStack {
                    HStack(spacing: 0) {
                        tabButton(title: "Calendar", tab: .calendar)
                        tabButton(title: "Dashboard", tab: .dashboard)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    
                    Spacer()
                    
                    // + button only for dashboard
                    if selectedTab == .dashboard {
                        Button(action: {
                            showingAddStakeSheet = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 8)
                
                // Tab Content
                if selectedTab == .calendar {
                    stakingCalendarView
                } else {
                    stakingDashboardContent
                }
            }
        }
        // Sheets and navigation
        .onAppear(perform: fetchStakesData)
        // Add onChange to properly handle state updates
        .onChange(of: sheetManager.showingStakeDetail) { _ in }
        .sheet(isPresented: $sheetManager.showingStakeDetail, onDismiss: {
            // Reset state on dismiss and refresh data in background only if needed
            sheetManager.dismissStakeDetail()
            // Only refresh if we have loaded data before (avoid loading animation on initial dismissal)
            if hasInitiallyLoaded {
                refreshStakesDataInBackground()
            }
        }) {
            // Only present sheet if we have a valid stake
            if let stake = sheetManager.selectedStake {
                StakeDetailViewWrapper(
                    stake: stake,
                    currentUserId: currentUserId ?? "",
                    stakeService: stakeService,
                    userService: userService,
                    onUpdate: {
                        // Immediately refresh data in background to show updated stake status
                        refreshStakesDataInBackground()
                    }
                )
            } else {
                // Fallback empty view to prevent crashes
                VStack {
                    Text("Loading...")
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackgroundView().ignoresSafeArea())
            }
        }
        // Sheet showing all stakes with a particular partner - using item binding
        .sheet(item: $presentedPartnerData, onDismiss: {
            // Refresh data in background when partner sheet is dismissed
            if hasInitiallyLoaded {
                refreshStakesDataInBackground()
            }
        }) { sheetData in
            PartnerStakesListView(
                partnerName: sheetData.partnerName,
                stakes: sheetData.stakes.sorted { $0.sessionDate > $1.sessionDate },
                currentUserId: currentUserId ?? "",
                groupKey: sheetData.groupKey,
                manualStakers: sheetData.manualStakers,
                stakeService: stakeService,
                userService: userService
            )
        }
        // Add stake sheet
        .sheet(isPresented: $showingAddStakeSheet) {
            AddStakeSheetView(onStakerCreated: {
                // Refresh the stakes data when a manual staker is created
                refreshStakesDataInBackground()
            })
            .environmentObject(stakeService)
        }
        .onDisappear {
            // Cancel any ongoing refresh task when leaving the view
            refreshTask?.cancel()
        }
    }
    
    // MARK: - Tab Button
    private func tabButton(title: String, tab: StakingTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == tab ? Color.white.opacity(0.15) : Color.clear)
                )
        }
    }
    
    // MARK: - Calendar View
    private var stakingCalendarView: some View {
        VStack {
            if isLoading {
                // Maintain the same layout structure during loading
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StakingEventCalendarView(
                    currentUserId: currentUserId ?? "",
                    userService: userService,
                    stakeService: stakeService,
                    eventStakingService: eventStakingService,
                    onInviteStatusChanged: {
                        refreshStakesDataInBackground()
                    },
                    onOpenStakeDetail: { stake in
                        sheetManager.presentStakeDetail(stake: stake)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Dashboard Content (existing content)
    private var stakingDashboardContent: some View {
        VStack {
            if isLoading {
                // Maintain the same layout structure during loading
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Loading Stakes...")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Spacer()
                    Text("Error: \(errorMessage)")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if stakes.isEmpty && manualStakers.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No staking activity found.")
                            .font(.plusJakarta(.title3, weight: .medium))
                            .foregroundColor(.gray)
                        Text("Create your first stake or check for event invites")
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Performance Analytics (only show if there are stakes)
                        if !stakes.isEmpty {
                            stakingPerformanceView
                            backedPerformanceView
                        }
                        
                        // Partner summary cards (only show if there are stakes or manual stakers)
                        if !stakesByPartner.isEmpty {
                            LazyVStack(spacing: 16) {
                                ForEach(stakesByPartner) { group in
                                    PartnerStakeSummaryCard(
                                        stakes: group.stakes, 
                                        currentUserId: currentUserId ?? "",
                                        manualStakers: manualStakers,
                                        onTap: {
                                            print("Dashboard: OnTap triggered for group with \(group.stakes.count) stakes")
                                            
                                            let computedName = partnerName(for: group.stakes, groupKey: group.key)
                                            print("Dashboard: Computed partner name: '\(computedName)' for groupKey: \(group.key ?? "nil")")
                                            
                                            // Directly set the sheet data - this will trigger sheet presentation
                                            let safeName = computedName.isEmpty ? "Unknown Partner" : computedName
                                            let sheetData = PartnerSheetData(
                                                partnerName: safeName,
                                                stakes: group.stakes,
                                                groupKey: group.key,
                                                manualStakers: manualStakers
                                            )
                                            
                                            print("Dashboard: Setting presentedPartnerData - name: '\(sheetData.partnerName)', stakes: \(sheetData.stakes.count), groupKey: '\(sheetData.groupKey ?? "nil")'")
                                            presentedPartnerData = sheetData
                                        },
                                        groupKey: group.key
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 10)
    }
    

    

    
    @ViewBuilder
    private var stakingPerformanceView: some View {
        VStack(spacing: 12) {
            Text("Your Staking Performance")
                .font(.plusJakarta(.title2, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                // Total Profit
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Profit")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text(formatCurrency(totalStakingProfit))
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(totalStakingProfit >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // ROI
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROI")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(stakingROI, specifier: "%.1f")%")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(stakingROI >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Win Rate
                VStack(alignment: .leading, spacing: 4) {
                    Text("Win Rate")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(stakingWinRate, specifier: "%.1f")%")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var backedPerformanceView: some View {
        VStack(spacing: 12) {
            Text("Your Backed Performance")
                .font(.plusJakarta(.title2, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                // Total Profit for backed
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Profit")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text(formatCurrency(totalBackedProfit))
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(totalBackedProfit >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // ROI
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROI")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(backedROI, specifier: "%.1f")%")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(backedROI >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Win Rate
                VStack(alignment: .leading, spacing: 4) {
                    Text("Win Rate")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(backedWinRate, specifier: "%.1f")%")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .padding(.horizontal, 16)
    }
    


    @MainActor 
    private func fetchStakesData() {
        Task {
            await performStakesDataRefresh(showLoadingState: !hasInitiallyLoaded)
        }
    }
    
    // Core data fetching logic
    private func performStakesDataRefresh(showLoadingState: Bool) async {
        guard let userId = currentUserId else { return }
        
        if showLoadingState {
            await MainActor.run {
                self.isLoading = true
                self.errorMessage = nil
            }
        }
        
        do {
            let stakes = try await stakeService.fetchStakes(forUser: userId)
            let manualStakers = try await manualStakerService.fetchManualStakers(forUser: userId)
            
            // CRITICAL: Pre-load ALL user profiles to prevent race conditions
            let uniquePartnerIds = Set<String>(stakes.compactMap { stake in
                // Only fetch app users, not manual stakers
                guard stake.isOffAppStake != true else { return nil }
                return stake.stakerUserId == userId ? stake.stakedPlayerUserId : stake.stakerUserId
            })
            
            print("Dashboard: Pre-loading \(uniquePartnerIds.count) user profiles to fix race condition")
            
            // Load all user profiles concurrently BEFORE updating UI
            for partnerId in uniquePartnerIds {
                guard !Task.isCancelled else { return }
                do {
                    await userService.fetchUser(id: partnerId)
                    print("Dashboard: Loaded profile for user \(partnerId)")
                } catch {
                    print("Dashboard: Failed to load profile for user \(partnerId): \(error)")
                }
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.stakes = stakes.filter { stake in
                    // If current user is the staker and the invite is still pending, hide it from dashboard
                    if stake.stakerUserId == userId, let pending = stake.invitePending, pending {
                        return false
                    }
                    return true
                }
                self.manualStakers = manualStakers
                self.isLoading = false
                self.hasInitiallyLoaded = true
                
                print("Dashboard: Loaded \(stakes.count) stakes, \(manualStakers.count) manual stakers")
                print("Dashboard: Pre-loaded \(self.userService.loadedUsers.count) user profiles")
                print("Dashboard: Manual stakers: \(manualStakers.map { "\($0.name) - \($0.contactInfo ?? "no contact")" })")
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.hasInitiallyLoaded = true
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
    
    // Background refresh that doesn't show loading animation
    private func refreshStakesDataInBackground() {
        // Don't start a new refresh if one is already in progress
        guard !isBackgroundRefreshing else { return }
        
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        // Debounce rapid refresh calls
        refreshTask = Task {
            // Small delay to debounce rapid calls
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.isBackgroundRefreshing = true
            }
            
            await performStakesDataRefresh(showLoadingState: false)
            
            await MainActor.run {
                self.isBackgroundRefreshing = false
            }
        }
    }
}

struct StakeCompactCard: View {
    let stake: Stake
    let currentUserId: String
    let onTap: () -> Void
    
    @EnvironmentObject var userService: UserService // Access user profiles
    
    // Determine role and partner details
    private var playerIsCurrentUser: Bool { stake.stakedPlayerUserId == currentUserId }
    private var stakerIsCurrentUser: Bool { stake.stakerUserId == currentUserId }
    private var partnerId: String { playerIsCurrentUser ? stake.stakerUserId : stake.stakedPlayerUserId }
    
    private var partnerName: String {
        // Add safety check for empty partnerId
        guard !partnerId.isEmpty else {
            return "Unknown User"
        }
        
        if stake.isOffAppStake == true, let manualName = stake.manualStakerDisplayName, !manualName.isEmpty {
            return manualName
        } else if let profile = userService.loadedUsers[partnerId] {
            return profile.displayName ?? profile.username
        } else {
            // This should not happen if pre-loading worked correctly
            print("Dashboard: WARNING - User profile not loaded for \(partnerId)")
            return "Loading..."
        }
    }
    private var roleLine: String {
        if stakerIsCurrentUser {
            return "You staked \(partnerName)"
        } else {
            return "You were staked by \(partnerName)"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Main info column
                VStack(alignment: .leading, spacing: 2) {
                    Text(roleLine)
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(stake.sessionDate, style: .date)")
                        .font(.plusJakarta(.caption, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Amount & status column
                VStack(alignment: .trailing, spacing: 2) {
                    // Check if this is awaiting session start
                    let isAwaitingSession = stake.status == .active && 
                                          stake.totalPlayerBuyInForSession == 0 && 
                                          stake.playerCashoutForSession == 0
                    
                    if isAwaitingSession {
                        Text("Awaiting Session")
                            .font(.plusJakarta(.callout, weight: .bold))
                            .foregroundColor(.orange)
                    } else if stake.amountTransferredAtSettlement == 0 {
                        Text("Even")
                            .font(.plusJakarta(.callout, weight: .bold))
                            .foregroundColor(.gray)
                    } else {
                        Text(formatCurrency(abs(stake.amountTransferredAtSettlement)))
                            .font(.plusJakarta(.callout, weight: .bold))
                            .foregroundColor(stake.amountTransferredAtSettlement < 0 ? .red : .green)
                    }
                    
                    if stake.status == .settled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                    } else {
                        Text(stake.status.displayName)
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        // User profiles should already be pre-loaded by fetchStakesData()
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

// New aggregated partner summary card
struct PartnerStakeSummaryCard: View {
    let stakes: [Stake]
    let currentUserId: String
    let manualStakers: [ManualStakerProfile] // Pass manual stakers directly
    let onTap: () -> Void
    let groupKey: String? // Add this to identify the partner group
    
    @EnvironmentObject var userService: UserService
    
    private var partnerId: String {
        guard let sample = stakes.first else { return "" }
        return (sample.stakedPlayerUserId == currentUserId) ? sample.stakerUserId : sample.stakedPlayerUserId
    }
    private var isManualStake: Bool {
        if let firstStake = stakes.first {
            return firstStake.isOffAppStake == true
        } else {
            // If no stakes, check if this is a manual staker by looking at the group key
            return groupKey?.hasPrefix("manual_") ?? false
        }
    }
    private var partnerName: String {
        if isManualStake {
            if let manualName = stakes.first?.manualStakerDisplayName, !manualName.isEmpty {
                return manualName
            } else if let groupKey = groupKey, groupKey.hasPrefix("manual_") {
                // Extract manual staker name from group key
                return String(groupKey.dropFirst(7)) // Remove "manual_" prefix
            }
        } else if let profile = userService.loadedUsers[partnerId] {
            return profile.displayName ?? profile.username
        }
        // This should not happen if pre-loading worked correctly
        print("Dashboard: WARNING - Partner name not found for partnerId: \(partnerId), isManual: \(isManualStake)")
        return "Unknown User"
    }
    
    private var manualStakerProfile: ManualStakerProfile? {
        guard isManualStake else { return nil }
        let name: String
        if let manualName = stakes.first?.manualStakerDisplayName, !manualName.isEmpty {
            name = manualName
        } else if let groupKey = groupKey, groupKey.hasPrefix("manual_") {
            name = String(groupKey.dropFirst(7))
        } else {
            return nil
        }
        let profile = manualStakers.first { $0.name == name }
        if let profile = profile {
            print("Found manual staker profile: \(profile.name), contactInfo: '\(profile.contactInfo ?? "nil")'")
        } else {
            print("Could not find manual staker profile for name: \(name)")
            print("Available manual stakers: \(manualStakers.map { $0.name })")
        }
        return profile
    }
    
    private var partnerSubtitle: String {
        // For manual stakers, always try to show contact info first
        if isManualStake, let profile = manualStakerProfile {
            if let contactInfo = profile.contactInfo, !contactInfo.isEmpty {
                return contactInfo
            } else if let notes = profile.notes, !notes.isEmpty {
                return notes
            }
        }
        
        // Fall back to stake count or "No stakes yet"
        if stakes.isEmpty {
            return "No stakes yet"
        } else {
            return "\(stakes.count) stake\(stakes.count == 1 ? "" : "s")"
        }
    }
    // Net across ALL stakes (settled + unsettled) for color reference
    private var totalProfit: Double {
        stakes.reduce(0) { total, stake in
            let isCurrentUserStaker = stake.stakerUserId == currentUserId
            let amount = stake.amountTransferredAtSettlement
            // FIXED: Inverse logic for both roles
            return total + (isCurrentUserStaker ? -amount : amount)
        }
    }
    // Outstanding (unsettled) amount still owed
    private var outstandingNet: Double {
        stakes.filter { $0.status != .settled }.reduce(0) { total, stake in
            let isCurrentUserStaker = stake.stakerUserId == currentUserId
            let amount = stake.amountTransferredAtSettlement
            // FIXED: Inverse logic for both roles
            return total + (isCurrentUserStaker ? -amount : amount)
        }
    }
    
    // Check if there are active stakes waiting for session to start
    private var hasActiveStakes: Bool {
        stakes.contains { stake in
            stake.status == .active && 
            stake.totalPlayerBuyInForSession == 0 && 
            stake.playerCashoutForSession == 0
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Group {
                    if let profile = userService.loadedUsers[partnerId],
                       let avatarURL = profile.avatarURL, !avatarURL.isEmpty,
                       let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                Text(String(partnerName.prefix(1)))
                                    .font(.plusJakarta(.headline, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .frame(width: 40, height: 40)
                    }
                }
                .shadow(radius: 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(partnerName)
                        .font(.plusJakarta(.subheadline, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(partnerSubtitle)
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if outstandingNet != 0 {
                        Text(outstandingNet > 0 ? "You Owe Them" : "They Owe You")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.gray)
                        Text(formatCurrency(abs(outstandingNet)))
                            .font(.plusJakarta(.callout, weight: .bold))
                            .foregroundColor(outstandingNet > 0 ? .red : .green)
                    } else if hasActiveStakes {
                        Text("Awaiting Session")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.orange)
                    } else {
                        Text("Settled")
                            .font(.plusJakarta(.caption2, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if !isManualStake && !partnerId.isEmpty && userService.loadedUsers[partnerId] == nil {
                Task { await userService.fetchUser(id: partnerId) }
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

// View listing all stakes with a particular partner
struct PartnerStakesListView: View {
    let partnerName: String
    @State private var stakes: [Stake]
    let currentUserId: String
    let groupKey: String? // Add this to identify manual stakers
    let manualStakers: [ManualStakerProfile] // Pass manual stakers directly
    let stakeService: StakeService
    let userService: UserService
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sheetManager = StakingSheetManager()
    @State private var selectedTab: PartnerTab = .summary
    
    init(partnerName: String, stakes: [Stake], currentUserId: String, groupKey: String?, manualStakers: [ManualStakerProfile], stakeService: StakeService, userService: UserService) {
        self.partnerName = partnerName
        self._stakes = State(initialValue: stakes)
        self.currentUserId = currentUserId
        self.groupKey = groupKey
        self.manualStakers = manualStakers
        self.stakeService = stakeService
        self.userService = userService
    }
    
    enum PartnerTab {
        case summary
        case history
    }
    
    // MARK: - Manual staker detection
    private var isManualStaker: Bool {
        if let firstStake = stakes.first {
            return firstStake.isOffAppStake == true
        } else {
            return groupKey?.hasPrefix("manual_") ?? false
        }
    }
    
    private var manualStakerProfile: ManualStakerProfile? {
        guard isManualStaker else { return nil }
        let name: String
        if let manualName = stakes.first?.manualStakerDisplayName, !manualName.isEmpty {
            name = manualName
        } else if let groupKey = groupKey, groupKey.hasPrefix("manual_") {
            name = String(groupKey.dropFirst(7))
        } else {
            return nil
        }
        let profile = manualStakers.first { $0.name == name }
        if let profile = profile {
            print("PartnerStakesListView: Found manual staker profile: \(profile.name), contactInfo: '\(profile.contactInfo ?? "nil")'")
        } else {
            print("PartnerStakesListView: Could not find manual staker profile for name: \(name)")
            print("PartnerStakesListView: Available manual stakers: \(manualStakers.map { $0.name })")
        }
        return profile
    }
    
    // MARK: - Settled/unsettled splits
    private var settledStakes: [Stake] { stakes.filter { $0.status == .settled } }
    private var unsettledStakes: [Stake] { stakes.filter { $0.status != .settled } }

    private var settledAsStaker: [Stake] { settledStakes.filter { $0.stakerUserId == currentUserId } }
    private var settledAsPlayer: [Stake] { settledStakes.filter { $0.stakedPlayerUserId == currentUserId } }

    private var unsettledNet: Double {
        unsettledStakes.reduce(0) { total, stake in
            let isCurrentUserStaker = stake.stakerUserId == currentUserId
            let amount = stake.amountTransferredAtSettlement
            // FIXED: Correct interpretation - negative amount means staker pays player
            return total + (isCurrentUserStaker ? -amount : amount)
        }
    }

    // Staker aggregates  
    private var stakerProfit: Double { settledAsStaker.reduce(0) { $0 - $1.amountTransferredAtSettlement } }
    private var stakerCost: Double { settledAsStaker.reduce(0) { $0 + $1.stakerCost } }
    private var stakerROI: Double { stakerCost > 0 ? (stakerProfit / stakerCost) * 100 : 0 }
    private var stakerWinRate: Double { 
        let total = settledAsStaker.filter { $0.status == .settled }
        guard !total.isEmpty else { return 0 }
        let wins = total.filter { $0.amountTransferredAtSettlement < 0 }.count
        return Double(wins) / Double(total.count) * 100
    }

    // Player aggregates
    private var playerProfit: Double { settledAsPlayer.reduce(0) { $0 + $1.amountTransferredAtSettlement } }
    private var playerCost: Double { settledAsPlayer.reduce(0) { $0 + ($1.totalPlayerBuyInForSession * (1 - $1.stakePercentage)) } }
    private var playerROI: Double { playerCost > 0 ? (playerProfit / playerCost) * 100 : 0 }
    private var playerWinRate: Double {
        let total = settledAsPlayer.filter { $0.status == .settled }
        guard !total.isEmpty else { return 0 }
        let wins = total.filter { $0.amountTransferredAtSettlement > 0 }.count
        return Double(wins) / Double(total.count) * 100
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Bar
                    HStack(spacing: 0) {
                        partnerTabButton(title: "Summary", tab: .summary)
                        partnerTabButton(title: "History", tab: .history)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    // Tab Content
                    if selectedTab == .summary {
                        summaryView
                    } else {
                        historyView
                    }
                }
            }
            .navigationTitle(partnerName.isEmpty ? "Unknown Partner" : partnerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $sheetManager.showingStakeDetail, onDismiss: {
            sheetManager.dismissStakeDetail()
            // Force immediate refresh when stake detail sheet is dismissed
            Task {
                await refreshStakesData()
            }
        }) {
            if let stake = sheetManager.selectedStake {
                StakeDetailViewWrapper(
                    stake: stake,
                    currentUserId: currentUserId,
                    stakeService: stakeService,
                    userService: userService,
                    onUpdate: {
                        // Trigger immediate refresh of stakes data for this partner
                        Task {
                            await refreshStakesData()
                        }
                    }
                )
            }
        }
        .onAppear {
            print("PartnerStakesListView: Opened with partnerName: '\(partnerName)'")
            print("PartnerStakesListView: Stakes count: \(stakes.count)")
            print("PartnerStakesListView: GroupKey: '\(groupKey ?? "nil")'")
            print("PartnerStakesListView: Manual stakers count: \(manualStakers.count)")
        }
    }
    
    // Method to refresh stakes data for this partner
    @MainActor
    private func refreshStakesData() async {
        do {
            // Fetch all stakes for the current user
            let allStakes = try await stakeService.fetchStakes(forUser: currentUserId)
            
            // Filter to get only stakes relevant to this partner
            let partnerStakes: [Stake]
            if let groupKey = groupKey, groupKey.hasPrefix("manual_") {
                // Manual staker - groupKey is "manual_" + stakerName
                let manualName = String(groupKey.dropFirst(7))
                partnerStakes = allStakes.filter { stake in
                    stake.isOffAppStake == true && 
                    stake.manualStakerDisplayName == manualName &&
                    stake.stakedPlayerUserId == currentUserId
                }
            } else if let partnerId = groupKey, !partnerId.isEmpty {
                // App user stakes - groupKey is the actual partnerId
                partnerStakes = allStakes.filter { stake in
                    stake.isOffAppStake != true && (
                        (stake.stakerUserId == partnerId && stake.stakedPlayerUserId == currentUserId) ||
                        (stake.stakedPlayerUserId == partnerId && stake.stakerUserId == currentUserId)
                    )
                }
            } else {
                // Fallback - no valid groupKey
                partnerStakes = []
            }
            
            self.stakes = partnerStakes.sorted { $0.sessionDate > $1.sessionDate }
            print("PartnerStakesListView: Refreshed data, found \(partnerStakes.count) stakes for partner")
        } catch {
            print("PartnerStakesListView: Failed to refresh stakes data: \(error)")
        }
    }
    
    // MARK: - Tab Button
    private func partnerTabButton(title: String, tab: PartnerTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == tab ? Color.white.opacity(0.15) : Color.clear)
                )
        }
    }
    
    // MARK: - Summary View
    @ViewBuilder
    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Aggregated stats
                statsHeader
                
                // Only show active/unsettled stakes in summary
                LazyVStack(spacing: 16) {
                    ForEach(unsettledStakes) { stake in
                        StakeCompactCard(stake: stake, currentUserId: currentUserId) {
                            sheetManager.presentStakeDetail(stake: stake)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                if unsettledStakes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                        Text("All stakes settled")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.gray)
                        Text("Check the History tab to see past settlements")
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - History View
    @ViewBuilder
    private var historyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // History header with settled stats
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Completed Stakes")
                            .font(.plusJakarta(.title2, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text("\(settledStakes.count) settled")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    // Historical performance summary
                    if !settledStakes.isEmpty {
                        VStack(spacing: 12) {
                            if !settledAsStaker.isEmpty {
                                roleStatsCard(title: "As Staker", profit: stakerProfit, roi: stakerROI, winRate: stakerWinRate)
                            }
                            if !settledAsPlayer.isEmpty {
                                roleStatsCard(title: "As Player", profit: playerProfit, roi: playerROI, winRate: playerWinRate)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Settled stakes list
                LazyVStack(spacing: 16) {
                    ForEach(settledStakes) { stake in
                        StakeCompactCard(stake: stake, currentUserId: currentUserId) {
                            sheetManager.presentStakeDetail(stake: stake)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                if settledStakes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                        Text("No completed stakes")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.gray)
                        Text("Settled stakes will appear here")
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    @ViewBuilder
    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            outstandingBanner
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary vs \(partnerName.isEmpty ? "Unknown Partner" : partnerName)")
                    .font(.plusJakarta(.title2, weight: .bold))
                    .foregroundColor(.white)
                
                // Show contact info for manual stakers
                if isManualStaker, let profile = manualStakerProfile {
                    
                    
                    if let contactInfo = profile.contactInfo, !contactInfo.isEmpty {
                        
                        Text(contactInfo)
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.gray)
                    } else if let notes = profile.notes, !notes.isEmpty {
                        
                        Text(notes)
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.gray)
                    }
                } else {
                    
                }
            }
            
            // Cards
            VStack(spacing: 12) {
                if !settledAsStaker.isEmpty {
                    roleStatsCard(title: "As Staker", profit: stakerProfit, roi: stakerROI, winRate: stakerWinRate)
                }
                if !settledAsPlayer.isEmpty {
                    roleStatsCard(title: "As Player", profit: playerProfit, roi: playerROI, winRate: playerWinRate)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func roleStatsCard(title: String, profit: Double, roi: Double, winRate: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(.white)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Profit")
                        .font(.plusJakarta(.caption2, weight: .medium))
                        .foregroundColor(.gray)
                    Text(formatCurrency(profit))
                        .font(.plusJakarta(.callout, weight: .bold))
                        .foregroundColor(profit >= 0 ? .green : .red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROI")
                        .font(.plusJakarta(.caption2, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(roi, specifier: "%.1f")%")
                        .font(.plusJakarta(.callout, weight: .bold))
                        .foregroundColor(roi >= 0 ? .green : .red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win Rate")
                        .font(.plusJakarta(.caption2, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(winRate, specifier: "%.1f")%")
                        .font(.plusJakarta(.callout, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    @ViewBuilder
    private var outstandingBanner: some View {
        let hasAwaitingSessionStakes = stakes.contains { stake in
            stake.status == .active && 
            stake.totalPlayerBuyInForSession == 0 && 
            stake.playerCashoutForSession == 0
        }
        
        if unsettledNet != 0 {
            let youAreOwed = unsettledNet > 0
            HStack {
                Image(systemName: youAreOwed ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(youAreOwed ? .green : .red)
                Text(!youAreOwed ? "They currently owe you" : "You currently owe them")
                    .font(.plusJakarta(.subheadline, weight: .medium))
                Spacer()
                Text(formatCurrency(abs(unsettledNet)))
                    .font(.plusJakarta(.headline, weight: .bold))
                    .foregroundColor(youAreOwed ? .green : .red)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
        } else if hasAwaitingSessionStakes {
            HStack {
                Image(systemName: "clock.circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
                Text("Waiting for session to start")
                    .font(.plusJakarta(.subheadline, weight: .medium))
                Spacer()
                Text("Event Stakes")
                    .font(.plusJakarta(.headline, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

struct StakeDetailView: View {
    let initialStake: Stake
    let currentUserId: String
    let stakeService: StakeService
    let userService: UserService
    var onUpdate: () -> Void

    @State private var stake: Stake
    @State private var isSettling = false
    @State private var showUserDetails: [String: UserProfile] = [:]
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isEditingResults = false
    @State private var editableBuyIn = ""
    @State private var editableCashout = ""
    @State private var isUpdatingResults = false
    @Environment(\.dismiss) private var dismiss
    
    init(stake: Stake, currentUserId: String, stakeService: StakeService, userService: UserService, onUpdate: @escaping () -> Void) {
        self.initialStake = stake
        self.currentUserId = currentUserId
        self.stakeService = stakeService
        self.userService = userService
        self.onUpdate = onUpdate
        self._stake = State(initialValue: stake)
    }
    
    private var playerIsCurrentUser: Bool {
        stake.stakedPlayerUserId == currentUserId
    }

    private var stakerIsCurrentUser: Bool {
        stake.stakerUserId == currentUserId
    }
    
    // Determine if the stake involves an off-app (manual) staker
    private var isManualStake: Bool {
        stake.isOffAppStake == true
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(stake.sessionGameName) - \(stake.sessionStakes)")
                            .font(.plusJakarta(.title, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(stake.sessionDate, style: .date)")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    // Role and terms
                    roleAndTermsView
                    
                    // Event results
                    eventResultsView
                    
                    // Settlement summary
                    settlementSummaryView
                    
                    // Action button
                    if stake.status != .settled {
                        actionButton
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 50)
                .padding(20)
            }
        }
        .navigationTitle("Stake Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .onAppear {
            fetchNeededUserProfiles()
            initializeEditableFields()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var roleAndTermsView: some View {
        let partnerId = playerIsCurrentUser ? stake.stakerUserId : stake.stakedPlayerUserId
        let partnerProfile = showUserDetails[partnerId]
        
        // Compute partner name in a single expression to avoid non-View statements inside ViewBuilder
        let partnerNameDisplay: String = {
            if isManualStake, let manualName = stake.manualStakerDisplayName, !manualName.isEmpty {
                return manualName
            } else if let profile = partnerProfile {
                return profile.displayName ?? profile.username
            } else {
                return partnerId == Stake.OFF_APP_STAKER_ID ? "Manual Staker" : "The Other Party"
            }
        }()

        let finalPartnerName = partnerId.isEmpty ? "Unknown Party" : partnerNameDisplay

        VStack(alignment: .leading, spacing: 8) {
            Text("Stake Details")
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                if playerIsCurrentUser {
                    Text("\(finalPartnerName) staked you")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                } else if stakerIsCurrentUser {
                    Text("You staked \(finalPartnerName)")
                        .font(.plusJakarta(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text("\(stake.stakePercentage * 100, specifier: "%.0f")% at \(stake.markup, specifier: "%.2f")x markup")
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
    
    @ViewBuilder
    private var eventResultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session Results")
                    .font(.plusJakarta(.headline, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Show edit button for tournament stakes and if results haven't been entered
                if stake.isTournamentSession == true && 
                   stake.status == .active && 
                   (stake.totalPlayerBuyInForSession == 0 || stake.playerCashoutForSession == 0) &&
                   !isEditingResults {
                    Button(action: {
                        isEditingResults = true
                    }) {
                        Text("Edit Results")
                            .font(.plusJakarta(.caption, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if isEditingResults {
                editableResultsView
            } else {
                staticResultsView
            }
        }
    }
    
    @ViewBuilder
    private var staticResultsView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Buy-in:")
                    .font(.plusJakarta(.body, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                if stake.totalPlayerBuyInForSession == 0 {
                    Text("Not entered")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("\(formatCurrency(stake.totalPlayerBuyInForSession))")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            HStack {
                Text("Cashout:")
                    .font(.plusJakarta(.body, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                // FIXED: Use status to determine if results have been entered, not just cashout value
                if stake.status == .active && stake.totalPlayerBuyInForSession > 0 && stake.playerCashoutForSession == 0 {
                    Text("Not entered")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("\(formatCurrency(stake.playerCashoutForSession))")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    @ViewBuilder
    private var editableResultsView: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Buy-in Amount")
                    .font(.plusJakarta(.caption, weight: .semibold))
                    .foregroundColor(.white)
                
                TextField("Enter buy-in amount", text: $editableBuyIn)
                    .font(.plusJakarta(.body, weight: .medium))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Cashout Amount")
                    .font(.plusJakarta(.caption, weight: .semibold))
                    .foregroundColor(.white)
                
                TextField("Enter cashout amount", text: $editableCashout)
                    .font(.plusJakarta(.body, weight: .medium))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    isEditingResults = false
                    initializeEditableFields() // Reset fields
                }) {
                    Text("Cancel")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                        )
                }
                
                Button(action: updateSessionResults) {
                    HStack {
                        if isUpdatingResults {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.plusJakarta(.subheadline, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(canSaveResults ? Color.green : Color.gray)
                    )
                }
                .disabled(!canSaveResults || isUpdatingResults)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var canSaveResults: Bool {
        guard let buyIn = Double(editableBuyIn),
              let cashout = Double(editableCashout) else {
            return false
        }
        return buyIn >= 0 && cashout >= 0
    }
    
    @ViewBuilder
    private var settlementSummaryView: some View {
        let amount = stake.amountTransferredAtSettlement
        let isAwaitingSession = stake.status == .active && 
                              stake.totalPlayerBuyInForSession == 0 && 
                              stake.playerCashoutForSession == 0
        let (owingParty, owedParty, absAmount, isEven) = determineSettlementParties(
            amount: amount,
            playerName: showUserDetails[stake.stakedPlayerUserId]?.displayName ?? showUserDetails[stake.stakedPlayerUserId]?.username ?? "Player",
            stakerName: (isManualStake ? stake.manualStakerDisplayName : (showUserDetails[stake.stakerUserId]?.displayName ?? showUserDetails[stake.stakerUserId]?.username)) ?? "Staker",
            youArePlayer: playerIsCurrentUser,
            youAreStaker: stakerIsCurrentUser
        )

        VStack(alignment: .leading, spacing: 8) {
            Text("Settlement")
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                if isAwaitingSession {
                    Text("Awaiting Session Start")
                        .font(.plusJakarta(.title3, weight: .semibold))
                        .foregroundColor(.orange)
                    Text("Session not started yet")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(.gray)
                } else if isEven {
                    Text("Settled Evenly")
                        .font(.plusJakarta(.title3, weight: .semibold))
                        .foregroundColor(.gray)
                    Text("\(formatCurrency(0))")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(.gray)
                } else {
                    let owesText = (owingParty == "You") ? "You owe \(owedParty)" : "\(owingParty) owes \(owedParty)"
                    Text(owesText)
                        .font(.plusJakarta(.title3, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("\(formatCurrency(absAmount))")
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(amount > 0 ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        // Manual stakers now follow the same settlement flow as app users
        if stake.status == .awaitingSettlement {
            Button(action: { 
                if isManualStake {
                    settleManualStake()
                } else {
                    initiateSettlement()
                }
            }) {
                HStack {
                    if isSettling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "checkmark.circle")
                        Text(isManualStake ? "Mark as Settled" : "Mark as Settled")
                    }
                }
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(.black)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
            }
            .disabled(isSettling)
        } else if stake.status == .awaitingConfirmation {
            if stake.settlementInitiatorUserId != currentUserId {
                Button(action: { confirmSettlement() }) {
                    HStack {
                        if isSettling {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.seal")
                            Text("Confirm Settlement")
                        }
                    }
                    .font(.plusJakarta(.headline, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(12)
                }
                .disabled(isSettling)
            } else {
                HStack {
                    ProgressView().tint(.yellow)
                    Text("Pending Other Party's Confirmation")
                        .font(.plusJakarta(.headline, weight: .semibold))
                        .foregroundColor(.yellow)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // Helper functions
    private func determineSettlementParties(amount: Double, playerName: String, stakerName: String, youArePlayer: Bool, youAreStaker: Bool) -> (owing: String, owed: String, absAmount: Double, isEven: Bool) {
        if amount == 0 {
            return ("-", "-", 0, true)
        }
        
        let absAmountVal = abs(amount)
        var owingParty: String
        var owedParty: String
        
        // FIXED: The logic was backwards! 
        // amountTransferredAtSettlement = stakerShareOfCashout - stakerCost
        // Negative amount means staker pays player (staker gets less than they paid)
        // Positive amount means player pays staker (staker gets more than they paid)
        if amount > 0 { // Staker gets more than they paid -> Player pays Staker
            owingParty = youArePlayer ? "You" : playerName
            owedParty = youAreStaker ? "You" : stakerName
        } else { // Staker gets less than they paid -> Staker pays Player (amount is negative)
            owingParty = youAreStaker ? "You" : stakerName
            owedParty = youArePlayer ? "You" : playerName
        }
        return (owingParty, owedParty, absAmountVal, false)
    }
    
    private func refreshStakeData() async {
        guard let stakeId = stake.id else { return }
        
        do {
            // Fetch fresh stake data from the database
            let userStakes = try await stakeService.fetchStakes(forUser: currentUserId)
            if let updatedStake = userStakes.first(where: { $0.id == stakeId }) {
                await MainActor.run {
                    self.stake = updatedStake
                    print("StakeDetail: Successfully refreshed stake data, status: \(updatedStake.status)")
                }
            }
        } catch {
            print("StakeDetail: Failed to refresh stake data: \(error)")
        }
    }
    
    private func initiateSettlement() {
        guard let stakeId = stake.id else { return }
        guard !isSettling else { return } // Prevent multiple concurrent calls
        
        isSettling = true
        Task {
            do {
                try await stakeService.initiateSettlement(stakeId: stakeId, initiatorUserId: currentUserId)
                print("StakeDetail: Settlement initiated successfully")
                
                // Refresh the stake data to get the latest status
                await refreshStakeData()
                
                await MainActor.run {
                    onUpdate()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to initiate settlement: \(error.localizedDescription)"
                    self.showError = true
                }
                print("StakeDetail: Failed to initiate settlement: \(error)")
            }
            await MainActor.run {
                isSettling = false
            }
        }
    }

    private func initializeEditableFields() {
        editableBuyIn = stake.totalPlayerBuyInForSession > 0 ? "\(stake.totalPlayerBuyInForSession)" : ""
        editableCashout = stake.playerCashoutForSession > 0 ? "\(stake.playerCashoutForSession)" : ""
    }
    
    private func updateSessionResults() {
        guard let stakeId = stake.id,
              let buyIn = Double(editableBuyIn),
              let cashout = Double(editableCashout) else {
            return
        }
        
        guard !isUpdatingResults else { return }
        
        isUpdatingResults = true
        Task {
            do {
                // Update the stake with new session results
                try await stakeService.updateStakeSessionResults(
                    stakeId: stakeId,
                    buyIn: buyIn,
                    cashout: cashout
                )
                
                // Refresh the stake data
                await refreshStakeData()
                
                await MainActor.run {
                    isEditingResults = false
                    onUpdate()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to update session results: \(error.localizedDescription)"
                    self.showError = true
                }
                print("StakeDetail: Failed to update session results: \(error)")
            }
            await MainActor.run {
                isUpdatingResults = false
            }
        }
    }

    private func confirmSettlement() {
        guard let stakeId = stake.id else { return }
        guard stake.settlementInitiatorUserId != currentUserId else { 
            print("StakeDetail: Cannot confirm settlement - user is the initiator")
            return
        }
        guard !isSettling else { return } // Prevent multiple concurrent calls
        
        isSettling = true
        Task {
            do {
                try await stakeService.confirmSettlement(stakeId: stakeId, confirmingUserId: currentUserId)
                print("StakeDetail: Settlement confirmed successfully")
                
                // Refresh the stake data to get the latest status
                await refreshStakeData()
                
                await MainActor.run {
                    onUpdate() // This will refresh the data and show the updated status
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to confirm settlement: \(error.localizedDescription)"
                    self.showError = true
                }
                print("StakeDetail: Failed to confirm settlement: \(error)")
            }
            await MainActor.run {
                isSettling = false
            }
        }
    }
    
    private func settleManualStake() {
        guard let stakeId = stake.id else { return }
        guard !isSettling else { return } // Prevent multiple concurrent calls
        
        isSettling = true
        Task {
            do {
                try await stakeService.settleManualStake(stakeId: stakeId, userId: currentUserId)
                print("StakeDetail: Manual stake settled successfully")
                
                // Refresh the stake data to get the latest status
                await refreshStakeData()
                
                await MainActor.run {
                    onUpdate()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to settle manual stake: \(error.localizedDescription)"
                    self.showError = true
                }
                print("StakeDetail: Failed to settle manual stake: \(error)")
            }
            await MainActor.run {
                isSettling = false
            }
        }
    }

    private func fetchNeededUserProfiles() {
        let partnerId = playerIsCurrentUser ? stake.stakerUserId : stake.stakedPlayerUserId
        // Only fetch if it's not a manual stake and partnerId is not the placeholder
        if !isManualStake && partnerId != Stake.OFF_APP_STAKER_ID && showUserDetails[partnerId] == nil && !partnerId.isEmpty {
            Task {
                if let cachedUser = userService.loadedUsers[partnerId] {
                    DispatchQueue.main.async {
                        showUserDetails[partnerId] = cachedUser
                    }
                } else {
                    await userService.fetchUser(id: partnerId) 
                    DispatchQueue.main.async {
                        if let fetchedUser = userService.loadedUsers[partnerId] {
                            showUserDetails[partnerId] = fetchedUser
                        } else {

                        }
                    }
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

// Wrapper view to ensure proper state initialization and prevent white screen issues
struct StakeDetailViewWrapper: View {
    let stake: Stake
    let currentUserId: String
    @ObservedObject var stakeService: StakeService
    @ObservedObject var userService: UserService
    var onUpdate: () -> Void
    
    // Local state to ensure view is ready before presenting content
    @State private var isViewReady = false
    
    var body: some View {
        Group {
            if isViewReady {
                NavigationView {
                    StakeDetailView(
                        stake: stake,
                        currentUserId: currentUserId,
                        stakeService: stakeService,
                        userService: userService,
                        onUpdate: onUpdate
                    )
                }
            } else {
                // Loading state while ensuring all dependencies are ready
                ZStack {
                    AppBackgroundView().ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading...")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .onAppear {
            // Ensure view is marked as ready after a minimal delay
            // This prevents the white screen issue by ensuring all state is initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isViewReady = true
            }
        }
    }
}



// Extension for StakeStatus displayName
extension Stake.StakeStatus {
    var displayName: String {
        switch self {
        case .pendingAcceptance:
            return "Pending"
        case .active:
            return "Active"
        case .awaitingSettlement:
            return "Awaiting Settlement"
        case .awaitingConfirmation:
            return "Awaiting Confirmation"
        case .settled:
            return "Settled"
        case .declined:
            return "Declined"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Event Staking Invite Card
struct EventStakingInviteCard: View {
    let invite: EventStakingInvite
    let userService: UserService
    let onStatusChanged: (() -> Void)? // Callback to refresh parent view
    
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with event name and date
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.eventName)
                    .font(.plusJakarta(.headline, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(invite.eventDate, style: .date)
                    .font(.plusJakarta(.subheadline, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            // Staking details
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Percentage")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(invite.percentageBought, specifier: "%.1f")%")
                        .font(.plusJakarta(.callout, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Amount")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    Text(formatCurrency(invite.amountBought))
                        .font(.plusJakarta(.callout, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Status badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Status")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 4) {
                        Image(systemName: invite.status.icon)
                            .font(.system(size: 12))
                        Text(invite.status.displayName)
                            .font(.plusJakarta(.caption, weight: .semibold))
                    }
                    .foregroundColor(statusColor(invite.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(invite.status).opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            
            // Player info (who's being staked)
            if !invite.isManualStaker {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    Text("Staking for player")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray)
                    // TODO: Add player name lookup
                    Text("Player")
                        .font(.plusJakarta(.caption, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            // Action buttons (only show for pending invites)
            if invite.status == .pending {
                HStack(spacing: 12) {
                    // Decline button
                    Button(action: {
                        declineInvite()
                    }) {
                        Text("Decline")
                            .font(.plusJakarta(.subheadline, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(isProcessing)
                    
                    // Accept button
                    Button(action: {
                        acceptInvite()
                    }) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Accept")
                                    .font(.plusJakarta(.subheadline, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green)
                        )
                    }
                    .disabled(isProcessing)
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func acceptInvite() {
        guard let inviteId = invite.id else { return }
        isProcessing = true
        
        Task {
            do {
                let eventStakingService = EventStakingService()
                let stakeService = StakeService()
                
                // 1. Accept the invite
                try await eventStakingService.acceptStakingInvite(inviteId: inviteId)
                
                // 2. Create a Stake record in the regular staking system
                let stake = Stake(
                    id: nil,
                    sessionId: "event_\(invite.eventId)_\(UUID().uuidString)", // Create unique session ID for event
                    sessionGameName: invite.eventName,
                    sessionStakes: "Event Stakes",
                    sessionDate: invite.eventDate,
                    stakerUserId: invite.stakerUserId,
                    stakedPlayerUserId: invite.stakedPlayerUserId,
                    stakePercentage: invite.percentageBought / 100.0, // Convert percentage to decimal
                    markup: invite.markup,
                    totalPlayerBuyInForSession: 0, // Will be updated when session starts
                    playerCashoutForSession: 0, // Will be updated when session ends
                    status: .active, // Set to active since invite was accepted
                    proposedAt: Date(),
                    lastUpdatedAt: Date(),
                    settlementInitiatorUserId: nil,
                    settlementConfirmerUserId: nil,
                    isTournamentSession: true, // Mark as tournament session since it's event-based
                    manualStakerDisplayName: invite.manualStakerDisplayName,
                    isOffAppStake: invite.isManualStaker
                )
                
                try await stakeService.addStake(stake)
                
                await MainActor.run {
                    isProcessing = false
                    onStatusChanged?() // Refresh parent view
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to accept invite: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func declineInvite() {
        guard let inviteId = invite.id else { return }
        isProcessing = true
        
        Task {
            do {
                let eventStakingService = EventStakingService()
                try await eventStakingService.declineStakingInvite(inviteId: inviteId)
                
                await MainActor.run {
                    isProcessing = false
                    onStatusChanged?() // Refresh parent view
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to decline invite: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func statusColor(_ status: EventStakingInvite.InviteStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .declined:
            return .red
        case .expired:
            return .gray
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

