import SwiftUI
import FirebaseAuth
import Kingfisher

// MARK: - User Event Detail View
struct UserEventDetailView: View {
    let event: UserEvent
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @StateObject private var groupService = GroupService()
    @Environment(\.presentationMode) var presentationMode
    
    @State private var currentUserRSVP: EventRSVP?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    @State private var showingShareSheet = false
    @State private var showingManageEvent = false
    @State private var attendees: [EventRSVP] = []
    @State private var isStartingBanking = false

    // Computed properties for display
    private var formattedStartDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy • h:mm a"
        return formatter.string(from: event.startDate)
    }
    
    private var formattedEndDate: String? {
        guard let endDate = event.endDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy • h:mm a"
        return formatter.string(from: endDate)
    }

    private var timeZoneDisplay: String {
        TimeZone(identifier: event.timezone)?.localizedName(for: .shortStandard, locale: .current) ?? event.timezone
    }


    
    private var isEventCreator: Bool {
        Auth.auth().currentUser?.uid == event.creatorId
    }
    
    private var shareURL: URL? {
        URL(string: "https://stackpoker.gg/events/\(event.id)")
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header Image / Event Type Icon (Placeholder)
                        eventTypeHeaderImage
                            .id("header") // ID for scrolling

                        // Main Content VStack
                        VStack(alignment: .leading, spacing: 24) {
                            titleAndHostSection
                            dateTimeLocationSection
                            
                            if let description = event.description, !description.isEmpty {
                                descriptionBox(description)
                            }
                            
                            participantsSection
                            actionsButtonsSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationBarHidden(true) // Fully custom navigation experience
        .overlay(customNavigationBar, alignment: .top)
        .alert("Error", isPresented: $showError, actions: { Button("OK") {} }, message: { Text(error ?? "An unknown error occurred.") })
        .onAppear(perform: fetchEventData)
        .sheet(isPresented: $showingManageEvent) {
            ManageEventView(event: event)
                .environmentObject(userEventService)
                .environmentObject(userService)
                .environmentObject(groupService)
        }
        .sheet(isPresented: $showingShareSheet) {
            EventInviteView(event: event)
                .environmentObject(userEventService)
                .environmentObject(userService)
                .environmentObject(groupService)
        }
    }

    // MARK: - UI Sections
    private var eventTypeHeaderImage: some View {
        ZStack(alignment: .bottomLeading) {
            // Event image or thematic background image
            if let imageURL = event.imageURL, let url = URL(string: imageURL) {
                KFImage(url)
                    .resizable()
                    .placeholder {
                        Image("stack_logo") // USE YOUR ACTUAL IMAGE NAME HERE
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 280)
                    .clipped()
                    .overlay(
                        // Darken the image for text readability & add a subtle vignette
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7), // Darker at the top
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.7)  // Darker at the bottom for text
                                    ]),
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
            } else {
                Image("stack_logo") // USE YOUR ACTUAL IMAGE NAME HERE
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 280)
                    .clipped()
                    .overlay(
                        // Darken the image for text readability & add a subtle vignette
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7), // Darker at the top
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.7)  // Darker at the bottom for text
                                    ]),
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
            }
            
            // Content overlaid on the image
            VStack(alignment: .leading, spacing: 8) {
                // Event Type Badge
                Text(event.eventType.displayName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundColor(.white) // Changed to white
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.3), lineWidth: 1))

                // Event Title
                Text(event.title)
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1) // Subtle shadow for readability
            }
            .padding(20)
        }
    }
    
    private var titleAndHostSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hosted by \(event.creatorName)")
                .font(.system(size: 16, weight: .medium, design: .default))
                .foregroundColor(.white)
            
            HStack {
                Label(event.isPublic ? "Public Event" : "Private Event", systemImage: event.isPublic ? "globe" : "lock.fill")
                    .font(.system(size: 14, design: .default))
                    .foregroundColor(.white)
                
                if event.isBanked {
                    Label("Banked", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 14, design: .default))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .padding(.leading, 8)
                }
                
                Spacer()
                Text(event.currentStatus.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(statusColor(event.currentStatus))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(event.currentStatus).opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 16)
    }
    
    private var dateTimeLocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(icon: "calendar", text: formattedStartDate)
            if let endDateStr = formattedEndDate {
                infoRow(icon: "calendar.badge.clock", text: endDateStr, subText: "Ends")
            }
            infoRow(icon: "globe.americas.fill", text: timeZoneDisplay, isSubtle: true)
            if let loc = event.location, !loc.isEmpty {
                infoRow(icon: "location.fill", text: loc)
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
            // Going attendees
            VStack(alignment: .leading, spacing: 12) {
                Text("Attendees (\(attendees.filter { $0.status == .going }.count)" + ((event.maxParticipants != nil) ? "/\(event.maxParticipants!)" : "") + ")")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(.white)

                let goingAttendees = attendees.filter { $0.status == .going }
                
                if goingAttendees.isEmpty {
                    Text("No confirmed attendees yet")
                        .font(.system(size: 16, design: .default))
                        .foregroundColor(.white)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(goingAttendees) { rsvp in
                                attendeeAvatar(rsvp: rsvp, statusColor: Color(red: 123/255, green: 255/255, blue: 99/255))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // Waitlist section
            let waitlistedAttendees = attendees.filter { $0.status == .waitlisted }.sorted { 
                ($0.waitlistPosition ?? 0) < ($1.waitlistPosition ?? 0) 
            }
            
            if !waitlistedAttendees.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Waitlist (\(waitlistedAttendees.count))")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(waitlistedAttendees) { rsvp in
                                VStack(spacing: 6) {
                                    attendeeAvatar(rsvp: rsvp, statusColor: Color(red: 64/255, green: 156/255, blue: 255/255))
                                    
                                    if let position = rsvp.waitlistPosition {
                                        Text("#\(position)")
                                            .font(.system(size: 10, weight: .bold, design: .default))
                                            .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }
    
    private func attendeeAvatar(rsvp: EventRSVP, statusColor: Color) -> some View {
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
                        .stroke(statusColor, lineWidth: 2)
                )
            
            Text(rsvp.userDisplayName)
                .font(.system(size: 12, design: .default))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
    
    private var actionsButtonsSection: some View {
        VStack(spacing: 16) {
            if isEventCreator {
                if event.isBanked && event.linkedGameId == nil && event.currentStatus != .completed {
                    Button(action: startBanking) {
                        HStack {
                            if isStartingBanking {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .frame(width: 20, height: 20)
                                    .padding(.horizontal, 10)
                            } else {
                                Label("Start Banking", systemImage: "gamecontroller.fill")
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
                    .disabled(isStartingBanking)
                }
                
                if event.currentStatus != .completed {
                    Button(action: { showingManageEvent = true }) {
                        Label("Manage Event", systemImage: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.9))
                            .cornerRadius(12)
                    }
                }
            } else {
                // RSVP Section for non-creators (only show if event is not completed)
                if event.currentStatus != .completed {
                    if let currentUserRSVP = currentUserRSVP {
                        VStack(spacing: 12) {
                            // Show current RSVP status
                            HStack {
                                Image(systemName: currentUserRSVP.status.icon)
                                    .foregroundColor(rsvpStatusColor(currentUserRSVP.status))
                                Text("You're \(currentUserRSVP.status.displayName.lowercased())")
                                    .font(.system(size: 16, weight: .medium, design: .default))
                                    .foregroundColor(.white)
                                
                                if currentUserRSVP.status == .waitlisted, let position = currentUserRSVP.waitlistPosition {
                                    Text("(#\(position) on waitlist)")
                                        .font(.system(size: 14, design: .default))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                            }
                            
                            // Cancel RSVP Button
                            Button(action: cancelRSVP) {
                                Label("Cancel RSVP", systemImage: "xmark.circle")
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
                        // RSVP Button for those who haven't RSVP'd
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
                        .disabled(isLoading)
                    }
                }
            }
            
            if event.currentStatus != .completed {
                Button(action: { showingShareSheet = true }) {
                    Label("Invite & Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
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
                // Add Edit button for creator, etc.
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
        .background(Color.clear)
    }
    
    // MARK: - Helper Views & Functions
    private func infoRow(icon: String, text: String, subText: String? = nil, isSubtle: Bool = false) -> some View {
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

    // MARK: - Data Fetching & Actions
    private func fetchEventData() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        Task {
            do {
                currentUserRSVP = try await userEventService.fetchUserRSVP(eventId: event.id, userId: currentUserId)
                attendees = try await userEventService.fetchEventRSVPs(eventId: event.id)
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load your RSVP: \(error.localizedDescription)"
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
                try await userEventService.rsvpToEvent(eventId: event.id, status: .going)
                
                // Refresh data
                await MainActor.run {
                    fetchEventData()
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
    
    private func cancelRSVP() {
        isLoading = true
        Task {
            do {
                try await userEventService.cancelRSVP(eventId: event.id)
                
                // Refresh data
                await MainActor.run {
                    fetchEventData()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to cancel RSVP: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func startBanking() {
        isStartingBanking = true
        error = nil
        
        Task {
            do {
                try await userEventService.startBankingForEvent(eventId: event.id)
                await MainActor.run {
                    isStartingBanking = false
                    // Refresh the event data to get the new linkedGameId
                    fetchEventData()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to start banking: \(error.localizedDescription)"
                    showError = true
                    isStartingBanking = false
                }
            }
        }
    }
} 