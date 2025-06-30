import SwiftUI
import FirebaseAuth
import PhotosUI
import FirebaseStorage
import Kingfisher

struct GroupsView: View {
    @StateObject private var groupService = GroupService()
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityManager
    @State private var showingCreateGroup = false
    @State private var showingInvites = false
    @State private var selectedGroupForChat: UserGroup?
    @State private var groupActionSheet: UserGroup?
    @State private var error: String?
    @State private var showError = false
    @State private var isRefreshing = false
    
    // Parameters to track whether bars are showing (matching FeedView)
    let hasStandaloneGameBar: Bool
    let hasInviteBar: Bool
    let hasLiveSessionBar: Bool
    
    // Add computed property for dynamic top padding based on bar visibility
    private var dynamicTopPadding: CGFloat {
        // When any top bars are visible, use minimal padding since they provide spacing
        if hasLiveSessionBar || hasStandaloneGameBar || hasInviteBar {
            return 8 // Minimal padding when bars are present
        } else {
            // When no bars, need padding to account for safe area
            return 8 // Consistent with FeedView approach
        }
    }
    
    // Add initializer to accept bar visibility parameters
    init(hasStandaloneGameBar: Bool = false, hasInviteBar: Bool = false, hasLiveSessionBar: Bool = false) {
        self.hasStandaloneGameBar = hasStandaloneGameBar
        self.hasInviteBar = hasInviteBar
        self.hasLiveSessionBar = hasLiveSessionBar
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                // Header with proper safe area handling
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Groups")
                            .font(.system(size: 22, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Invites button with notification badge
                        Button(action: { showingInvites = true }) {
                            ZStack {
                                Image(systemName: "envelope")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                
                                if !groupService.pendingInvites.isEmpty {
                                    Circle()
                                        .fill(Color(red: 64/255, green: 156/255, blue: 255/255))
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .padding(.trailing, 12)
                        
                        // Create group button
                        Button(action: { showingCreateGroup = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, dynamicTopPadding)
                    .padding(.bottom, 16)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            // Refresh controls
                            RefreshControls(isRefreshing: $isRefreshing) {
                                Task {
                                    await refreshGroups()
                                    isRefreshing = false
                                }
                            }
                            .padding(.bottom, 8)

                            if groupService.isLoading && groupService.userGroups.isEmpty {
                                VStack {
                                    Spacer().frame(height: 180)
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.8)))
                                        .scaleEffect(1.5)
                                }
                            } else if groupService.userGroups.isEmpty {
                                EmptyGroupsView(onCreateTapped: { showingCreateGroup = true })
                            } else {
                                VStack(spacing: 20) {
                                    ForEach(groupService.userGroups) { group in
                                        GroupCard(
                                            group: group,
                                            onTap: {
                                                selectedGroupForChat = group
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 100)
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        // MARK: Navigation destinations
        .background(
            Group {
                // Group Chat navigation
                NavigationLink(destination:
                                selectedGroupForChat.map { grp in
                    GroupChatView(group: grp)
                        .environmentObject(userService)
                        .environmentObject(sessionStore)
                        .environmentObject(postService)
                        .environmentObject(tabBarVisibility)
                        .navigationBarHidden(true)
                }, isActive: Binding(
                    get: { selectedGroupForChat != nil },
                    set: { if !$0 { selectedGroupForChat = nil } }
                )) { EmptyView() }
            }
        )
        .alert(isPresented: $showError) {
            Alert(title: Text("Error"), message: Text(error ?? "An unknown error occurred"), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView { success in
                if success { Task { await refreshGroups() } }
            }
        }
        .sheet(isPresented: $showingInvites) {
            GroupInvitesView { Task { await refreshGroups() } }
        }
        // Confirmation Dialog
        .confirmationDialog("Group Options", isPresented: .init(get: { groupActionSheet != nil }, set: { if !$0 { groupActionSheet = nil } }), titleVisibility: .visible) {
            if let grp = groupActionSheet {
                if grp.ownerId != Auth.auth().currentUser?.uid {
                    Button("Leave Group", role: .destructive) { Task { await leaveGroup(group: grp) } }
                }
                Button("Cancel", role: .cancel) { groupActionSheet = nil }
            }
        }
        .onAppear {
            setupNotificationObserver()
            setupMessageUpdateObserver()
            Task { await refreshGroups() }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
        .navigationBarHidden(true)
    }
    
    // Set up notification observer for group data changes
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GroupDataChanged"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await refreshGroups()
            }
        }
    }
    
    // Set up observer for message updates to refresh group order
    private func setupMessageUpdateObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GroupMessageSent"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await refreshGroups()
            }
        }
    }
    
    private func refreshGroups() async {
        do {
            try await groupService.fetchUserGroups()
            try await groupService.fetchPendingInvites()
        } catch {
            self.error = error.localizedDescription
            self.showError = true
        }
    }
    
    private func leaveGroup(group: UserGroup) async {
        do {
            try await groupService.leaveGroup(groupId: group.id)
        } catch {
            self.error = error.localizedDescription
            self.showError = true
        }
    }
}

// Update the EmptyGroupsView to be more minimalistic
struct EmptyGroupsView: View {
    let onCreateTapped: () -> Void
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)
            
            // Modern flat icon
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.8))
                .padding(.bottom, 16)
            
