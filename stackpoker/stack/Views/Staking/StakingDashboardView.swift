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

    @State private var stakes: [Stake] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @StateObject private var sheetManager = StakingSheetManager()

    private var currentUserId: String? {
        userService.currentUserProfile?.id
    }

    // Analytics for staking performance (when user is the staker)
    private var stakingPerformanceStakes: [Stake] {
        stakes.filter { $0.stakerUserId == currentUserId && $0.status == .settled }
    }
    
    private var totalStakingProfit: Double {
        stakingPerformanceStakes.reduce(0) { total, stake in
            // When user is staker, positive amountTransferredAtSettlement means staker receives money
            total + stake.amountTransferredAtSettlement
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
        let winningStakes = stakingPerformanceStakes.filter { $0.amountTransferredAtSettlement > 0 }.count
        return Double(winningStakes) / Double(totalStakes) * 100
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

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            VStack {
                if isLoading {
                    ProgressView("Loading Stakes...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else if stakes.isEmpty {
                    Text("No staking activity found.")
                        .font(.plusJakarta(.title3, weight: .medium))
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Staking Performance Analytics
                            stakingPerformanceView
                            
                            // Monthly stake cards
                            LazyVStack(spacing: 16) {
                                ForEach(stakesByMonth, id: \.0) { month, monthStakes in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(month)
                                            .font(.plusJakarta(.title2, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.leading, 16)
                                        
                                        ForEach(monthStakes) { stake in
                                            StakeCompactCard(stake: stake, currentUserId: currentUserId ?? "") {
                                                sheetManager.presentStakeDetail(stake: stake)
                                            }
                                            .padding(.horizontal, 16)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 30)
                        .padding(.bottom, 30)
                    }
                }
            }
            .padding(.top, 40)
            .onAppear(perform: fetchStakesData)
        }
        // Add onChange to properly handle state updates
        .onChange(of: sheetManager.showingStakeDetail) { _ in }
        .sheet(isPresented: $sheetManager.showingStakeDetail, onDismiss: {
            // Reset state on dismiss to prevent issues
            sheetManager.dismissStakeDetail()
        }) {
            // Only present sheet if we have a valid stake
            if let stake = sheetManager.selectedStake {
                StakeDetailViewWrapper(
                    stake: stake,
                    currentUserId: currentUserId ?? "",
                    stakeService: stakeService,
                    userService: userService,
                    onUpdate: {
                        sheetManager.dismissStakeDetail()
                        fetchStakesData()
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

    private func fetchStakesData() {
        guard let userId = currentUserId else {
            errorMessage = "User ID not found."
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetchedStakes = try await stakeService.fetchStakes(forUser: userId)
                DispatchQueue.main.async {
                    self.stakes = fetchedStakes
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
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

struct StakeCompactCard: View {
    let stake: Stake
    let currentUserId: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stake.sessionGameName) - \(stake.sessionStakes)")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(stake.sessionDate, style: .date)")
                        .font(.plusJakarta(.caption, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if stake.amountTransferredAtSettlement == 0 {
                        Text("Even")
                            .font(.plusJakarta(.callout, weight: .bold))
                            .foregroundColor(.gray)
                    } else {
                        Text(formatCurrency(abs(stake.amountTransferredAtSettlement)))
                            .font(.plusJakarta(.callout, weight: .bold))
                            .foregroundColor(stake.amountTransferredAtSettlement > 0 ? .green : .red)
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
    let stake: Stake
    let currentUserId: String
    @ObservedObject var stakeService: StakeService
    @ObservedObject var userService: UserService
    var onUpdate: () -> Void

    @State private var isSettling = false
    @State private var showUserDetails: [String: UserProfile] = [:]
    @Environment(\.dismiss) private var dismiss
    
    private var playerIsCurrentUser: Bool {
        stake.stakedPlayerUserId == currentUserId
    }

    private var stakerIsCurrentUser: Bool {
        stake.stakerUserId == currentUserId
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
        }
    }
    
    @ViewBuilder
    private var roleAndTermsView: some View {
        let partnerId = playerIsCurrentUser ? stake.stakerUserId : stake.stakedPlayerUserId
        let partnerProfile = showUserDetails[partnerId]
        let partnerName = partnerProfile?.displayName ?? partnerProfile?.username ?? "The Other Party"
        let finalPartnerName = partnerId.isEmpty ? "Unknown Party" : partnerName

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
            Text("Session Results")
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Buy-in:")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(formatCurrency(stake.totalPlayerBuyInForSession))")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                HStack {
                    Text("Cashout:")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(formatCurrency(stake.playerCashoutForSession))")
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
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
    private var settlementSummaryView: some View {
        let amount = stake.amountTransferredAtSettlement
        let (owingParty, owedParty, absAmount, isEven) = determineSettlementParties(
            amount: amount,
            playerName: showUserDetails[stake.stakedPlayerUserId]?.displayName ?? showUserDetails[stake.stakedPlayerUserId]?.username ?? "Player",
            stakerName: showUserDetails[stake.stakerUserId]?.displayName ?? showUserDetails[stake.stakerUserId]?.username ?? "Staker",
            youArePlayer: playerIsCurrentUser,
            youAreStaker: stakerIsCurrentUser
        )

        VStack(alignment: .leading, spacing: 8) {
            Text("Settlement")
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                if isEven {
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
        if stake.status == .awaitingSettlement {
            Button(action: { initiateSettlement() }) {
                HStack {
                    if isSettling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "checkmark.circle")
                        Text("Mark as Settled")
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
        
        if amount > 0 { // Player pays Staker
            owingParty = youArePlayer ? "You" : playerName
            owedParty = youAreStaker ? "You" : stakerName
        } else { // Staker pays Player (amount is negative)
            owingParty = youAreStaker ? "You" : stakerName
            owedParty = youArePlayer ? "You" : playerName
        }
        return (owingParty, owedParty, absAmountVal, false)
    }
    
    private func initiateSettlement() {
        guard let stakeId = stake.id else { return }
        isSettling = true
        Task {
            do {
                try await stakeService.initiateSettlement(stakeId: stakeId, initiatorUserId: currentUserId)
                onUpdate()
            } catch {
                print("Error initiating settlement: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                isSettling = false
            }
        }
    }

    private func confirmSettlement() {
        guard let stakeId = stake.id else { return }
        guard stake.settlementInitiatorUserId != currentUserId else { 
            print("Cannot confirm own settlement initiation.")
            return
        }
        isSettling = true
        Task {
            do {
                try await stakeService.confirmSettlement(stakeId: stakeId, confirmingUserId: currentUserId)
                onUpdate()
            } catch {
                print("Error confirming settlement: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                isSettling = false
            }
        }
    }

    private func fetchNeededUserProfiles() {
        let partnerId = playerIsCurrentUser ? stake.stakerUserId : stake.stakedPlayerUserId
        if showUserDetails[partnerId] == nil && !partnerId.isEmpty {
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
                            print("Still couldn't find user \(partnerId) in cache after fetch for StakeDetailView.")
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

