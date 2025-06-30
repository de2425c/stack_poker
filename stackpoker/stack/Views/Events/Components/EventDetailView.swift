import SwiftUI
import FirebaseAuth
import Kingfisher

// MARK: - Event Detail View
struct EventDetailView: View {
    let event: Event
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var sessionStore: SessionStore
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
    @State private var showingPendingStakersAlert = false
    @StateObject private var eventStakingService = EventStakingService()
    @StateObject private var stakeService = StakeService()


    // Computed properties for display
    private var formattedDate: String {
        event.simpleDate.displayMedium
    }
    
    private var hasPendingStakingInvites: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return existingStakingInvites.contains { invite in
            invite.status == .pending && invite.stakedPlayerUserId == currentUserId
        }
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
        
        // Create base date from SimpleDate
        let baseEventDate = calendar.date(from: DateComponents(
            year: event.simpleDate.year,
            month: event.simpleDate.month,
            day: event.simpleDate.day
        )) ?? Date()
        
        // Parse start time if available
        let eventStartTime = parseEventStartTime(baseDate: baseEventDate, timeString: event.time)
        
        // Parse late registration end time if available
        let lateRegEndTime = parseLateRegistrationEndTime(startTime: eventStartTime, lateRegString: event.lateRegistration)
        
        // Calculate ongoing period end (12 hours after late reg ends, or start time if no late reg)
        let ongoingEndTime = calendar.date(byAdding: .hour, value: 12, to: lateRegEndTime ?? eventStartTime) ?? eventStartTime
        
        // Determine status based on current time
        if now < eventStartTime {
            return .upcoming
        } else if let lateRegEnd = lateRegEndTime, now >= eventStartTime && now < lateRegEnd {
            return .lateRegistration
        } else if now < ongoingEndTime {
            return .active
        } else {
            return .completed
        }
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Event Banner Image at top
                    eventImage
                    
                    // Title section in a nice card below the image
                    titleCard
                    
                    // Main Content VStack
                    VStack(alignment: .leading, spacing: 24) {
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
        .alert("Error", isPresented: $showError, actions: { Button("OK") {} }, message: { Text(error ?? "An unknown error occurred.") })
        .alert("Pending Stakers", isPresented: $showingPendingStakersAlert) {
            Button("Continue") { 
                showingLiveSession = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have pending staking invites for this event. You can start the session now - when your stakers accept the invites, they'll automatically receive the session results.")
        }
        .onAppear {
            checkIfAddedToSchedule()
            fetchExistingStakingInvites()
            fetchExistingStakes()
        }
        .sheet(isPresented: $showingLiveSession) {
            EnhancedLiveSessionView(
                userId: Auth.auth().currentUser?.uid ?? "",
                sessionStore: sessionStore,
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
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status and Series badges
            HStack {
                Text(eventStatus.displayName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(statusColor(eventStatus).opacity(0.3))
                            .overlay(
                                Capsule()
                                    .stroke(statusColor(eventStatus), lineWidth: 1)
                            )
                    )
                
                Spacer()
                
                // Series name badge if available
                if let seriesName = event.series_name, !seriesName.isEmpty {
                    Text(seriesName)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                                )
                        )
                }
            }
            
            // Event Title
            Text(event.event_name)
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundColor(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            
            // Buy-in and Game Info
            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 255/255, green: 215/255, blue: 0/255))
                    Text(event.buyin_string)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundColor(.white)
                }
                