            Text("No Conversations Yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text("Create poker groups to host home games,\nshare photos, create events, and compete\n with your friends")
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            
            Button(action: onCreateTapped) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                    
                    Text("New Group")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                    Color(red: 100/255, green: 180/255, blue: 255/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
    }
}

// Banner-style Group Card
struct GroupCard: View {
    let group: UserGroup
    let onTap: () -> Void
    
    @State private var cardOffset: CGFloat = 30
    @State private var cardOpacity: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Banner Image
            ZStack(alignment: .bottomLeading) {
                // Image with a fallback gradient
                if let avatarURL = group.avatarURL, let url = URL(string: avatarURL) {
                    KFImage(url)
                        .placeholder {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 40/255, green: 40/255, blue: 50/255),
                                            Color(red: 25/255, green: 25/255, blue: 35/255)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        .frame(height: 110)
                        .clipped()
                        } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5),
                                    Color(red: 40/255, green: 40/255, blue: 50/255)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 110)
                }
                
                // Dark overlay for text readability
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
                
                // Group Name and member count on top of the banner
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.custom("PlusJakartaSans-Bold", size: 22))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                        Text("\(group.memberCount) member\(group.memberCount != 1 ? "s" : "")")
                    }
                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .padding(16)
            }
            
            // Bottom section for last message details
            VStack(alignment: .leading, spacing: 8) {
                if let lastMessage = group.lastMessage, let lastMessageTime = group.lastMessageTime {
                    HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                            Text(group.lastMessageSenderName ?? "Recent message:")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                            
                            Text(lastMessage)
                                .font(.custom("PlusJakartaSans-Medium", size: 15))
                        .foregroundColor(.white)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    
                    Spacer()
                    
                        Text(timeAgoString(from: lastMessageTime))
                            .font(.custom("PlusJakartaSans-Medium", size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 4)
                    }
                } else {
                    Text("No messages yet. Be the first to chat!")
                        .font(.custom("PlusJakartaSans-Medium", size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()
                }
            }
            .padding(16)
            .frame(minHeight: 70) // Ensure a consistent height for the bottom part
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .background(
            ZStack {
                // Use a slightly darker base for the card
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 28/255, green: 30/255, blue: 40/255))
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 8)
        .offset(y: cardOffset)
        .opacity(cardOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardOffset = 0
                cardOpacity = 1
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Custom button style for subtle scaling on press
struct ScaleButtonStyles: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Matching the refresh control from FeedView
struct RefreshControls: View {
    @Binding var isRefreshing: Bool
    let action: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var refreshScale: CGFloat = 0.8
    @State private var rotation: Angle = .degrees(0)
    
    var body: some View {
        GeometryReader { geo in
            if offset > 0 {
                VStack(spacing: 5) {
                    Spacer()
                    
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                            .scaleEffect(1.2)
                    } else {
                        Group {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .rotationEffect(rotation)
                                .scaleEffect(refreshScale)
                        }
                        .font(.system(size: 18, weight: .semibold))
                    }
                    
                    Group {
                        Text(isRefreshing ? "Refreshing..." : "Pull to refresh")
                            .foregroundColor(.gray)
                    }
                    .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                }
                .frame(width: geo.size.width)
                .offset(y: -offset)
            }
        }
        .coordinateSpace(name: "pullToRefresh")
        .onPreferenceChange(OffsetPreferenceKey.self) { value in
            offset = value
            
            // Update scale and rotation based on pull distance
            refreshScale = min(1.0, 0.8 + (offset / 120) * 0.2)
            
            // Start rotation animation when pulled far enough
            if offset > 80 && !isRefreshing {
                withAnimation(.linear(duration: 0.2)) {
                    rotation = .degrees(180)
                }
            } else if offset < 20 && !isRefreshing {
                withAnimation(.linear(duration: 0.2)) {
                    rotation = .degrees(0)
                }
            }
            
            // Trigger refresh when pulled past threshold and released
            if offset > 80 && !isRefreshing {
                isRefreshing = true
                action()
            }
        }
    }
}

struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CreateGroupView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var groupService = GroupService()
    @State private var groupName = ""
    @State private var showingInviteFlow = false
    @State private var createdGroup: UserGroup?
    @State private var isCreating = false
    @State private var error: String?
    @State private var showError = false
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem?
    
    // Animation states
    @State private var nameFieldOpacity = 0.0
    @State private var imageOpacity = 0.0
    @State private var buttonOpacity = 0.0
    
    let onComplete: (Bool) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Group image selection - centered and first
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 40/255, green: 40/255, blue: 50/255))
                                    .frame(width: 100, height: 100)
                                
                                if let selectedImage = selectedImage {
                                    Image(uiImage: selectedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 40, design: .default))
                                        .foregroundColor(.gray)
                                }
                                
                                // Camera icon for uploading if owner
                                PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14, design: .default))
                                            .foregroundColor(.white)
                                    }
                                }
                                .onChange(of: imagePickerItem) { newItem in
                                    loadTransferableImage(from: newItem)
                                }
                                .position(x: 75, y: 75)
                            }
                            
                            Text("Group Photo (Optional)")
                                .font(.system(size: 14, design: .default))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.bottom, 16)
                        .opacity(imageOpacity)
                        
                        // Form fields
                        VStack(spacing: 20) {
                            GlassyInputField(icon: "person.2.fill", title: "GROUP NAME") {
                                TextField("Enter group name", text: $groupName)
                                    .font(.system(size: 17, design: .default))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 24)
                            .opacity(nameFieldOpacity)
                            
                            // Create button with gradient and shadow
                            Button(action: createGroup) {
                                HStack {
                                    if isCreating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .frame(width: 20, height: 20)
                                            .padding(.horizontal, 10)
                                    } else {
                                        Text("Create Group")
                                            .font(.system(size: 17, weight: .semibold, design: .default))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(height: 54)
                                .background(
                                    groupName.isEmpty || isCreating
                                        ? LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5),
                                                Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.5)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 64/255, green: 156/255, blue: 255/255),
                                                Color(red: 100/255, green: 180/255, blue: 255/255)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                                .cornerRadius(16)
                                .shadow(
                                    color: groupName.isEmpty ? Color.clear : Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.4),
                                    radius: 8, x: 0, y: 4
                                )
                            }
                            .disabled(groupName.isEmpty || isCreating)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .opacity(buttonOpacity)
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 40)
                    }
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .alert(isPresented: $showError, content: {
                        Alert(
                            title: Text("Error"),
                            message: Text(error ?? "An unknown error occurred"),
                            dismissButton: .default(Text("OK"))
                        )
                    })
                }
                .navigationBarItems(
                    leading: Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color(red: 30/255, green: 33/255, blue: 36/255)))
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingInviteFlow) {
                    if let group = createdGroup {
                        GroupInviteFlowView(group: group) {
                            // Completed invite flow
                            showingInviteFlow = false
                            onComplete(true)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .onAppear {
                    // Animate elements sequentially
                    withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                        imageOpacity = 1.0
                    }
                    
                    withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                        nameFieldOpacity = 1.0
                    }
                    
                    withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                        buttonOpacity = 1.0
                    }
                }
            }
        }
    }
    
    private func loadTransferableImage(from imageSelection: PhotosPickerItem?) {
        guard let imageSelection else { return }
        
        Task {
            do {
                if let data = try await imageSelection.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            } catch {

            }
        }
    }
    
    private func createGroup() {
        guard !groupName.isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                let group: UserGroup
                
                if let image = selectedImage {
                    group = try await groupService.createGroup(
                        name: groupName,
                        description: nil,
                        image: image
                    )
                } else {
                    group = try await groupService.createGroup(
                        name: groupName,
                        description: nil
                    )
                }
                
                await MainActor.run {
                    isCreating = false
                    createdGroup = group
                    showingInviteFlow = true
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isCreating = false
                }
            }
        }
    }
}

