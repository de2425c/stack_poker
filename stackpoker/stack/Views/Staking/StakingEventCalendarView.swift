import SwiftUI
import FirebaseFirestore

struct StakingEventCalendarView: View {
    let currentUserId: String
    @ObservedObject var userService: UserService
    @ObservedObject var stakeService: StakeService
    let eventStakingService: EventStakingService
    let onInviteStatusChanged: () -> Void
    let onOpenStakeDetail: (Stake) -> Void
    
    @State private var eventStakingInvites: [EventStakingInvite] = []
    @State private var isLoading = true
    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    
    // Filter out declined events - no reason to show them
    private var relevantEvents: [EventStakingInvite] {
        return eventStakingInvites
            .filter { $0.status != .declined }
    }
    
    // Get events for selected date
    private var eventsForSelectedDate: [EventStakingInvite] {
        let calendar = Calendar.current
        return relevantEvents.filter { invite in
            calendar.isDate(invite.eventDate, inSameDayAs: selectedDate)
        }
    }
    
    // Get dates with events in current month
    private var datesWithEvents: Set<String> {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        return Set(relevantEvents.compactMap { invite in
            let inviteComponents = calendar.dateComponents([.year, .month], from: invite.eventDate)
            let currentComponents = calendar.dateComponents([.year, .month], from: currentMonth)
            
            if inviteComponents.year == currentComponents.year && 
               inviteComponents.month == currentComponents.month {
                return formatter.string(from: invite.eventDate)
            }
            return nil
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading events...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Month navigation header
                        monthNavigationHeader
                        
                        // Calendar grid
                        calendarGrid
                        
                        // Events for selected date
                        if !eventsForSelectedDate.isEmpty {
                            selectedDateEvents
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            fetchEventStakingInvites()
        }
    }
    
    // MARK: - Month Navigation Header
    private var monthNavigationHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text(monthYearString)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Calendar Grid
    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Day headers
            HStack {
                ForEach(Array(zip(["S", "M", "T", "W", "T", "F", "S"], 0..<7)), id: \.1) { day, index in
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar days
            let calendar = Calendar.current
            let monthInterval = calendar.dateInterval(of: .month, for: currentMonth)!
            let firstOfMonth = monthInterval.start
            let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
            let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                // Empty cells for days before month starts
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Text("")
                        .frame(height: 40)
                }
                
                                 // Days of the month
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)!
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let eventCount = getEventCount(for: date)
                    let isToday = calendar.isDateInToday(date)
                    
                    CalendarDayView(
                        day: day,
                        isSelected: isSelected,
                        eventCount: eventCount,
                        isToday: isToday,
                        onTap: {
                            selectedDate = date
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Selected Date Events
    private var selectedDateEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDateString)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(eventsForSelectedDate.count) event\(eventsForSelectedDate.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            ForEach(eventsForSelectedDate.sorted { $0.eventDate < $1.eventDate }) { invite in
                CompactStakingEventCard(
                    invite: invite,
                    currentUserId: currentUserId,
                    userService: userService,
                    eventStakingService: eventStakingService,
                    onStatusChanged: {
                        fetchEventStakingInvites() // Refresh calendar data
                        onInviteStatusChanged() // Call parent callback
                    },
                    onOpenStakeDetail: { stakeId in
                        openStakeDetail(stakeId: stakeId)
                    }
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Helper Functions
    private func hasEventsOnDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return relevantEvents.contains { invite in
            calendar.isDate(invite.eventDate, inSameDayAs: date)
        }
    }
    
    private func getEventCount(for date: Date) -> Int {
        let calendar = Calendar.current
        return relevantEvents.filter { invite in
            calendar.isDate(invite.eventDate, inSameDayAs: date)
        }.count
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private var selectedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: selectedDate)
    }
    
    private func previousMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func nextMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    // MARK: - Data Fetching
    private func fetchEventStakingInvites() {
        isLoading = true
        Task {
            do {
                // Fetch both types of event invites
                let stakerInvites = try await eventStakingService.fetchStakingInvitesAsStaker(userId: currentUserId)
                let playerInvites = try await eventStakingService.fetchStakingInvitesAsPlayer(userId: currentUserId)
                
                // ALSO fetch tournament stakes created via "Add Stake"
                let allStakes = try await stakeService.fetchStakes(forUser: currentUserId)
                let tournamentStakes = allStakes.filter { 
                    $0.isTournamentSession == true && 
                    $0.stakerUserId == currentUserId && // User is the staker
                    $0.isOffAppStake == true // Manual stakes
                }
                
                // Convert tournament stakes to EventStakingInvite format for calendar display
                let tournamentInvites = tournamentStakes.map { stake in
                    let inviteStatus: EventStakingInvite.InviteStatus = {
                        switch stake.status {
                        case .active:
                            // Check if cashout has been entered
                            if stake.totalPlayerBuyInForSession > 0 && stake.playerCashoutForSession > 0 {
                                return .accepted // Has results, ready for settlement
                            } else {
                                return .pending // Awaiting cashout input
                            }
                        case .awaitingSettlement, .awaitingConfirmation:
                            return .accepted
                        case .settled:
                            return .accepted
                        default:
                            return .pending
                        }
                    }()
                    
                    return EventStakingInvite(
                        id: stake.id,
                        eventId: stake.sessionId,
                        eventName: stake.sessionGameName,
                        eventDate: stake.sessionDate,
                        stakedPlayerUserId: stake.stakedPlayerUserId,
                        stakerUserId: stake.stakerUserId,
                        maxBullets: 1, // Default for now
                        markup: stake.markup,
                        percentageBought: stake.stakePercentage * 100,
                        amountBought: stake.stakerCost,
                        isManualStaker: true,
                        manualStakerDisplayName: stake.manualStakerDisplayName,
                        status: inviteStatus,
                        createdAt: stake.proposedAt,
                        lastUpdatedAt: stake.lastUpdatedAt
                    )
                }
                
                // Combine both invite types + tournament stakes
                let allEventInvites = stakerInvites + playerInvites + tournamentInvites
                
                // CRITICAL: Pre-load ALL user profiles to prevent race conditions
                let uniqueUserIds = Set<String>(allEventInvites.compactMap { invite in
                    // Only fetch app users, not manual stakers
                    guard !invite.isManualStaker else { return nil }
                    return invite.stakerUserId
                })
                
                print("Calendar: Pre-loading \(uniqueUserIds.count) user profiles to fix race condition")
                
                // Load all user profiles concurrently BEFORE updating UI
                for userId in uniqueUserIds {
                    do {
                        await userService.fetchUser(id: userId)
                        print("Calendar: Loaded profile for user \(userId)")
                    } catch {
                        print("Calendar: Failed to load profile for user \(userId): \(error)")
                    }
                }
                
                await MainActor.run {
                    self.eventStakingInvites = allEventInvites
                    self.isLoading = false
                    print("Calendar: Loaded \(stakerInvites.count) staker invites and \(playerInvites.count) player invites")
                    print("Calendar: Pre-loaded \(self.userService.loadedUsers.count) user profiles")
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Calendar: Error loading event invites: \(error)")
                }
            }
        }
    }
    
    private func openStakeDetail(stakeId: String) {
        Task {
            do {
                let allStakes = try await stakeService.fetchStakes(forUser: currentUserId)
                
                if let stake = allStakes.first(where: { $0.id == stakeId }) {
                    onOpenStakeDetail(stake)
                }
            } catch {
                print("Failed to fetch stake for detail: \(error)")
            }
        }
    }
}

// MARK: - Calendar Day View
struct CalendarDayView: View {
    let day: Int
    let isSelected: Bool
    let eventCount: Int
    let isToday: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)
                
                // Day number
                Text("\(day)")
                    .font(.system(size: 14, weight: isSelected || isToday ? .semibold : .medium))
                    .foregroundColor(textColor)
                
                // Event dots
                if eventCount > 0 && !isSelected {
                    VStack {
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(0..<min(eventCount, 3), id: \.self) { index in
                                Circle()
                                    .fill(dotColor)
                                    .frame(width: 4, height: 4)
                            }
                            
                            // Show "+" if more than 3 events
                            if eventCount > 3 {
                                Text("+")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(dotColor)
                            }
                        }
                        .offset(y: -2)
                    }
                }
            }
        }
        .frame(height: 40)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .white.opacity(0.2)
        } else if isToday {
            return .blue.opacity(0.3)
        } else {
            return .clear
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .white.opacity(0.8)
        }
    }
    
    private var dotColor: Color {
        return .orange
    }
}