                if let game = event.game, !game.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "suit.spade.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Text(game)
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                // Nice card background that extends full width
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.04)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Top border line for separation
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                    Spacer()
                }
            }
        )
        .padding(.bottom, 16) // Add spacing underneath
    }
    
    private var eventImage: some View {
        Group {
            // Banner image at top
            if let imageUrl = event.imageUrl, !imageUrl.isEmpty {
                KFImage(URL(string: imageUrl))
                    .placeholder {
                        // Show placeholder while loading
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 200)
                            .overlay(
                                Text("Loading...")
                                    .foregroundColor(.white)
                            )
                    }
                    .onFailure { error in
                        print("DEBUG: Failed to load image: \(error)")
                    }
                    .onSuccess { result in
                        print("DEBUG: Successfully loaded image")
                    }
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color.black.opacity(0.8))
                    .clipped()
            } else {
                // Fallback to default logo if no imageUrl
                Image("stack_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.black.opacity(0.8))
                    .clipped()
                    .opacity(0.7)
            }
        }
    }
    

    
    private var eventDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tournament type header
            HStack {
                Label("Tournament Details", systemImage: "crown.fill")
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.bottom, 8)
            
            infoRow(icon: "calendar", text: formattedDate)
            infoRow(icon: "clock.fill", text: formattedTime)
            
            // New fields from new_event collection - removed duplicate game since it's in header
            
            if let chipsFormatted = event.chipsFormatted, !chipsFormatted.isEmpty {
                infoRow(icon: "cpu", text: "Starting chips: \(chipsFormatted)")
            }
            
            if let guaranteeFormatted = event.guaranteeFormatted, !guaranteeFormatted.isEmpty {
                infoRow(icon: "dollarsign.square.fill", text: "Guarantee: \(guaranteeFormatted)")
            }
            
            if let levelsFormatted = event.levelsFormatted, !levelsFormatted.isEmpty {
                infoRow(icon: "clock.arrow.circlepath", text: "Level length: \(levelsFormatted) min")
            }
            
            if let lateReg = event.lateRegistration, !lateReg.isEmpty {
                infoRow(icon: "clock.badge.exclamationmark", text: "Late registration: \(lateReg)")
            }
            
            // PDF Link button
            if let pdfLink = event.pdfLink, !pdfLink.isEmpty {
                
                Button(action: {
                    if let url = URL(string: pdfLink) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 24, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Schedule PDF")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.white)
                            Text("Open tournament structure")
                                .font(.system(size: 13, design: .default))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                }
            }
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
                if hasPendingStakingInvites {
                    showingPendingStakersAlert = true
                } else {
                    showingLiveSession = true
                }
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
        case .lateRegistration: return Color(red: 255/255, green: 149/255, blue: 0/255) // Orange for late registration
        case .active: return Color(red: 255/255, green: 59/255, blue: 48/255) // Red for active/ongoing
        case .completed: return .blue
        case .cancelled: return .gray
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
                            
                            if invite.hasSessionResults {
                                // Show session results if available
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text("Buy-in: \(formatCurrency(invite.sessionBuyIn ?? 0))")
                                            .font(.system(size: 14, design: .default))
                                            .foregroundColor(.gray)
                                        Text("•")
                                            .foregroundColor(.gray)
                                        Text("Cashout: \(formatCurrency(invite.sessionCashout ?? 0))")
                                            .font(.system(size: 14, design: .default))
                                            .foregroundColor(.gray)
                                    }
                                    Text("Profit: \(formatCurrency(invite.sessionProfit ?? 0))")
                                        .font(.system(size: 14, weight: .semibold, design: .default))
                                        .foregroundColor(invite.sessionProfit ?? 0 >= 0 ? .green : .red)
                                }
                            } else {
                                // Show stake details if no session results
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
                        }
                        
                        Spacer()
                        
                        // Status badge - use updated status for session complete invites
                        HStack(spacing: 4) {
                            Image(systemName: invite.hasSessionResults && invite.status == .pending ? "checkmark.circle.fill" : invite.status.icon)
                                .font(.system(size: 12))
                            Text(invite.hasSessionResults && invite.status == .pending ? "Session Complete" : invite.status.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                        }
                        .foregroundColor(invite.hasSessionResults && invite.status == .pending ? .blue : stakingStatusColor(invite.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((invite.hasSessionResults && invite.status == .pending ? .blue : stakingStatusColor(invite.status)).opacity(0.15))
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

    // MARK: - Time Parsing Helper Functions
    
    private func parseEventStartTime(baseDate: Date, timeString: String?) -> Date {
        guard let timeString = timeString, !timeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Default to 6 PM if no time specified
            let calendar = Calendar.current
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: baseDate) ?? baseDate
        }
        
        let calendar = Calendar.current
        let cleanTimeString = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse time in various formats
        let timeFormats = ["h:mm a", "HH:mm", "h a", "ha", "h:mma"]
        let formatter = DateFormatter()
        
        for format in timeFormats {
            formatter.dateFormat = format
            if let time = formatter.date(from: cleanTimeString) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                if let hour = timeComponents.hour, let minute = timeComponents.minute {
                    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? baseDate
                }
            }
        }
        
        // If parsing fails, default to 6 PM
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: baseDate) ?? baseDate
    }
    
    private func parseLateRegistrationEndTime(startTime: Date, lateRegString: String?) -> Date? {
        guard let lateRegString = lateRegString, !lateRegString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        let calendar = Calendar.current
        let cleanString = lateRegString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract level information (e.g., "End of Level 8", "Level 10", "8 levels")
        if let levelMatch = extractLevelNumber(from: cleanString) {
            // Assume each level is the levelLength from the event (default 20 minutes if not specified)
            let levelLengthMinutes = event.levelLength ?? 20
            let totalMinutes = levelMatch * levelLengthMinutes
            return calendar.date(byAdding: .minute, value: totalMinutes, to: startTime)
        }
        
        // Try to extract time duration (e.g., "2 hours", "90 minutes", "1.5 hours")
        if let durationMinutes = extractDurationMinutes(from: cleanString) {
            return calendar.date(byAdding: .minute, value: durationMinutes, to: startTime)
        }
        
        // Try to extract specific time (e.g., "9:30 PM", "21:30")
        if let specificTime = parseSpecificTime(from: cleanString, baseDate: startTime) {
            return specificTime
        }
        
        // Default fallback: 2 hours after start if we can't parse
        return calendar.date(byAdding: .hour, value: 2, to: startTime)
    }
    
    private func extractLevelNumber(from string: String) -> Int? {
        // Patterns to match: "end of level 8", "level 10", "8 levels", etc.
        let patterns = [
            "(?:end of )?level (\\d+)",
            "(\\d+) levels?",
            "through level (\\d+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: string.utf16.count)
                if let match = regex.firstMatch(in: string, options: [], range: range) {
                    let numberRange = match.range(at: 1)
                    if let range = Range(numberRange, in: string) {
                        if let number = Int(String(string[range])) {
                            return number
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func extractDurationMinutes(from string: String) -> Int? {
        // Patterns for duration: "2 hours", "90 minutes", "1.5 hours", "2h 30m"
        let patterns = [
            "(\\d+(?:\\.\\d+)?)\\s*hours?",
            "(\\d+)\\s*minutes?",
            "(\\d+)h\\s*(\\d+)m",
            "(\\d+)\\s*hrs?",
            "(\\d+)\\s*mins?"
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: string.utf16.count)
                if let match = regex.firstMatch(in: string, options: [], range: range) {
                    switch index {
                    case 0, 3: // hours patterns
                        let hoursRange = match.range(at: 1)
                        if let range = Range(hoursRange, in: string),
                           let hours = Double(String(string[range])) {
                            return Int(hours * 60)
                        }
                    case 1, 4: // minutes patterns  
                        let minutesRange = match.range(at: 1)
                        if let range = Range(minutesRange, in: string),
                           let minutes = Int(String(string[range])) {
                            return minutes
                        }
                    case 2: // "2h 30m" pattern
                        let hoursRange = match.range(at: 1)
                        let minutesRange = match.range(at: 2)
                        if let hoursStringRange = Range(hoursRange, in: string),
                           let minutesStringRange = Range(minutesRange, in: string),
                           let hours = Int(String(string[hoursStringRange])),
                           let minutes = Int(String(string[minutesStringRange])) {
                            return hours * 60 + minutes
                        }
                    default:
                        break
                    }
                }
            }
        }
        return nil
    }
    
    private func parseSpecificTime(from string: String, baseDate: Date) -> Date? {
        let calendar = Calendar.current
        let timeFormats = ["h:mm a", "HH:mm", "h a", "ha"]
        let formatter = DateFormatter()
        
        for format in timeFormats {
            formatter.dateFormat = format
            // Try to find time pattern in the string
            if let regex = try? NSRegularExpression(pattern: "\\b\\d{1,2}:?\\d{0,2}\\s*[ap]?m?\\b", options: .caseInsensitive) {
                let range = NSRange(location: 0, length: string.utf16.count)
                if let match = regex.firstMatch(in: string, options: [], range: range) {
                    if let timeRange = Range(match.range, in: string) {
                        let timeString = String(string[timeRange])
                        if let time = formatter.date(from: timeString) {
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                            if let hour = timeComponents.hour, let minute = timeComponents.minute {
                                let baseDateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
                                var newComponents = DateComponents()
                                newComponents.year = baseDateComponents.year
                                newComponents.month = baseDateComponents.month
                                newComponents.day = baseDateComponents.day
                                newComponents.hour = hour
                                newComponents.minute = minute
                                return calendar.date(from: newComponents)
                            }
                        }
                    }
                }
            }
        }
        return nil
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
