import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ManageEventView: View {
    let event: UserEvent
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var groupService: GroupService
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: ManageTab = .attendees
    @State private var eventRSVPs: [EventRSVP] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    @State private var showingInviteSheet = false
    @State private var showingGroupInviteSheet = false
    @State private var showDeleteAlert = false
    
    enum ManageTab: String, CaseIterable {
        case attendees = "Attendees"
        case waitlist = "Waitlist"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .attendees: return "person.2.fill"
            case .waitlist: return "clock.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    // Computed properties for different RSVP statuses
    private var goingAttendees: [EventRSVP] {
        eventRSVPs.filter { $0.status == .going }
    }
    
    private var waitlistedAttendees: [EventRSVP] {
        eventRSVPs.filter { $0.status == .waitlisted }.sorted { 
            ($0.waitlistPosition ?? 0) < ($1.waitlistPosition ?? 0) 
        }
    }
    
    private var maybeAttendees: [EventRSVP] {
        eventRSVPs.filter { $0.status == .maybe }
    }
    
    private var declinedAttendees: [EventRSVP] {
        eventRSVPs.filter { $0.status == .declined }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Event Header
                    
                    // Tab Selector
                    customTabBar
                    
                    // Tab Content
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading...")
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                        Spacer()
                    } else {
                        switch selectedTab {
                        case .attendees:
                            attendeesView
                        case .waitlist:
                            waitlistView
                        case .settings:
                            settingsView
                        }
                    }
                }
            }
            .navigationTitle("Manage Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .onAppear(perform: fetchEventRSVPs)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(error ?? "An unknown error occurred")
            }
            .alert("Delete Event?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { deleteEvent() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showingInviteSheet) {
                InviteUsersView(event: event)
                    .environmentObject(userEventService)
                    .environmentObject(userService)
            }
            .sheet(isPresented: $showingGroupInviteSheet) {
                InviteGroupView(event: event)
                    .environmentObject(userEventService)
                    .environmentObject(groupService)
            }
        }
    }
    
    // MARK: - Event Header
    
    // MARK: - Custom Tab Bar
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ManageTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(selectedTab == tab ? Color(red: 64/255, green: 156/255, blue: 255/255) : Color.clear)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
                    )
                }
            }
        }
        .background(Color.white.opacity(0.05))
    }
    
    // MARK: - Attendees View
    private var attendeesView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !goingAttendees.isEmpty {
                    attendeeSection(title: "Going (\(goingAttendees.count))", attendees: goingAttendees, color: Color(red: 64/255, green: 156/255, blue: 255/255))
                }
                
                if !maybeAttendees.isEmpty {
                    attendeeSection(title: "Maybe (\(maybeAttendees.count))", attendees: maybeAttendees, color: .orange)
                }
                
                if !declinedAttendees.isEmpty {
                    attendeeSection(title: "Declined (\(declinedAttendees.count))", attendees: declinedAttendees, color: .red)
                }
                
                if goingAttendees.isEmpty && maybeAttendees.isEmpty && declinedAttendees.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No RSVPs Yet")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("Invite people to see their responses here")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Waitlist View
    private var waitlistView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !waitlistedAttendees.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Waitlist Order")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        ForEach(Array(waitlistedAttendees.enumerated()), id: \.element.id) { index, rsvp in
                            HStack(spacing: 12) {
                                Text("#\(index + 1)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.orange)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rsvp.userDisplayName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("Added \(formatRelativeDate(rsvp.rsvpDate))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    // TODO: Move to going list if space available
                                }) {
                                    Text("Promote")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No Waitlist")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("People will appear here when the event is full")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Settings View
    private var settingsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Delete Event (only creator)
                if Auth.auth().currentUser?.uid == event.creatorId {
                    Button(role: .destructive, action: { showDeleteAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Event")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 30)
        }
    }
    
    // MARK: - Helper Views
    private func attendeeSection(title: String, attendees: [EventRSVP], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            ForEach(attendees) { rsvp in
                HStack(spacing: 12) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rsvp.userDisplayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("RSVP'd \(formatRelativeDate(rsvp.rsvpDate))")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if let notes = rsvp.notes, !notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Helper Functions
    private func fetchEventRSVPs() {
        isLoading = true
        Task {
            do {
                let rsvps = try await userEventService.fetchEventRSVPs(eventId: event.id)
                await MainActor.run {
                    self.eventRSVPs = rsvps
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // Delete event API
    private func deleteEvent() {
        Task {
            do {
                try await userEventService.deleteEvent(eventId: event.id)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
}

// MARK: - Invite Users View
struct InviteUsersView: View {
    let event: UserEvent
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedUserIds: Set<String> = []
    @State private var selectedUsernames: [String] = []
    @State private var showingUserSearch = false
    @State private var isInviting = false
    @State private var error: String?
    @State private var showError = false
    
    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Selected Users List
                    if !selectedUsernames.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Selected Users (\(selectedUsernames.count))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            ForEach(Array(selectedUsernames.enumerated()), id: \.offset) { index, username in
                                HStack {
                                    Text(username)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button(action: {
                                        let idToRemove = Array(selectedUserIds)[index]
                                        selectedUserIds.remove(idToRemove)
                                        selectedUsernames.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { showingUserSearch = true }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Search & Add Users")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color(red: 64/255, green: 156/255, blue: 255/255), Color(red: 100/255, green: 180/255, blue: 255/255)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)
                        )
                        .cornerRadius(14)
                    }
                    .padding(.bottom, 20)
                    
                    Button(action: sendInvites) {
                        if isInviting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Send Invites (\(selectedUserIds.count))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .disabled(selectedUserIds.isEmpty || isInviting)
                    .background(selectedUserIds.isEmpty ? Color.white.opacity(0.2) : Color(red: 64/255, green: 156/255, blue: 255/255))
                    .cornerRadius(14)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Invite Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingUserSearch) {
                UserSearchView(currentUserId: currentUserId, userService: userService) { userId in
                    addUser(userId)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(error ?? "Unknown error")
        }
    }
    
    // Add a user to local selections and fetch a friendly name
    private func addUser(_ id: String) {
        guard !selectedUserIds.contains(id) else { return }
        selectedUserIds.insert(id)

        // Optimistically show UID while we fetch
        selectedUsernames.append(id)

        Task {
            if let snap = try? await Firestore.firestore().collection("users").document(id).getDocument(),
               let data = snap.data() {
                let name = (data["displayName"] as? String) ?? (data["username"] as? String) ?? id
                await MainActor.run {
                    if let idx = selectedUsernames.firstIndex(of: id) { selectedUsernames[idx] = name }
                }
            }
        }
    }
    
    private func sendInvites() {
        guard !isInviting, !selectedUserIds.isEmpty else { return }
        isInviting = true
        Task {
            do {
                try await userEventService.inviteUsersToEvent(eventId: event.id, userIds: Array(selectedUserIds))
                await MainActor.run {
                    isInviting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? UserEventServiceError)?.message ?? error.localizedDescription
                    self.isInviting = false
                    self.showError = true
                }
            }
        }
    }
}

// MARK: - Invite Group View
struct InviteGroupView: View {
    let event: UserEvent
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var groupService: GroupService
    @Environment(\.dismiss) var dismiss
    
    @State private var isLoading = true
    @State private var error: String?
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(groupService.userGroups) { group in
                                Button(action: { inviteGroup(group.id) }) {
                                    HStack {
                                        Text(group.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(10)
                                }
                            }
                            if groupService.userGroups.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "person.3")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                    Text("You don't have any groups yet")
                                        .foregroundColor(.gray)
                                }
                                .padding(.top, 60)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Invite Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .onAppear {
                loadGroups()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(error ?? "Unknown error")
        }
    }
    
    private func loadGroups() {
        Task {
            do {
                try await groupService.fetchUserGroups()
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    self.showError = true
                }
            }
        }
    }
    
    private func inviteGroup(_ groupId: String) {
        Task {
            do {
                try await userEventService.inviteGroupToEvent(eventId: event.id, groupId: groupId)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
}

#Preview {
    ManageEventView(event: UserEvent(
        id: "preview",
        title: "Friday Night Poker",
        description: "Weekly poker game",
        eventType: .homeGame,
        creatorId: "preview",
        creatorName: "John Doe",
        startDate: Date(),
        endDate: nil,
        timezone: "UTC",
        location: "My place",
        maxParticipants: 8,
        waitlistEnabled: true,
        groupId: nil,
        isPublic: false,
        rsvpDeadline: nil,
        reminderSettings: nil,
        isBanked: false
    ))
    .environmentObject(UserEventService())
    .environmentObject(UserService())
    .environmentObject(GroupService())
} 