struct GroupInvitesView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var groupService = GroupService()
    @State private var isLoading = true
    @State private var error: String?
    @State private var showError = false
    @State private var animateList = false
    
    let onComplete: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Modern header with title and close button
                    HStack {
                        Group {
                            Text("Group Invites")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .font(.system(size: 22, weight: .bold))
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                            .scaleEffect(1.5)
                        Spacer()
                    } else if groupService.pendingInvites.isEmpty {
                        // Empty state with animation
                        VStack(spacing: 20) {
                            Spacer()
                                .frame(height: 40)
                            
                            Image(systemName: "bell.badge.fill") // Placeholder replacement
                                .font(.system(size: 50, design: .default))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .frame(width: 200, height: 200)

                            Text("No Pending Invites")
                                .font(.system(size: 22, weight: .bold, design: .default))
                                .foregroundColor(.white)
                            
                            Text("When someone invites you to join a group,\nyou'll see it here")
                                .font(.system(size: 16, design: .default))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            
                            Spacer()
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(Array(groupService.pendingInvites.enumerated()), id: \.element.id) { index, invite in
                                    InviteCard(invite: invite, onAccept: {
                                        acceptInvite(invite: invite)
                                    }, onDecline: {
                                        declineInvite(invite: invite)
                                    })
                                    .offset(y: animateList ? 0 : 50)
                                    .opacity(animateList ? 1 : 0)
                                    .animation(
                                        .spring(response: 0.4, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.1),
                                        value: animateList
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .alert(isPresented: $showError, content: {
                    Alert(
                        title: Text("Error"),
                        message: Text(error ?? "An unknown error occurred"),
                        dismissButton: .default(Text("OK"))
                    )
                })
            }
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color(red: 30/255, green: 33/255, blue: 36/255)))
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await loadInvites()
                    withAnimation {
                        animateList = true
                    }
                }
            }
        }
    }
    
    private func loadInvites() async {
        isLoading = true
        
        do {
            try await groupService.fetchPendingInvites()
            
            await MainActor.run {
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.showError = true
                isLoading = false
            }
        }
    }
    
    private func acceptInvite(invite: GroupInvite) {
        Task {
            do {
                try await groupService.acceptInvite(inviteId: invite.id)
                onComplete()
                
                // If there are no more invites, dismiss the sheet
                if groupService.pendingInvites.count <= 1 {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                self.error = error.localizedDescription
                self.showError = true
            }
        }
    }
    
    private func declineInvite(invite: GroupInvite) {
        Task {
            do {
                try await groupService.declineInvite(inviteId: invite.id)
                
                // If there are no more invites, dismiss the sheet
                if groupService.pendingInvites.count <= 1 {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                self.error = error.localizedDescription
                self.showError = true
            }
        }
    }
}

// Beautiful invitation card
struct InviteCard: View {
    let invite: GroupInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Invitation avatar/icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 40/255, green: 60/255, blue: 40/255),
                                    Color(red: 30/255, green: 45/255, blue: 35/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 22, design: .default))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(invite.groupName)
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Text("Invited by \(invite.inviterName)")
                        .font(.system(size: 14, design: .default))
                        .foregroundColor(.gray)
                    
                    // Invitation time
                    Text(timeAgoString(from: invite.createdAt))
                        .font(.system(size: 13, design: .default))
                        .foregroundColor(Color.gray.opacity(0.7))
                        .padding(.top, 2)
                }
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Accept button
                Button(action: onAccept) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                        
                        Text("Accept")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                    )
                }
                .buttonStyle(ScaleButtonStyles())
                
                // Decline button
                Button(action: onDecline) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                        
                        Text("Decline")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 45/255, green: 45/255, blue: 50/255))
                    )
                }
                .buttonStyle(ScaleButtonStyles())
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 30/255, green: 32/255, blue: 36/255),
                                Color(red: 25/255, green: 27/255, blue: 32/255)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.1),
                            Color.clear,
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct GroupDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var groupService = GroupService()
    @Binding var group: UserGroup
    @State private var selectedUser: UserListItem?
    @State private var searchText = ""
    @State private var isInviting = false
    @State private var error: String?
    @State private var showError = false
    @State private var inviteSuccess = false
    @State private var isDropdownVisible = false
    @State private var isLoadingUsers = false
    @State private var isLoadingMembers = false
    @State private var selectedTab = 0 // 0 = Info, 1 = Members, 2 = Invites
    @State private var showDeleteConfirmation = false
    @State private var isDeletingGroup = false
    
    // For image upload
    @State private var selectedImage: UIImage?
    @State private var isShowingImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    
    // Animation states
    @State private var headerOpacity = 0.0
    @State private var avatarScale = 0.8
    @State private var tabsOffset: CGFloat = 30
    @State private var avatarRefreshId = UUID()
    
    // If the current user is the owner
    var isOwner: Bool {
        return group.ownerId == Auth.auth().currentUser?.uid
    }
    
    var filteredUsers: [UserListItem] {
        if searchText.isEmpty {
            return groupService.availableUsers
        } else {
            return groupService.availableUsers.filter { user in
                user.username.lowercased().contains(searchText.lowercased()) || 
                (user.displayName?.lowercased().contains(searchText.lowercased()) ?? false)
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            // Background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                    // Header section with banner image
                    ZStack(alignment: .top) {
                        // Banner Image, now the bottom layer
                        ZStack(alignment: .bottomLeading) {
                            if let avatarURL = group.avatarURL, let url = URL(string: avatarURL) {
                                KFImage(url)
                                    .placeholder {
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color(red: 40/255, green: 40/255, blue: 50/255),
                                                        Color(red: 25/255, green: 25/255, blue: 35/255)
                                                    ]),
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                    }
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 220)
                                    .clipped()
                                    .id(avatarRefreshId) // Refresh image when ID changes
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5),
                                                Color(red: 40/255, green: 40/255, blue: 50/255)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: 220)
                            }
                            
                            // Dark overlay for text readability
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                )
                            
                            // Group Name and member count
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.name)
                                    .font(.custom("PlusJakartaSans-Bold", size: 28))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                    Text("\(group.memberCount) member\(group.memberCount != 1 ? "s" : "")")
                                }
                                .font(.custom("PlusJakartaSans-Medium", size: 16))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                            // Upload progress overlay
                        if isUploadingImage {
                            ZStack {
                                    Rectangle().fill(.black.opacity(0.5))
                                    ProgressView("Uploading...")
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .foregroundColor(.white)
                                        .scaleEffect(1.2)
                                }
                                .frame(height: 220)
                            }
                        }
                        .frame(height: 220)
                        .opacity(headerOpacity)
                        .scaleEffect(avatarScale)

                        
                        // Elegant navigation header, now the top layer
                        HStack {
                            Button(action: {
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 40, height: 40)
                                    
                                Image(systemName: "chevron.left")
                                        .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                                .foregroundColor(.white)
                                }
                            }
                            
                            Spacer()
                            
                            // Camera button for owners in top-right
                            if isOwner {
                                PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 44, height: 44)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 64/255, green: 156/255, blue: 255/255), lineWidth: 2)
                                    )
                                    .shadow(
                                        color: Color.black.opacity(0.3),
                                        radius: 8,
                                        x: 0,
                                        y: 4
                                    )
                                    .shadow(
                                        color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.4),
                                        radius: 6,
                                        x: 0,
                                        y: 2
                                    )
                                }
                                .onChange(of: imagePickerItem) { newItem in
                                    loadTransferableImage(from: newItem)
                                }
                                .scaleEffect(isUploadingImage ? 0.9 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isUploadingImage)
                            } else {
                                // Placeholder for non-owners
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.safeAreaInsets.top)
                        .padding(.bottom, 8)
                        .opacity(headerOpacity)
                    }
                    
                    // Glass morphism tab selector
                HStack(spacing: 0) {
                        ForEach(0..<3) { index in
                            let titles = ["Info", "Members", "Invite"]
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedTab = index
                                }
                                
                                if index == 1 {
                                    loadGroupMembers()
                                } else if index == 2 {
                        loadUsers()
                    }
                            }) {
                                Text(titles[index])
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                                    .foregroundColor(selectedTab == index ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        ZStack {
                                            if selectedTab == index {
                                                Capsule()
                                                    .fill(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.8))
                                                    .shadow(
                                                        color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.3),
                                                        radius: 8,
                                                        x: 0,
                                                        y: 4
                                                    )
                                            }
                                        }
                                    )
                            }
                        }
                    }
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .offset(y: tabsOffset)
                
                    // Content with smooth transitions
                ScrollView {
                        Group {
                    if selectedTab == 0 {
                        GroupInfoView(
                            group: group, 
                            isOwner: isOwner, 
                            onDeleteTapped: { 
                                showDeleteConfirmation = true 
                            },
                            isDeletingGroup: isDeletingGroup
                        )
                    } else if selectedTab == 1 {
                        MembersView(
                            groupService: groupService,
                            isLoadingMembers: isLoadingMembers
                        )
                    } else {
                        InviteView(
                            groupService: groupService,
                            groupId: group.id,
                            selectedUser: $selectedUser,
                            searchText: $searchText,
                            isInviting: $isInviting,
                            inviteSuccess: $inviteSuccess,
                            isDropdownVisible: $isDropdownVisible,
                            isLoadingUsers: isLoadingUsers,
                            filteredUsers: filteredUsers,
                            inviteUser: inviteUser
                        )
                    }
                        }
                        .transition(.opacity.combined(with: .offset(y: 20)))
                }
                .padding(.bottom, 16)
            }
                .ignoresSafeArea(.container, edges: .top)
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(error ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Delete Group", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteGroup()
                }
            } message: {
                Text("Are you sure you want to delete this group? This action cannot be undone. All messages and data will be permanently lost.")
        }
        .onAppear {
                // Beautiful entrance animations
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                    headerOpacity = 1.0
                }
                
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                    avatarScale = 1.0
                }
                
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    tabsOffset = 0
                }
                
            if selectedTab == 1 {
                loadGroupMembers()
            } else if selectedTab == 2 {
                loadUsers()
            }
        }
        }
    }
    
    private func loadTransferableImage(from imageSelection: PhotosPickerItem?) {
        guard let imageSelection else { return }
        
        Task {
            do {
                if let data = try await imageSelection.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                        uploadGroupImage(image)
                    }
                }
            } catch {

            }
        }
    }
    
    private func uploadGroupImage(_ image: UIImage) {
        print("🖼️ Starting group image upload...")
        isUploadingImage = true
        
        // Use the same approach as profile pictures with completion handler
        Task {
            let imageURL = await withCheckedContinuation { continuation in
                print("📤 Calling upload service...")
                groupService.uploadGroupImageWithCompletion(image, groupId: group.id) { result in
                    print("📥 Upload service returned: \(result)")
                    continuation.resume(returning: result)
                }
            }
            
            await MainActor.run {
                switch imageURL {
                case .success(let urlString):
                    print("✅ Upload successful, updating group avatar...")
                // Update the group avatar URL in Firebase
                    Task {
                        do {
                            try await groupService.updateGroupAvatar(groupId: group.id, avatarURL: urlString)
                            print("✅ Group avatar updated in Firestore")
                
                // Refresh the user's groups to update the avatar in the main GroupsView
                try await groupService.fetchUserGroups()
                            print("✅ User groups refreshed")
                
                await MainActor.run {
                    isUploadingImage = false
                                selectedImage = nil
                                imagePickerItem = nil
                                
                                // Update the local currentGroup with the new avatar URL
                                group.avatarURL = urlString
                                // Force AsyncImage to refresh by changing its ID
                                avatarRefreshId = UUID()
                                print("✅ Upload complete! Updated local group avatar")
                    
                    // Notify parent view to refresh the UI for other screens
                    NotificationCenter.default.post(name: NSNotification.Name("GroupDataChanged"), object: nil)
                }
            } catch {
                            print("❌ Failed to update group avatar: \(error)")
                await MainActor.run {
                                self.error = "Failed to update group avatar: \(error.localizedDescription)"
                                self.showError = true
                                isUploadingImage = false
                                selectedImage = nil
                                imagePickerItem = nil
                            }
                        }
                    }
                    
                case .failure(let error):
                    print("❌ Upload failed: \(error)")
                    self.error = "Failed to upload image: \(error.localizedDescription)"
                    self.showError = true
                    isUploadingImage = false
                    selectedImage = nil
                    imagePickerItem = nil
                }
            }
        }
    }
    
    private func loadUsers() {
        isLoadingUsers = true
        Task {
            do {
                try await groupService.fetchAvailableUsers()
                await MainActor.run {
                    isLoadingUsers = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isLoadingUsers = false
                }
            }
        }
    }
    
    private func loadGroupMembers() {
        isLoadingMembers = true
        Task {
            do {
                try await groupService.fetchGroupMembers(groupId: group.id)
                await MainActor.run {
                    isLoadingMembers = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isLoadingMembers = false
                }
            }
        }
    }
    
    private func deleteGroup() {
        isDeletingGroup = true
        
        Task {
            do {
                try await groupService.deleteGroup(groupId: group.id)
                
                await MainActor.run {
                    isDeletingGroup = false
                    // Notify that group data changed
                    NotificationCenter.default.post(name: NSNotification.Name("GroupDataChanged"), object: nil)
                    // Dismiss the view
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isDeletingGroup = false
                }
            }
        }
    }
    
    private func inviteUser() {
        guard let selectedUser = selectedUser else { return }
        
        isInviting = true
        inviteSuccess = false
        
        Task {
            do {
                try await groupService.inviteUserToGroup(username: selectedUser.username, groupId: group.id)
                
                await MainActor.run {
                    isInviting = false
                    self.selectedUser = nil
                    searchText = ""
                    inviteSuccess = true
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isInviting = false
                }
            }
        }
    }
}