// MARK: - Compact Staking Event Card
struct CompactStakingEventCard: View {
    let invite: EventStakingInvite
    let currentUserId: String
    let userService: UserService
    let eventStakingService: EventStakingService
    let onStatusChanged: () -> Void
    let onOpenStakeDetail: ((String) -> Void)? // New callback for opening stake detail
    
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var isUserThePlayer: Bool {
        invite.stakedPlayerUserId == currentUserId
    }
    
    private var canInteract: Bool {
        // Tournament stakes don't need accept/decline - they go straight to cashout input
        invite.stakerUserId == currentUserId && invite.status == .pending && !invite.eventId.hasPrefix("tournament_")
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Main Row - Event name, role, and status
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.eventName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: isUserThePlayer ? "person.crop.circle.fill" : "dollarsign.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isUserThePlayer ? .blue : .green)
                        
                        Text(isUserThePlayer ? "Being staked by" : "Staking")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text(stakerDisplayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    statusBadge
                    Text(formatEventTime(invite.eventDate))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            
            // Staking Details Row - Compact inline
            HStack(spacing: 12) {
                stakingDetailInline(label: "Stake", value: "\(String(format: "%.0f", invite.percentageBought))%")
                stakingDetailInline(label: "Amount", value: formatCurrency(invite.amountBought))
                stakingDetailInline(label: "Markup", value: "\(String(format: "%.1f", invite.markup))x")
                stakingDetailInline(label: "Bullets", value: "\(invite.maxBullets)")
                
                Spacer()
                
                // Action Buttons (if user can interact)
                if canInteract {
                    HStack(spacing: 6) {
                        Button(action: declineInvite) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .disabled(isProcessing)
                        
                        Button(action: acceptInvite) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .background(Color.green.opacity(0.8))
                        .clipShape(Circle())
                        .disabled(isProcessing)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(statusColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .onTapGesture {
            // For tournament stakes, open stake detail directly
            if invite.eventId.hasPrefix("tournament_"), let stakeId = invite.id {
                onOpenStakeDetail?(stakeId)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        // User profiles should already be pre-loaded by fetchEventStakingInvites()
    }
    
    // MARK: - Helper Views
    private var statusBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: statusIcon)
                .font(.system(size: 8))
            Text(statusDisplayText)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private var statusDisplayText: String {
        // Check if this is a tournament stake awaiting cashout
        if invite.status == .pending && invite.eventId.hasPrefix("tournament_") {
            return "Awaiting Cashout"
        }
        return invite.status.displayName
    }
    
    private var statusIcon: String {
        // Check if this is a tournament stake awaiting cashout
        if invite.status == .pending && invite.eventId.hasPrefix("tournament_") {
            return "dollarsign.circle"
        }
        return invite.status.icon
    }
    
    private func stakingDetail(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func stakingDetailInline(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private var statusColor: Color {
        switch invite.status {
        case .pending: return .orange
        case .accepted: return .green
        case .declined: return .red
        case .expired: return .gray
        }
    }
    
    private var stakerDisplayName: String {
        if invite.isManualStaker {
            return invite.manualStakerDisplayName ?? "Manual"
        } else if let stakerProfile = userService.loadedUsers[invite.stakerUserId] {
            return stakerProfile.displayName ?? stakerProfile.username
        } else {
            // This should not happen if pre-loading worked correctly
            print("Calendar: WARNING - User profile not loaded for \(invite.stakerUserId)")
            return "User \(invite.stakerUserId.prefix(8))..." 
        }
    }
    
    // MARK: - Actions
    private func acceptInvite() {
        guard let inviteId = invite.id else { return }
        isProcessing = true
        
        Task {
            do {
                let stakeService = StakeService()
                
                // 1. Accept the invite
                try await eventStakingService.acceptStakingInvite(inviteId: inviteId)
                
                // 2. Create a Stake record in the regular staking system
                let stake = Stake(
                    id: nil,
                    sessionId: "event_\(invite.eventId)_\(UUID().uuidString)",
                    sessionGameName: invite.eventName,
                    sessionStakes: "Event Stakes",
                    sessionDate: invite.eventDate,
                    stakerUserId: invite.stakerUserId,
                    stakedPlayerUserId: invite.stakedPlayerUserId,
                    stakePercentage: invite.percentageBought / 100.0,
                    markup: invite.markup,
                    totalPlayerBuyInForSession: 0,
                    playerCashoutForSession: 0,
                    status: .active,
                    proposedAt: Date(),
                    lastUpdatedAt: Date(),
                    settlementInitiatorUserId: nil,
                    settlementConfirmerUserId: nil,
                    isTournamentSession: true,
                    manualStakerDisplayName: invite.manualStakerDisplayName,
                    isOffAppStake: invite.isManualStaker
                )
                
                try await stakeService.addStake(stake)
                
                await MainActor.run {
                    isProcessing = false
                    onStatusChanged()
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
                try await eventStakingService.declineStakingInvite(inviteId: inviteId)
                
                await MainActor.run {
                    isProcessing = false
                    onStatusChanged()
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
    
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.1fk", amount / 1000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
} 
