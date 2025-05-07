import SwiftUI
import FirebaseAuth
import PhotosUI
import FirebaseStorage

struct GroupsView: View {
    @StateObject private var groupService = GroupService()
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var handStore: HandStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var postService: PostService
    @State private var showingCreateGroup = false
    @State private var showingInvites = false
    @State private var selectedGroup: UserGroup?
    @State private var showingGroupDetails = false
    @State private var groupActionSheet: UserGroup?
    @State private var error: String?
    @State private var showError = false
    @State private var showingGroupChat = false
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Modern header with animated notification badge
                    HStack {
                        Group {
                            Text("GROUPS")
                                .foregroundColor(.white)
                                .padding(.leading, 4)
                        }
                        .font(.system(size: 24, weight: .black))
                        
                        Spacer()
                        
                        // Notification bell with animated badge
                        Button(action: {
                            showingInvites = true
                        }) {
                            ZStack {
                                Image(systemName: !groupService.pendingInvites.isEmpty ? "bell.fill" : "bell")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                
                                if !groupService.pendingInvites.isEmpty {
                                    // Animated notification badge
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                        .offset(x: 8, y: -8)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(10)
                            .background(
                                Capsule()
                                    .fill(Color(red: 35/255, green: 35/255, blue: 40/255))
                            )
                        }
                        .padding(.trailing, 8)
                        
                        // Create group button
                        Button(action: {
                            showingCreateGroup = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                
                                Text("New")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                            }
                            .foregroundColor(.black)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(
                                Capsule()
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    
                    // Content
                    ScrollView {
                        // Pull to refresh
                        RefreshControls(isRefreshing: $isRefreshing) {
                            Task {
                                await refreshGroups()
                                isRefreshing = false
                            }
                        }
                        
                        if groupService.isLoading && groupService.userGroups.isEmpty {
                            // Centered loading indicator
                            VStack {
                                Spacer()
                                    .frame(height: 180)
                                
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                    .scaleEffect(1.5)
                            }
                        } else if groupService.userGroups.isEmpty {
                            // Empty state with animation
                            EmptyGroupsView(onCreateTapped: {
                                showingCreateGroup = true
                            })
                        } else {
                            // Groups list with staggered animation
                            LazyVStack(spacing: 16) {
                                ForEach(Array(groupService.userGroups.enumerated()), id: \.element.id) { index, group in
                                    GroupCard(group: group, onTap: {
                                        selectedGroup = group
                                        showingGroupChat = true
                                    }, onDetailsTap: {
                                        selectedGroup = group
                                        showingGroupDetails = true
                                    }, onOptionsTap: {
                                        groupActionSheet = group
                                    })
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 100) // Add padding at bottom for tab bar
                        }
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
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView { success in
                    if success {
                        Task {
                            await refreshGroups()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingInvites) {
                GroupInvitesView {
                    Task {
                        await refreshGroups()
                    }
                }
            }
            .sheet(isPresented: $showingGroupDetails) {
                if let group = selectedGroup {
                    GroupDetailView(group: group)
                }
            }
            .onChange(of: showingGroupDetails) { isShowing in
                if !isShowing {
                    // Refresh groups when the detail view is dismissed
                    Task {
                        await refreshGroups()
                    }
                }
            }
            .sheet(isPresented: $showingGroupChat) {
                if let group = selectedGroup {
                    GroupChatView(group: group)
                        .environmentObject(userService)
                        .environmentObject(handStore)
                        .environmentObject(sessionStore)
                        .environmentObject(postService)
                }
            }
            .confirmationDialog("Group Options", isPresented: .init(
                get: { groupActionSheet != nil },
                set: { if !$0 { groupActionSheet = nil } }
            ), titleVisibility: .visible) {
                if let group = groupActionSheet {
                    Button("View Details") {
                        selectedGroup = group
                        showingGroupDetails = true
                    }
                    
                    Button("Invite Members") {
                        selectedGroup = group
                        showingGroupDetails = true
                    }
                    
                    if group.ownerId != Auth.auth().currentUser?.uid {
                        Button("Leave Group", role: .destructive) {
                            Task {
                                await leaveGroup(group: group)
                            }
                        }
                    }
                    
                    Button("Cancel", role: .cancel) {
                        groupActionSheet = nil
                    }
                }
            }
            .onAppear {
                // Set up notification observer
                setupNotificationObserver()
                
                Task {
                    await refreshGroups()
                }
            }
            .onDisappear {
                // Clean up notification observer
                NotificationCenter.default.removeObserver(self)
            }
            .navigationBarHidden(true)
        }
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

// Beautiful empty state view with animations
struct EmptyGroupsView: View {
    let onCreateTapped: () -> Void
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)
            
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 70, design: .default))
                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                .rotationEffect(.degrees(animateIcon ? 8 : -8))
                .animation(
                    Animation.easeInOut(duration: 2)
                        .repeatForever(autoreverses: true),
                    value: animateIcon
                )
                .onAppear {
                    animateIcon = true
                }
            
            Text("No Groups Yet")
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundColor(.white)
            
            Text("Create your first group or wait for invites to connect with other players")
                .font(.system(size: 16, design: .default))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(4)
            
            Button(action: onCreateTapped) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, design: .default))
                    
                    Text("Create Group")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                }
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(
                    Capsule()
                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .shadow(
                            color: Color(red: 123/255, green: 255/255, blue: 99/255),
                            radius: 8, x: 0, y: 4
                        )
                )
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct GroupCard: View {
    let group: UserGroup
    let onTap: () -> Void
    let onDetailsTap: () -> Void
    let onOptionsTap: () -> Void
    @State private var cardOffset: CGFloat = 30
    @State private var cardOpacity: Double = 0
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    // Group avatar with gradient border
                    ZStack {
                        // Highlight gradient border
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 123/255, green: 255/255, blue: 99/255),
                                        Color(red: 50/255, green: 120/255, blue: 80/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                        
                        // Background for avatar
                        Circle()
                            .fill(Color(red: 35/255, green: 35/255, blue: 40/255))
                            .frame(width: 60, height: 60)
                        
                        if let avatarURL = group.avatarURL, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                } else if phase.error != nil {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 26, design: .default))
                                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                        .frame(width: 60, height: 60)
                                } else {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                        .frame(width: 60, height: 60)
                                }
                            }
                        } else {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 26, design: .default))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            Text(group.name)
                                .foregroundColor(.white)
                        }
                        .font(.system(size: 18, weight: .bold))
                        
                        if let description = group.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 14, design: .default))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                        
                        HStack(spacing: 12) {
                            // Members count
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12, design: .default))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                
                                Text("\(group.memberCount)")
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    // Action buttons column
                    VStack(spacing: 16) {
                        Button(action: onDetailsTap) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 18, design: .default))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .frame(width: 32, height: 32)
                                .background(Color(red: 35/255, green: 50/255, blue: 40/255))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
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
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
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
            .offset(y: cardOffset)
            .opacity(cardOpacity)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    cardOffset = 0
                    cardOpacity = 1
                }
            }
        }
        .buttonStyle(ScaleButtonStyles())
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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
    @State private var groupDescription = ""
    @State private var isCreating = false
    @State private var error: String?
    @State private var showError = false
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem?
    
    // Animation states
    @State private var nameFieldOpacity = 0.0
    @State private var descFieldOpacity = 0.0
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
                        // Header with icon
                        VStack(spacing: 8) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 40, design: .default))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.bottom, 8)
                            
                            Text("Create New Group")
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundColor(.white)
                            
                            Text("Connect with players who share your interests")
                                .font(.system(size: 16, design: .default))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.top, 20)
                        .opacity(nameFieldOpacity)
                        
                        // Group image selection
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
                        .padding(.bottom, 16)
                        .opacity(imageOpacity)
                        
                        // Form fields
                        VStack(spacing: 20) {
                            // Group name field with floating label
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GROUP NAME")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .padding(.leading, 4)
                                
                                TextField("", text: $groupName)
                                    .placeholder(when: groupName.isEmpty) {
                                        Text("Enter group name").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17, design: .default))
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.1),
                                                        Color.clear,
                                                        Color.clear,
                                                        Color.clear
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .foregroundColor(.white)
                            }
                            .opacity(nameFieldOpacity)
                            
                            // Group description field with floating label
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DESCRIPTION")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .padding(.leading, 4)
                                
                                TextField("", text: $groupDescription)
                                    .placeholder(when: groupDescription.isEmpty) {
                                        Text("What's this group about? (Optional)").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17, design: .default))
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.1),
                                                        Color.clear,
                                                        Color.clear,
                                                        Color.clear
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .foregroundColor(.white)
                            }
                            .opacity(descFieldOpacity)
                        }
                        .padding(.horizontal, 24)
                        
                        // Create button with gradient and shadow
                        Button(action: createGroup) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Create Group")
                                        .font(.system(size: 17, weight: .semibold, design: .default))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                groupName.isEmpty || isCreating
                                    ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                    : Color(red: 123/255, green: 255/255, blue: 99/255)
                            )
                            .cornerRadius(16)
                            .shadow(
                                color: groupName.isEmpty ? Color.clear : Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.4),
                                radius: 8, x: 0, y: 4
                            )
                        }
                        .disabled(groupName.isEmpty || isCreating)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .opacity(buttonOpacity)
                    }
                    .padding(.bottom, 40)
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
            .onAppear {
                // Animate elements sequentially
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                    nameFieldOpacity = 1.0
                }
                
                withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                    imageOpacity = 1.0
                }
                
                withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                    descFieldOpacity = 1.0
                }
                
                withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                    buttonOpacity = 1.0
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
                print("Error loading image: \(error)")
            }
        }
    }
    
    private func createGroup() {
        guard !groupName.isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                let description = groupDescription.isEmpty ? nil : groupDescription
                
                if let image = selectedImage {
                    _ = try await groupService.createGroup(
                        name: groupName,
                        description: description,
                        image: image
                    )
                } else {
                    _ = try await groupService.createGroup(
                        name: groupName,
                        description: description
                    )
                }
                
                await MainActor.run {
                    isCreating = false
                    onComplete(true)
                    presentationMode.wrappedValue.dismiss()
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
                            
                            LottieView(name: "empty-notifications", loopMode: .loop)
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
                        .font(.system(size: 16, weight: .semibold, design: .default))
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



// LottieView placeholder - you would need to add the Lottie package
// This is a simplified version until you add the real implementation
struct LottieView: View {
    let name: String
    let loopMode: LoopMode
    
    enum LoopMode {
        case loop
        case playOnce
    }
    
    var body: some View {
        // Placeholder until Lottie is implemented
        VStack {
            Image(systemName: "bell.slash")
                .font(.system(size: 50, design: .default))
                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
        }
    }
}

struct GroupDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var groupService = GroupService()
    let group: UserGroup
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
    
    // For image upload
    @State private var selectedImage: UIImage?
    @State private var isShowingImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    
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
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                
                VStack(spacing: 0) {
                    // Group info header
                    VStack(spacing: 16) {
                        // Group avatar with edit capability
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
                            } else if let avatarURL = group.avatarURL, let url = URL(string: avatarURL) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                    } else if phase.error != nil {
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 40, design: .default))
                                            .foregroundColor(.gray)
                                    } else {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                            .frame(width: 100, height: 100)
                                    }
                                }
                            } else {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 40, design: .default))
                                    .foregroundColor(.gray)
                            }
                            
                            // Show camera icon for uploading if owner
                            if isOwner {
                                PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14, design: .default))
                                            .foregroundColor(.white)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 2)
                                    )
                                }
                                .onChange(of: imagePickerItem) { newItem in
                                    loadTransferableImage(from: newItem)
                                }
                                .position(x: 75, y: 75)
                            }
                            
                            // Show loading indicator when uploading
                            if isUploadingImage {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 100, height: 100)
                                    
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                        .scaleEffect(1.5)
                                }
                            }
                        }
                        
                        Group {
                            Text(group.name)
                                .foregroundColor(.white)
                        }
                        .font(.system(size: 24, weight: .bold))
                        
                        if let description = group.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 16, design: .default))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14, design: .default))
                                .foregroundColor(.gray)
                            
                            Text("\(group.memberCount) member\(group.memberCount != 1 ? "s" : "")")
                                .font(.system(size: 14, design: .default))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    
                    // Tab selector
                    HStack(spacing: 0) {
                        GroupTabButton(text: "Info", isSelected: selectedTab == 0) {
                            selectedTab = 0
                        }
                        
                        GroupTabButton(text: "Members", isSelected: selectedTab == 1) {
                            selectedTab = 1
                            loadGroupMembers()
                        }
                        
                        GroupTabButton(text: "Invite", isSelected: selectedTab == 2) {
                            selectedTab = 2
                            loadUsers()
                        }
                    }
                    .background(Color(red: 30/255, green: 30/255, blue: 35/255))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    
                    // Content based on selected tab
                    ScrollView {
                        if selectedTab == 0 {
                            // Group Info Tab
                            GroupInfoView(group: group)
                        } else if selectedTab == 1 {
                            // Members Tab
                            MembersView(
                                groupService: groupService,
                                isLoadingMembers: isLoadingMembers
                            )
                        } else {
                            // Invite Tab
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
                    .padding(.bottom, 16)
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
                },
                trailing: Text(group.name)
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundColor(.white)
            )
            .onAppear {
                if selectedTab == 1 {
                    loadGroupMembers()
                } else if selectedTab == 2 {
                    loadUsers()
                }
            }
            .onTapGesture {
                // Hide dropdown when tapping outside
                isDropdownVisible = false
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
                print("Error loading image: \(error)")
            }
        }
    }
    
    private func uploadGroupImage(_ image: UIImage) {
        isUploadingImage = true
        
        Task {
            do {
                // Use the GroupService's uploadGroupImage function
                let imageURL = try await groupService.uploadGroupImage(image, groupId: group.id)
                
                // Update the group avatar URL in Firebase
                try await groupService.updateGroupAvatar(groupId: group.id, avatarURL: imageURL)
                
                // Refresh the user's groups to update the avatar in the main GroupsView
                try await groupService.fetchUserGroups()
                
                await MainActor.run {
                    isUploadingImage = false
                    
                    // Notify parent view to refresh the UI for other screens
                    NotificationCenter.default.post(name: NSNotification.Name("GroupDataChanged"), object: nil)
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to upload image: \(error.localizedDescription)"
                    self.showError = true
                    isUploadingImage = false
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

// Sub-views for GroupDetailView
struct GroupInfoView: View {
    let group: UserGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Group Details section
            VStack(alignment: .leading, spacing: 8) {
                Text("Group Details")
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Created")
                            .foregroundColor(.gray)
                        Spacer()
                        Text(formattedDate(group.createdAt))
                            .foregroundColor(.white)
                    }
                    
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    HStack {
                        Text("Members")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(group.memberCount)")
                            .foregroundColor(.white)
                    }
                }
                .padding(16)
                .background(Color(red: 30/255, green: 30/255, blue: 35/255))
                .cornerRadius(10)
                .padding(.horizontal, 16)
            }
            
            if let description = group.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    Text(description)
                        .font(.system(size: 16, design: .default))
                        .foregroundColor(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 30/255, green: 30/255, blue: 35/255))
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                }
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct MembersView: View {
    let groupService: GroupService
    let isLoadingMembers: Bool
    
    var body: some View {
        if isLoadingMembers {
            VStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                Spacer()
            }
            .frame(height: 200)
        } else if groupService.groupMembers.isEmpty {
            VStack {
                Spacer()
                Text("No members found")
                    .foregroundColor(.gray)
                Spacer()
            }
            .frame(height: 200)
        } else {
            VStack(spacing: 16) {
                ForEach(groupService.groupMembers) { member in
                    MemberRow(member: member)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct MemberRow: View {
    let member: GroupMemberInfo
    
    var body: some View {
        HStack(spacing: 12) {
            // Member avatar
            ZStack {
                Circle()
                    .fill(Color(red: 40/255, green: 40/255, blue: 50/255))
                    .frame(width: 48, height: 48)
                
                if let avatarURL = member.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else if phase.error != nil {
                            Image(systemName: "person.fill")
                                .font(.system(size: 22, design: .default))
                                .foregroundColor(.gray)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, design: .default))
                        .foregroundColor(.gray)
                }
            }
            
            // Member info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let displayName = member.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                    } else {
                        Text("@\(member.username)")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                    }
                    
                    if member.isOwner {
                        Text("Owner")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .cornerRadius(4)
                    }
                }
                
                if member.displayName != nil {
                    Text("@\(member.username)")
                        .font(.system(size: 14, design: .default))
                        .foregroundColor(.gray)
                }
                
                Text("Joined \(formattedDate(member.joinedAt))")
                    .font(.system(size: 12, design: .default))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(red: 30/255, green: 30/255, blue: 35/255))
        .cornerRadius(10)
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
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Invite Members")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            
            // Custom dropdown field with search
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .trailing) {
                    TextField("Search users...", text: $searchText)
                        .padding()
                        .background(Color(red: 40/255, green: 40/255, blue: 45/255))
                        .cornerRadius(10)
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
                                    // User avatar in user selection
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                            .frame(width: 36, height: 36)
                                        
                                        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                                            AsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 36, height: 36)
                                                        .clipShape(Circle())
                                                } else if phase.error != nil {
                                                    Image(systemName: "person.fill")
                                                        .font(.system(size: 18, design: .default))
                                                        .foregroundColor(.gray)
                                                } else {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                                }
                                            }
                                        } else {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 18, design: .default))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.leading, 8)
                                    
                                    // User info
                                    VStack(alignment: .leading) {
                                        if let displayName = user.displayName, !displayName.isEmpty {
                                            Text(displayName)
                                                .font(.system(size: 14, weight: .semibold, design: .default))
                                                .foregroundColor(.white)
                                                
                                            Text("@\(user.username)")
                                                .font(.system(size: 12, design: .default))
                                                .foregroundColor(.gray)
                                        } else {
                                            Text("@\(user.username)")
                                                .font(.system(size: 14, weight: .semibold, design: .default))
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
            .padding(.horizontal, 16)
            
            // Invite button
            Button(action: inviteUser) {
                if isInviting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .frame(width: 20, height: 20)
                        .padding(.horizontal, 20)
                } else {
                    Text("Invite")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 15)
            .background(
                selectedUser == nil || isInviting
                    ? Color(red: 123/255, green: 255/255, blue: 99/255)
                    : Color(red: 123/255, green: 255/255, blue: 99/255)
            )
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .disabled(selectedUser == nil || isInviting)
            
            if inviteSuccess {
                Text("Invitation sent!")
                    .font(.system(size: 14, design: .default))
                    .foregroundColor(.green)
            }
        }
    }
}

struct GroupTabButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular, design: .default))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color(red: 40/255, green: 40/255, blue: 45/255) : Color.clear)
                .cornerRadius(8)
        }
    }
} 
