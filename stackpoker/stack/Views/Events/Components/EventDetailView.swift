import SwiftUI
import FirebaseAuth
import Kingfisher

// MARK: - Event Detail View
struct EventDetailView: View {
    let event: Event
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @Environment(\.presentationMode) var presentationMode
    
    @State private var isAddedToSchedule = false
    @State private var userEvent: UserEvent?
    @State private var currentUserRSVP: EventRSVP?
    @State private var attendees: [EventRSVP] = []
    @State private var isLoading = false
    @State private var isAddingToSchedule = false
    @State private var error: String?
    @State private var showError = false
    @State private var showingLiveSession = false
    @State private var showingStakingDetails = false
    @State private var existingStakingInvites: [EventStakingInvite] = []
    @State private var existingStakes: [Stake] = []
    @StateObject private var eventStakingService = EventStakingService()
    @StateObject private var stakeService = StakeService()


    // Computed properties for display
    private var formattedDate: String {
        event.simpleDate.displayMedium
    }
    
    private var formattedTime: String {
        event.time ?? "Time TBD"
    }
    
    private var buyinDisplay: String {
        event.buyin_string
    }
    
    private var eventStatus: UserEvent.EventStatus {
        let now = Date()
        let calendar = Calendar.current
        
        // Create date from SimpleDate
        let eventDate = calendar.date(from: DateComponents(
            year: event.simpleDate.year,
            month: event.simpleDate.month,
            day: event.simpleDate.day
        )) ?? Date()
        
        // Calculate completion time (12 hours after event start)
        let completionTime = calendar.date(byAdding: .hour, value: 12, to: eventDate) ?? eventDate
        
        // Compare dates
        if now >= completionTime {
            return .completed
        } else if calendar.isDate(now, inSameDayAs: eventDate) {
            return .active
        } else if eventDate > now {
            return .upcoming
        } else {
            return .completed
        }
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header Image / Event Type Icon
                    eventHeaderImage
                    
                    // Main Content VStack
                    VStack(alignment: .leading, spacing: 24) {
                        titleAndSeriesSection
                        eventDetailsSection
                        
                        if let description = event.description, !description.isEmpty {
                            descriptionBox(description)
                        }
                        
                        participantsSection
                        
                        // Show existing staking details if any exist
                        if isAddedToSchedule && (!existingStakingInvites.isEmpty || !existingStakes.isEmpty) {
                            existingStakingDetailsSection
                        }
                        
                        actionsButtonsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(customNavigationBar, alignment: .top)
        .alert("Error", isPresented: $showError, actions: { Button("OK") {} }, message: { Text(error ?? "An unknown error occurred.") })
        .onAppear {
            checkIfAddedToSchedule()
            fetchExistingStakingInvites()
            fetchExistingStakes()
        }
        .sheet(isPresented: $showingLiveSession) {
            EnhancedLiveSessionView(
                userId: Auth.auth().currentUser?.uid ?? "",
                sessionStore: SessionStore(userId: Auth.auth().currentUser?.uid ?? ""),
                preselectedEvent: event
            )
        }
        .sheet(isPresented: $showingStakingDetails, onDismiss: {
            // Refresh staking data when returning from staking details
            fetchExistingStakingInvites()
            fetchExistingStakes()
        }) {
            EventStakingDetailsView(event: event)
                .environmentObject(userService)
                .environmentObject(ManualStakerService())
        }
    }

    // MARK: - UI Sections
    private var eventHeaderImage: some View {
        ZStack(alignment: .bottomLeading) {
            // Event thematic background image based on series
            Image("stack_logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 280)
                .clipped()
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.7),
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.7)
                                ]),
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )
            
            // Content overlaid on the image
            VStack(alignment: .leading, spacing: 8) {
                // Event Status Badge
                Text(eventStatus.displayName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor(eventStatus).opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(statusColor(eventStatus).opacity(0.3), lineWidth: 1))

                // Event Title
                Text(event.event_name)
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .padding(20)
        }
    }
    
    private var titleAndSeriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let seriesName = event.series_name, !seriesName.isEmpty {
                HStack {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 255/255, green: 215/255, blue: 0/255))
                    Text(seriesName)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.white)
                }
            }
            
            HStack {
                Label("Tournament Event", systemImage: "crown.fill")
                    .font(.system(size: 14, design: .default))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(eventStatus.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(statusColor(eventStatus))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(eventStatus).opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 16)
    }
    
    private var eventDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(icon: "calendar", text: formattedDate)
            infoRow(icon: "clock.fill", text: formattedTime)
            infoRow(icon: "dollarsign.circle.fill", text: "Buy-in: \(buyinDisplay)")
        }
    }
    
    private func descriptionBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this Event")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 16, design: .default))
                .foregroundColor(.white)
                .lineSpacing(5)
        }
        .padding(.vertical, 16)
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Players (\(attendees.filter { $0.status == .going }.count))")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(.white)

                let goingAttendees = attendees.filter { $0.status == .going }
                
                if goingAttendees.isEmpty {
                    Text("No confirmed players yet")
                        .font(.system(size: 16, design: .default))
                        .foregroundColor(.white)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(goingAttendees) { rsvp in
                                attendeeAvatar(rsvp: rsvp)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }
    
    private func attendeeAvatar(rsvp: EventRSVP) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(rsvp.userDisplayName.prefix(1)))
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 2)
                )
            
            Text(rsvp.userDisplayName)
                .font(.system(size: 12, design: .default))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
    
    private var actionsButtonsSection: some View {
        VStack(spacing: 16) {
            if !isAddedToSchedule {
                // Add to Schedule Button
                Button(action: addToSchedule) {
                    HStack {
                        if isAddingToSchedule {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .frame(width: 20, height: 20)
                                .padding(.horizontal, 10)
                        } else {
                            Label("Add to My Events", systemImage: "calendar.badge.plus")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                        }
                    }
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
                    .cornerRadius(12)
                }
                .disabled(isAddingToSchedule)
            } else {
                // Already added to schedule
                if let currentUserRSVP = currentUserRSVP {
                    VStack(spacing: 12) {
                        // Show current RSVP status
                        HStack {
                            Image(systemName: currentUserRSVP.status.icon)
                                .foregroundColor(rsvpStatusColor(currentUserRSVP.status))
                            Text("You're \(currentUserRSVP.status.displayName.lowercased())")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        
                        // Remove from Schedule Button
                        Button(action: removeFromSchedule) {
                            Label("Remove from My Events", systemImage: "calendar.badge.minus")
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(12)
                        }
                        .disabled(isLoading)
                    }
                } else {
                    // Already added but no RSVP yet
                    VStack(spacing: 12) {
                        Button(action: rsvpAsGoing) {
                            Label("RSVP as Going", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
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
                                .cornerRadius(12)
                        }
                        
                        Button(action: removeFromSchedule) {
                            Label("Remove from My Events", systemImage: "calendar.badge.minus")
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(12)
                        }
                    }
                    .disabled(isLoading)
                }
            }
            
            // Add Staking Details Button (only show if event is added to schedule)
            if isAddedToSchedule {
                Button(action: {
                    showingStakingDetails = true
                }) {
                    Label((existingStakingInvites.isEmpty && existingStakes.isEmpty) ? "Add Staking Details" : "Edit Staking Details", systemImage: "person.2.fill")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 255/255, green: 149/255, blue: 0/255),
                                    Color(red: 255/255, green: 179/255, blue: 64/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                }
            }
            
            // Start Live Session Button
            Button(action: {
                showingLiveSession = true
            }) {
                Label("Start Live Session", systemImage: "play.circle.fill")
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 64/255, green: 156/255, blue: 255/255),
                                Color(red: 100/255, green: 180/255, blue: 255/255)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Custom Navigation Bar
    private var customNavigationBar: some View {
        VStack(spacing: 0) {
            // Status bar spacer
            Rectangle()
                .fill(Color.clear)
                .frame(height: UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
            
            // Navigation content
            HStack {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
        .background(Color.clear)
    }
    
    // MARK: - Helper Views & Functions
    private func infoRow(icon: String, text: String, subText: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(.white)
                if let subText = subText {
                    Text(subText)
                        .font(.system(size: 13, design: .default))
                        .foregroundColor(.white)
                }
            }
            Spacer()
        }
    }
    
    private func statusColor(_ status: UserEvent.EventStatus) -> Color {
        switch status {
        case .upcoming: return Color(red: 123/255, green: 255/255, blue: 99/255)
        case .active: return .orange
        case .completed: return .blue
        case .cancelled: return .red
        }
    }
    
    private func rsvpStatusColor(_ status: EventRSVP.RSVPStatus) -> Color {
        switch status {
        case .going: return Color(red: 123/255, green: 255/255, blue: 99/255)
        case .maybe: return .orange
        case .declined: return .red
        case .waitlisted: return Color(red: 64/255, green: 156/255, blue: 255/255)
        }
    }

    // MARK: - Data Actions
    private func checkIfAddedToSchedule() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        Task {
            do {
                // Always fetch all public event RSVPs to show attendees
                let publicRSVPs = try await userEventService.fetchPublicEventRSVPs(publicEventId: event.id)
                attendees = publicRSVPs.map { publicRSVP in
                    EventRSVP(
                        eventId: event.id,
                        userId: publicRSVP.userId,
                        userDisplayName: publicRSVP.userDisplayName,
                        status: EventRSVP.RSVPStatus(rawValue: publicRSVP.status.rawValue) ?? .going
                    )
                }
                
                // Check if current user has RSVP'd to this public event
                let publicRSVP = try await userEventService.fetchPublicEventRSVP(publicEventId: event.id, userId: currentUserId)
                
                if let rsvp = publicRSVP {
                    isAddedToSchedule = true
                    // Convert PublicEventRSVP to EventRSVP for UI compatibility
                    currentUserRSVP = EventRSVP(
                        eventId: event.id,
                        userId: rsvp.userId,
                        userDisplayName: rsvp.userDisplayName,
                        status: EventRSVP.RSVPStatus(rawValue: rsvp.status.rawValue) ?? .going
                    )
                }
                
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    self.error = "Failed to check schedule: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func addToSchedule() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        isAddingToSchedule = true
        error = nil
        
        Task {
            do {
                // Create a date from the event's SimpleDate
                let eventDate = dateFromSimpleDate(event.simpleDate)
                
                // RSVP to the public event directly
                try await userEventService.rsvpToPublicEvent(
                    publicEventId: event.id,
                    eventName: event.event_name,
                    eventDate: eventDate,
                    status: .going
                )
                
                await MainActor.run {
                    self.isAddedToSchedule = true
                    self.isAddingToSchedule = false
                    // Refresh data
                    checkIfAddedToSchedule()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to add to schedule: \(error.localizedDescription)"
                    showError = true
                    isAddingToSchedule = false
                }
            }
        }
    }
    
    private func removeFromSchedule() {
        isLoading = true
        
        Task {
            do {
                try await userEventService.cancelPublicEventRSVP(publicEventId: event.id)
                
                await MainActor.run {
                    self.isAddedToSchedule = false
                    self.currentUserRSVP = nil
                    self.attendees = []
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to remove from schedule: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func rsvpAsGoing() {
        isLoading = true
        
        Task {
            do {
                let eventDate = dateFromSimpleDate(event.simpleDate)
                try await userEventService.rsvpToPublicEvent(
                    publicEventId: event.id,
                    eventName: event.event_name,
                    eventDate: eventDate,
                    status: .going
                )
                
                // Refresh data
                await MainActor.run {
                    checkIfAddedToSchedule()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to RSVP: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
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
    
    // MARK: - Existing Staking Details Section
    private var existingStakingDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Staking Configuration")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                // Show invites (app users)
                ForEach(existingStakingInvites) { invite in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            StakerDisplayView(
                                invite: invite,
                                userService: userService
                            )
                            
                            HStack(spacing: 8) {
                                Text("\(invite.percentageBought, specifier: "%.1f")%")
                                    .font(.system(size: 14, design: .default))
                                    .foregroundColor(.gray)
                                Text("•")
                                    .foregroundColor(.gray)
                                Text(formatCurrency(invite.amountBought))
                                    .font(.system(size: 14, design: .default))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                        
                        // Status badge
                        HStack(spacing: 4) {
                            Image(systemName: invite.status.icon)
                                .font(.system(size: 12))
                            Text(invite.status.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                        }
                        .foregroundColor(stakingStatusColor(invite.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stakingStatusColor(invite.status).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                    )
                }
                
                // Show stakes (manual stakers)
                ForEach(existingStakes, id: \.id) { stake in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stake.manualStakerDisplayName ?? "Manual Staker")
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Text("\(stake.stakePercentage * 100, specifier: "%.1f")%")
                                    .font(.system(size: 14, design: .default))
                                    .foregroundColor(.gray)
                                Text("•")
                                    .foregroundColor(.gray)
                                Text("\(stake.markup, specifier: "%.2f")x markup")
                                    .font(.system(size: 14, design: .default))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                        
                        // Status badge
                        HStack(spacing: 4) {
                            Image(systemName: stakeStatusIcon(stake.status))
                                .font(.system(size: 12))
                            Text(stake.status.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                        }
                        .foregroundColor(stakeStatusColor(stake.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stakeStatusColor(stake.status).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
            
            // Summary info
            if let firstInvite = existingStakingInvites.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Global Settings")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                    HStack {
                        Text("Max Bullets: \(firstInvite.maxBullets)")
                            .font(.system(size: 13, design: .default))
                            .foregroundColor(.gray)
                        Text("•")
                            .foregroundColor(.gray)
                        Text("Markup: \(firstInvite.markup, specifier: "%.2f")x")
                            .font(.system(size: 13, design: .default))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 16)
    }
    
    private func stakingStatusColor(_ status: EventStakingInvite.InviteStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .accepted: return .green
        case .declined: return .red
        case .expired: return .gray
        }
    }
    
    private func stakeStatusColor(_ status: Stake.StakeStatus) -> Color {
        switch status {
        case .pendingAcceptance: return .orange
        case .active: return .green
        case .awaitingSettlement: return .blue
        case .awaitingConfirmation: return .yellow
        case .settled: return .gray
        case .declined: return .red
        case .cancelled: return .red
        }
    }
    
    private func stakeStatusIcon(_ status: Stake.StakeStatus) -> String {
        switch status {
        case .pendingAcceptance: return "clock"
        case .active: return "checkmark.circle"
        case .awaitingSettlement: return "hourglass"
        case .awaitingConfirmation: return "questionmark.circle"
        case .settled: return "checkmark.circle.fill"
        case .declined: return "xmark.circle"
        case .cancelled: return "xmark.circle"
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
    
    // MARK: - Fetch Existing Staking Invites
    private func fetchExistingStakingInvites() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let invites = try await eventStakingService.fetchStakingInvitesForEvent(eventId: event.id)
                // Only show invites created by the current user
                let userCreatedInvites = invites.filter { $0.stakedPlayerUserId == currentUserId }
                
                await MainActor.run {
                    self.existingStakingInvites = userCreatedInvites
                }
            } catch {
                print("Failed to fetch existing staking invites: \(error)")
            }
        }
    }
    
    // MARK: - Fetch Existing Stakes
    private func fetchExistingStakes() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let allStakes = try await stakeService.fetchStakes(forUser: currentUserId)
                print("EventDetailView: Total stakes fetched: \(allStakes.count)")
                print("EventDetailView: Looking for event name: '\(event.event_name)'")
                
                // Debug all stakes
                for stake in allStakes {
                    print("EventDetailView: Stake - sessionGameName: '\(stake.sessionGameName)', stakedPlayerUserId: '\(stake.stakedPlayerUserId)', isOffAppStake: '\(stake.isOffAppStake ?? false)', status: '\(stake.status)'")
                }
                
                // Filter for stakes related to this event
                let eventStakes = allStakes.filter { stake in
                    let nameMatch = stake.sessionGameName == event.event_name
                    let playerMatch = stake.stakedPlayerUserId == currentUserId
                    let manualMatch = stake.isOffAppStake == true
                    
                    print("EventDetailView: Stake filter - nameMatch: \(nameMatch), playerMatch: \(playerMatch), manualMatch: \(manualMatch)")
                    
                    return nameMatch && playerMatch && manualMatch
                }
                
                await MainActor.run {
                    self.existingStakes = eventStakes
                    print("EventDetailView: Found \(eventStakes.count) manual stakes for event '\(event.event_name)'")
                }
            } catch {
                print("Failed to fetch existing stakes: \(error)")
            }
        }
    }
}

// MARK: - Helper Views

private struct StakerDisplayView: View {
    let invite: EventStakingInvite
    @ObservedObject var userService: UserService
    
    var body: some View {
        Group {
            if invite.isManualStaker {
                manualStakerView
            } else {
                appUserStakerView
            }
        }
    }
    
    private var manualStakerView: some View {
        Text(invite.manualStakerDisplayName ?? "Manual Staker")
            .font(.system(size: 16, weight: .semibold, design: .default))
            .foregroundColor(.white)
    }
    
    private var appUserStakerView: some View {
        Group {
            if let stakerProfile = userService.loadedUsers[invite.stakerUserId] {
                HStack(spacing: 8) {
                    profileImageView(for: stakerProfile)
                    
                    Text(stakerProfile.displayName ?? stakerProfile.username)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                }
            } else {
                Text("Loading staker...")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .onAppear {
                        Task {
                            await userService.fetchUser(id: invite.stakerUserId)
                        }
                    }
            }
        }
    }
    
    private func profileImageView(for profile: UserProfile) -> some View {
        AsyncImage(url: URL(string: profile.avatarURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Text(String(profile.displayName?.first ?? profile.username.first ?? "?"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                )
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }
} 