struct GroupInfoView: View {
    let group: UserGroup
    let isOwner: Bool
    let onDeleteTapped: () -> Void
    let isDeletingGroup: Bool
    
    @State private var cardOpacity = 0.0
    @State private var cardOffset: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 24) {
            // Group Details section with glass morphism
            VStack(alignment: .leading, spacing: 20) {
                Text("Group Details")
                    .font(.custom("PlusJakartaSans-Bold", size: 22))
                    .foregroundColor(.white)
                
                VStack(spacing: 16) {
                    GroupDetailRow(
                        icon: "calendar",
                        title: "Created",
                        value: formattedDate(group.createdAt),
                        iconColor: Color(red: 64/255, green: 156/255, blue: 255/255)
                    )
                    
                    GroupDetailRow(
                        icon: "person.2.fill",
                        title: "Members",
                        value: "\(group.memberCount)",
                        iconColor: Color(red: 100/255, green: 180/255, blue: 255/255)
                    )
                    
                    
                }
                .padding(20)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .opacity(cardOpacity)
            .offset(y: cardOffset)
            
            // Description section if available
            if let description = group.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("About")
                        .font(.custom("PlusJakartaSans-Bold", size: 22))
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.custom("PlusJakartaSans-Medium", size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(4)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .opacity(cardOpacity)
                .offset(y: cardOffset)
            }
            
            // Delete button for group owners
            if isOwner {
                    Button(action: onDeleteTapped) {
                    HStack(spacing: 12) {
                            if isDeletingGroup {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                            } else {
                            Image(systemName: "trash.fill")
                                .font(.custom("PlusJakartaSans-Medium", size: 16))
                            }
                            
                            Text(isDeletingGroup ? "Deleting Group..." : "Delete Group")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.red.opacity(isDeletingGroup ? 0.6 : 0.9),
                                Color.red.opacity(isDeletingGroup ? 0.4 : 0.7)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(
                        color: Color.red.opacity(0.3),
                        radius: isDeletingGroup ? 0 : 8,
                        x: 0,
                        y: isDeletingGroup ? 0 : 4
                        )
                    }
                    .disabled(isDeletingGroup)
                .opacity(cardOpacity)
                .offset(y: cardOffset)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                cardOpacity = 1.0
                cardOffset = 0
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    

}

struct GroupDetailRow: View {
    let icon: String
    let title: String
    let value: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(value)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
    }
}

struct MembersView: View {
    let groupService: GroupService
    let isLoadingMembers: Bool
    
    @State private var membersOpacity = 0.0
    @State private var membersOffset: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 20) {
        if isLoadingMembers {
                VStack(spacing: 16) {
                ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 64/255, green: 156/255, blue: 255/255)))
                        .scaleEffect(1.2)
                    
                    Text("Loading members...")
                        .font(.custom("PlusJakartaSans-Medium", size: 16))
                        .foregroundColor(.white.opacity(0.7))
            }
            .frame(height: 200)
        } else if groupService.groupMembers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.custom("PlusJakartaSans-Medium", size: 40))
                        .foregroundColor(.white.opacity(0.5))
                    
                Text("No members found")
                        .font(.custom("PlusJakartaSans-Medium", size: 16))
                        .foregroundColor(.white.opacity(0.7))
            }
            .frame(height: 200)
        } else {
                VStack(spacing: 12) {
                    ForEach(Array(groupService.groupMembers.enumerated()), id: \.element.id) { index, member in
                    MemberRow(member: member)
                            .opacity(membersOpacity)
                            .offset(y: membersOffset)
                            .animation(
                                .easeOut(duration: 0.4).delay(Double(index) * 0.1),
                                value: membersOpacity
                            )
                    }
                }
                .padding(.horizontal, 20)
                .onAppear {
                    withAnimation {
                        membersOpacity = 1.0
                        membersOffset = 0
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

struct MemberRow: View {
    let member: GroupMemberInfo
    
    var body: some View {
        HStack(spacing: 16) {
            // Beautiful member avatar with glow
            ZStack {
                // Subtle glow effect
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.2),
                                Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .blur(radius: 4)
                
                // Main avatar container
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.4),
                                    lineWidth: 1.5
                                )
                        )
                
                if let avatarURL = member.avatarURL, let url = URL(string: avatarURL) {
                    KFImage(url)
                        .placeholder {
                            Image(systemName: "person.fill")
                                .font(.custom("PlusJakartaSans-Medium", size: 20))
                                .foregroundColor(.white.opacity(0.7))
                        }
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                            .font(.custom("PlusJakartaSans-Medium", size: 20))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            // Member info with beautiful typography
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                    if let displayName = member.displayName, !displayName.isEmpty {
                        Text(displayName)
                                .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                                .foregroundColor(.white)
                    } else {
                        Text("@\(member.username)")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                                .foregroundColor(.white)
                        }
                        
                        if member.displayName != nil {
                            Text("@\(member.username)")
                                .font(.custom("PlusJakartaSans-Medium", size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    if member.isOwner {
                        Text("Owner")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 255/255, green: 193/255, blue: 64/255),
                                        Color(red: 255/255, green: 175/255, blue: 64/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(
                                color: Color(red: 255/255, green: 193/255, blue: 64/255).opacity(0.3),
                                radius: 4,
                                x: 0,
                                y: 2
                            )
                    }
                }
                
                Text("Joined \(formattedDate(member.joinedAt))")
                    .font(.custom("PlusJakartaSans-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct InviteView: View {
    let groupService: GroupService
    let groupId: String
    @Binding var selectedUser: UserListItem?
    @Binding var searchText: String
    @Binding var isInviting: Bool
    @Binding var inviteSuccess: Bool
    @Binding var isDropdownVisible: Bool
    let isLoadingUsers: Bool
    let filteredUsers: [UserListItem]
    let inviteUser: () -> Void
    
    @State private var keyboardHeight: CGFloat = 0
    @State private var inviteOpacity = 0.0
    @State private var inviteOffset: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 16) {
            // Simple search field
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .trailing) {
                    TextField("Search users...", text: $searchText)
                        .font(.system(size: 16))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _ in
                            isDropdownVisible = true
                        }
                        .onTapGesture {
                            isDropdownVisible = true
                        }
                    
                    if isLoadingUsers {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 64/255, green: 156/255, blue: 255/255)))
                            .scaleEffect(0.8)
                            .padding(.trailing, 16)
                    } else {
                        Button(action: {
                            isDropdownVisible.toggle()
                        }) {
                            Image(systemName: isDropdownVisible ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.trailing, 16)
                        }
                    }
                }
                
                // Simple dropdown menu
                if isDropdownVisible && !filteredUsers.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredUsers) { user in
                                HStack(spacing: 12) {
                                    // Simple user avatar
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.3))
                                            .frame(width: 36, height: 36)
                                        
                                        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                                            KFImage(url)
                                                .placeholder {
                                                    Image(systemName: "person.fill")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.white.opacity(0.7))
                                                }
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 36, height: 36)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    
                                    // User info
                                    VStack(alignment: .leading, spacing: 1) {
                                        if let displayName = user.displayName, !displayName.isEmpty {
                                            Text(displayName)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.white)
                                                
                                            Text("@\(user.username)")
                                                .font(.system(size: 13))
                                                .foregroundColor(.white.opacity(0.6))
                                        } else {
                                            Text("@\(user.username)")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Selection indicator
                                    if selectedUser?.id == user.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background(
                                    selectedUser?.id == user.id ? 
                                        Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.15) : 
                                        Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    selectedUser = user
                                    searchText = user.displayText
                                    isDropdownVisible = false
                                }
                            }
                        }
                        .padding(6)
                    }
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxHeight: 200)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            
            // Simple invite button
            Button(action: inviteUser) {
                HStack(spacing: 8) {
                    if isInviting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                    }
                    
                    Text(isInviting ? "Sending..." : "Send Invite")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color(red: 64/255, green: 156/255, blue: 255/255)
                        .opacity(selectedUser == nil || isInviting ? 0.5 : 1.0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedUser == nil || isInviting)
            .padding(.horizontal, 20)
            
            // Success message
            if inviteSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    Text("Invitation sent!")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2))
                .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.top, 0)
        .padding(.bottom, keyboardHeight)
        .opacity(inviteOpacity)
        .offset(y: inviteOffset)
        .onAppear {
            // Beautiful entrance animation
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                inviteOpacity = 1.0
                inviteOffset = 0
            }
            
            // Set up keyboard observers
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = keyboardFrame.height
                }
            }
            
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                keyboardHeight = 0
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
    }
}

struct GroupTabButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: isSelected ? .bold : .medium, design: .default))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.8))
                        }
                    }
                )
        }
    }
}



// MARK: - Group Invite Flow View
struct GroupInviteFlowView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var groupService = GroupService()
    let group: UserGroup
    let onComplete: () -> Void
    
    @State private var selectedUser: UserListItem?
    @State private var searchText = ""
    @State private var isInviting = false
    @State private var inviteSuccess = false
    @State private var isDropdownVisible = false
    @State private var isLoadingUsers = false
    @State private var error: String?
    @State private var showError = false
    @State private var invitedUsers: [UserListItem] = []
    
    var filteredUsers: [UserListItem] {
        if searchText.isEmpty {
            return groupService.availableUsers.filter { user in
                !invitedUsers.contains(user)
            }
        } else {
            return groupService.availableUsers.filter { user in
                !invitedUsers.contains(user) && (
                    user.username.lowercased().contains(searchText.lowercased()) || 
                    (user.displayName?.lowercased().contains(searchText.lowercased()) ?? false)
                )
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        HStack {
                            Text("Invite Friends")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.top, 20)
                        
                        Text("to \(group.name)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 24)
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Search and invite section
                            VStack(alignment: .leading, spacing: 16) {
            // Custom dropdown field with search
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .trailing) {
                    TextField("Search users...", text: $searchText)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(red: 40/255, green: 40/255, blue: 45/255))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _ in
                            isDropdownVisible = true
                        }
                        .onTapGesture {
                            isDropdownVisible = true
                        }
                    
                    if isLoadingUsers {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 12)
                    } else {
                        Button(action: {
                            isDropdownVisible.toggle()
                        }) {
                            Image(systemName: isDropdownVisible ? "chevron.up" : "chevron.down")
                                .foregroundColor(.gray)
                                .padding(.trailing, 12)
                        }
                    }
                }
                
                // Dropdown menu
                if isDropdownVisible && !filteredUsers.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredUsers) { user in
                                HStack {
                                                        // User avatar
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                            .frame(width: 36, height: 36)
                                        
                                        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                                            KFImage(url)
                                                .placeholder {
                                                    Image(systemName: "person.fill")
                                                        .font(.system(size: 18))
                                                        .foregroundColor(.gray)
                                                }
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 36, height: 36)
                                                        .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.fill")
                                                                    .font(.system(size: 18))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.leading, 8)
                                    
                                    // User info
                                    VStack(alignment: .leading) {
                                        if let displayName = user.displayName, !displayName.isEmpty {
                                            Text(displayName)
                                                                    .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                                
                                            Text("@\(user.username)")
                                                                    .font(.system(size: 12))
                                                .foregroundColor(.gray)
                                        } else {
                                            Text("@\(user.username)")
                                                                    .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.leading, 8)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background(selectedUser?.id == user.id ? 
                                    Color(red: 50/255, green: 50/255, blue: 55/255) : 
                                    Color.clear)
                                .onTapGesture {
                                    selectedUser = user
                                    searchText = user.displayText
                                    isDropdownVisible = false
                                }
                            }
                        }
                    }
                    .background(Color(red: 30/255, green: 30/255, blue: 35/255))
                                        .frame(maxHeight: 200)
                    .cornerRadius(10)
                    .padding(.top, 4)
                }
            }
            
            // Invite button
            Button(action: inviteUser) {
                if isInviting {
                    ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                        .padding(.horizontal, 20)
                } else {
                                        Text("Send Invite")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 18)
            .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 64/255, green: 156/255, blue: 255/255),
                                            Color(red: 100/255, green: 180/255, blue: 255/255)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .opacity(selectedUser == nil || isInviting ? 0.6 : 1)
                                )
                                .cornerRadius(12)
            .disabled(selectedUser == nil || isInviting)
            
            if inviteSuccess {
                Text("Invitation sent!")
                                        .font(.system(size: 14))
                    .foregroundColor(.green)
            }
                            }
                            .padding(.horizontal, 20)
                            
                            // Invited users list
                            if !invitedUsers.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Invited (\(invitedUsers.count))")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                    
                                    VStack(spacing: 8) {
                                        ForEach(invitedUsers) { user in
                                            HStack {
                                                // User avatar
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                                        .frame(width: 32, height: 32)
                                                    
                                                    if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                                                        KFImage(url)
                                                            .placeholder {
                                                                Image(systemName: "person.fill")
                                                                    .font(.system(size: 16))
                                                                    .foregroundColor(.gray)
                                                            }
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 32, height: 32)
                                                            .clipShape(Circle())
                                                    } else {
                                                        Image(systemName: "person.fill")
                                                            .font(.system(size: 16))
                                                            .foregroundColor(.gray)
                                                    }
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    if let displayName = user.displayName, !displayName.isEmpty {
                                                        Text(displayName)
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundColor(.white)
                                                        Text("@\(user.username)")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.gray)
                                                    } else {
                                                        Text("@\(user.username)")
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundColor(.white)
                                                    }
                                                }
                                                
                                                Spacer()
                                                
                                                Text("Invited")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.green)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color(red: 30/255, green: 30/255, blue: 35/255))
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            
                            // Done button
                            Button(action: {
                                onComplete()
                            }) {
                                Text(invitedUsers.isEmpty ? "Skip for Now" : "Done")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 45/255, green: 45/255, blue: 50/255))
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarItems(
                leading: Button(action: {
                    onComplete()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color(red: 30/255, green: 33/255, blue: 36/255)))
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $showError) {
                Alert(title: Text("Error"), message: Text(error ?? "Unknown error"), dismissButton: .default(Text("OK")))
            }
        .onAppear {
                loadUsers()
            }
            .onTapGesture {
                isDropdownVisible = false
            }
        }
    }
    
    private func loadUsers() {
        isLoadingUsers = true
        Task {
            do {
                try await groupService.fetchAvailableUsers()
                await MainActor.run {
                    isLoadingUsers = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isLoadingUsers = false
                }
            }
        }
    }
    
    private func inviteUser() {
        guard let selectedUser = selectedUser else { return }
        
        isInviting = true
        inviteSuccess = false
        
        Task {
            do {
                try await groupService.inviteUserToGroup(username: selectedUser.username, groupId: group.id)
                
                await MainActor.run {
                    isInviting = false
                    invitedUsers.append(selectedUser)
                    self.selectedUser = nil
                    searchText = ""
                    inviteSuccess = true
                    
                    // Hide success message after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        inviteSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isInviting = false
                }
            }
        }
    }
} 
