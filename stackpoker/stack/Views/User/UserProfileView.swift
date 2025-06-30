import SwiftUI
import FirebaseAuth
import Kingfisher // For displaying avatar image
import FirebaseFirestore

struct UserProfileView: View {
    let userId: String // The ID of the profile being viewed
    @StateObject private var profilePostService = PostService(profileMode: true) // For fetching user's posts - won't respond to follow changes
    @StateObject private var publicSessionService = PublicSessionService() // For fetching user's public sessions
    @EnvironmentObject var userService: UserService // To get user details and current user info

    // State for the follow button
    @State private var isFollowing: Bool = false // Placeholder: actual value needs to be fetched
    @State private var isProcessingFollow: Bool = false
    
    // State for post notifications
    @State private var postNotificationsEnabled: Bool = false
    @State private var isProcessingNotifications: Bool = false
    @State private var showingPostNotificationPrompt: Bool = false
    @State private var targetUserName: String = ""
    
    // State for blocking functionality
    @State private var showingBlockAlert: Bool = false
    @State private var isUserBlocked: Bool = false

    // Local follower/following counts so we don't need to mutate `userService.loadedUsers` each time
    @State private var localFollowersCount: Int = 0
    @State private var localFollowingCount: Int = 0
    
    // Active challenges for the user
    @State private var activeChallenges: [Challenge] = []
    
    // User's public sessions
    @State private var userPublicSessions: [PublicLiveSession] = []
    
    // State for edit profile
    @State private var showingEditProfile = false

    private var loggedInUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var isCurrentUserProfile: Bool {
        userId == loggedInUserId
    }
    
    // Combined content type for profile activity
    enum ProfileContentType: Identifiable {
        case post(Post)
        case publicSession(PublicLiveSession)
        
        var id: String {
            switch self {
            case .post(let post):
                return "post_\(post.id ?? "")"
            case .publicSession(let session):
                return "session_\(session.id)"
            }
        }
        
        var timestamp: Date {
            switch self {
            case .post(let post):
                return post.createdAt
            case .publicSession(let session):
                return session.createdAt
            }
        }
    }
    
    // Computed property to get combined and sorted user activity
    private var combinedUserActivity: [ProfileContentType] {
        var combined: [ProfileContentType] = []
        
        // Add posts
        combined.append(contentsOf: profilePostService.posts.map { .post($0) })
        print("📝 [UserProfileView] Added \(profilePostService.posts.count) posts to combined activity")
        
        // Add public sessions
        combined.append(contentsOf: userPublicSessions.map { .publicSession($0) })
        print("🎮 [UserProfileView] Added \(userPublicSessions.count) public sessions to combined activity")
        
        // Sort by timestamp (newest first)
        let sorted = combined.sorted { $0.timestamp > $1.timestamp }
        print("📊 [UserProfileView] Total combined activity items: \(sorted.count)")
        return sorted
    }

    var body: some View {
        ScrollView {
            if let user = userService.loadedUsers[userId] {
                VStack(alignment: .leading, spacing: 16) {
                    // Profile Header
                    HStack(spacing: 16) {
                        // Avatar Image
                        Group {
                            if let avatarURLString = user.avatarURL, let url = URL(string: avatarURLString) {
                                KFImage(url)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                            } else {
                                PlaceholderAvatarView(size: 80)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName ?? user.username)
                                .font(.title2).bold()
                                .foregroundColor(.white)
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer() // Pushes content to left, button to right if in HStack
                    }
                    .padding(.horizontal)

                    // Follow/Edit Profile Button & Stats
                    HStack(spacing: 20) {
                        StatView(count: localFollowersCount, label: "Followers")
                        StatView(count: localFollowingCount, label: "Following")
                        Spacer()
                        if !isCurrentUserProfile {
                            Button(action: toggleFollow) {
                                Text(isFollowing ? "Unfollow" : "Follow")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isFollowing ? .white : .black)
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(isFollowing ? Color.gray.opacity(0.7) : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(isFollowing ? Color.gray : Color.clear, lineWidth: 1)
                                    )
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(isProcessingFollow)
                            
                            // Post Notifications Toggle (only show when following)
                            if isFollowing {
                                Button(action: { 
                                    // Show popup to ask about notifications
                                    if let user = userService.loadedUsers[userId] {
                                        targetUserName = user.username
                                    } else {
                                        targetUserName = "this user"
                                    }
                                    showingPostNotificationPrompt = true
                                }) {
                                    Image(systemName: postNotificationsEnabled ? "bell.fill" : "bell.slash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(postNotificationsEnabled ? Color.blue.opacity(0.7) : Color.gray.opacity(0.5))
                                        .cornerRadius(20)
                                }
                                .disabled(isProcessingNotifications)
                            }
                            
                            // Block Button
                            Button(action: { 
                                blockUser()
                            }) {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.7))
                                    .cornerRadius(20)
                            }
                            

                        } else {
                            // Edit Profile button for current user
                            Button(action: { 
                                showingEditProfile = true 
                            }) {
                                Text("Edit Profile")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.5))
                                    .cornerRadius(20)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.horizontal)

                    // Bio and hyperlink combined
                    VStack(alignment: .leading, spacing: 8) {
                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(nil) // Allow multi-line bio
                        }
                        
                        // Simple hyperlink - just colored text
                        if let hyperlinkText = user.hyperlinkText, !hyperlinkText.isEmpty,
                           let hyperlinkURL = user.hyperlinkURL, !hyperlinkURL.isEmpty {
                            Button(action: {
                                // Ensure URL has proper scheme
                                var urlString = hyperlinkURL
                                if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                                    urlString = "https://" + urlString
                                }
                                
                                if let url = URL(string: urlString) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text(hyperlinkText)
                                    .font(.body)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    // Active Challenges Section
                    if !activeChallenges.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Active Challenges")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ForEach(activeChallenges) { challenge in
                                ChallengeProgressComponent(
                                    challenge: challenge,
                                    isCompact: true
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Divider().padding(.horizontal)
                    
                    // Changed from "User's Posts"
                    Text("Recent Activity")
                        .font(.plusJakarta(.title2, weight: .bold)) // Using Plus Jakarta Sans, bold, size 22-24 equivalent
                        .foregroundColor(.white) // Ensure text is white
                        .padding([.horizontal, .top])
                    
                    if combinedUserActivity.isEmpty && !profilePostService.isLoading {
                        Text("This user hasn't shared any activity yet.")
                            .foregroundColor(.gray)
                            .padding()
                    } else if profilePostService.isLoading {
                        ProgressView().padding()
                    }
                    
                    // List of user's activity (posts and public sessions)
                    ForEach(combinedUserActivity) { content in
                        VStack(spacing: 0) {
                            switch content {
                            case .post(let post):
                                NavigationLink(destination: PostDetailView(post: post, userId: loggedInUserId ?? "").environmentObject(userService).environmentObject(profilePostService)) {
                                    PostCardView(
                                        post: post, 
                                        onLike: { 
                                            Task { try? await profilePostService.toggleLike(postId: post.id ?? "", userId: loggedInUserId ?? "") } 
                                        }, 
                                        onComment: { /* Comment handling for profile view if needed */ }, 
                                        isCurrentUser: post.userId == loggedInUserId,
                                        userId: loggedInUserId ?? "" // Pass logged-in user ID
                                    )
                                }
                                .buttonStyle(PlainButtonStyle()) // Ensures the whole PostView is tappable like a button
                                
                            case .publicSession(let session):
                                PublicLiveSessionCard(
                                    session: session,
                                    currentUserId: loggedInUserId ?? "",
                                    onViewTapped: {
                                        // TODO: Implement view session functionality
                                        print("View session tapped: \(session.id)")
                                    }
                                )
                                .environmentObject(userService)
                            }
                            
                            Divider()
                        }
                    }
                    
                }
                .padding(.vertical)
            } else {
                // Loading state or user not found
                VStack {
                    ProgressView()
                    Text("Loading profile...")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(AppBackgroundView().ignoresSafeArea()) // Assuming AppBackgroundView exists
        .alert("User Blocked", isPresented: $showingBlockAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let user = userService.loadedUsers[userId] {
                Text("\(user.displayName ?? user.username) has been blocked. You will no longer see their posts in your feed.")
            }
        }
        .alert("Turn on Post Notifications?", isPresented: $showingPostNotificationPrompt) {
            Button("Yes") {
                Task {
                    do {
                        try await userService.updatePostNotificationPreference(targetUserId: userId, enabled: true)
                        await MainActor.run {
                            self.postNotificationsEnabled = true
                        }
                    } catch {
                        print("Error enabling post notifications: \(error)")
                    }
                }
            }
            Button("No", role: .cancel) { 
                // Do nothing, keep notifications disabled
            }
        } message: {
            Text("Turn on post notifications for @\(targetUserName)?")
        }
        .sheet(isPresented: $showingEditProfile) {
            if let user = userService.loadedUsers[userId] {
                ProfileEditView(
                    profile: user,
                    onSave: { updatedProfile in
                        // Update the userService with the new profile data
                        userService.loadedUsers[userId] = updatedProfile
                        
                        // Also update current user profile if this is the current user
                        if isCurrentUserProfile {
                            userService.currentUserProfile = updatedProfile
                        }
                    }
                )
                .environmentObject(userService)
            }
        }
        .onAppear {
            Task {
                if userService.loadedUsers[userId] == nil {
                    await userService.fetchUser(id: userId) // Fetch user details if not already loaded
                }

                // Initialize local counts from fetched user profile if available
                if let profile = userService.loadedUsers[userId] {
                    self.localFollowersCount = profile.followersCount
                    self.localFollowingCount = profile.followingCount
                    
                    // Debug: Print hyperlink data
                    print("🔗 [UserProfileView] User \(profile.username) hyperlink data:")
                    print("   - hyperlinkText: '\(profile.hyperlinkText ?? "nil")'")
                    print("   - hyperlinkURL: '\(profile.hyperlinkURL ?? "nil")'")
                }

                // Fetch initial follow state
                if let currentLoggedInUserId = loggedInUserId {
                    self.isFollowing = await userService.isUserFollowing(targetUserId: userId, currentUserId: currentLoggedInUserId)
                    
                    // If following, also fetch post notification preference
                    if self.isFollowing {
                        self.postNotificationsEnabled = await userService.getPostNotificationPreference(targetUserId: userId, currentUserId: currentLoggedInUserId)
                    }
                }

                // Fetch user's posts
                try? await profilePostService.fetchPosts(forUserId: userId)
                
                // Fetch user's public sessions
                try? await fetchUserPublicSessions()
                
                // Fetch user's active challenges
                await fetchActiveChallenges()
            }
        }
    }

    func toggleFollow() {
        guard let currentLoggedInUserId = loggedInUserId, userId != currentLoggedInUserId else { return }
        
        isProcessingFollow = true

        Task {
            do {
                if isFollowing {
                    // Currently following –> unfollow
                    try await userService.unfollowUser(userIdToUnfollow: userId)
                    await MainActor.run {
                        self.localFollowersCount = max(0, self.localFollowersCount - 1)
                        self.postNotificationsEnabled = false // Reset to default when unfollowing
                    }
                } else {
                    // Not following –> follow
                    try await userService.followUser(userIdToFollow: userId)
                    await MainActor.run {
                        self.localFollowersCount += 1
                        self.postNotificationsEnabled = false // Default to false when following
                    }
                }

                // Optimistically flip local UI state on the main actor
                await MainActor.run {
                    self.isFollowing.toggle()
                    self.isProcessingFollow = false
                }
            } catch {
                // On error just clear processing flag; state stays unchanged
                await MainActor.run {
                    self.isProcessingFollow = false
                }
            }
        }
    }
    
    func togglePostNotifications() {
        guard let currentLoggedInUserId = loggedInUserId, isFollowing else { return }
        
        isProcessingNotifications = true
        
        Task {
            do {
                let newState = !postNotificationsEnabled
                try await userService.updatePostNotificationPreference(targetUserId: userId, enabled: newState)
                
                await MainActor.run {
                    self.postNotificationsEnabled = newState
                    self.isProcessingNotifications = false
                }
            } catch {
                print("Error toggling post notifications: \(error)")
                await MainActor.run {
                    self.isProcessingNotifications = false
                }
            }
        }
    }
    
    private func fetchUserPublicSessions() async throws {
        print("🔍 [UserProfileView] Fetching public sessions for userId: \(userId)")
        do {
            let sessions = try await publicSessionService.fetchUserSessions(userId: userId)
            print("✅ [UserProfileView] Fetched \(sessions.count) public sessions for user \(userId)")
            await MainActor.run {
                self.userPublicSessions = sessions
                print("📱 [UserProfileView] Updated userPublicSessions with \(sessions.count) sessions")
            }
        } catch {
            print("❌ [UserProfileView] Error fetching user public sessions: \(error)")
            throw error
        }
    }
    
    private func fetchActiveChallenges() async {
        do {
            // Initialize challenge service on main actor
            let challengeService = await MainActor.run {
                ChallengeService(userId: userId)
            }
            
            // Create a simple query to get public challenges for this user
            let db = Firestore.firestore()
            let snapshot = try await db.collection("challenges")
                .whereField("userId", isEqualTo: userId)
                .whereField("isPublic", isEqualTo: true)
                .whereField("status", isEqualTo: "active")
                .limit(to: 3) // Show max 3 challenges
                .getDocuments()
            
            let challenges = snapshot.documents.compactMap { Challenge(document: $0) }
            
            await MainActor.run {
                self.activeChallenges = challenges
            }
        } catch {
            print("❌ Error fetching challenges: \(error)")
        }
    }

    private func blockUser() {
        guard let currentLoggedInUserId = loggedInUserId, userId != currentLoggedInUserId else { return }
        
        Task {
            // If currently following the user, unfollow them first
            if isFollowing {
                do {
                    try await userService.unfollowUser(userIdToUnfollow: userId)
                    await MainActor.run {
                        self.isFollowing = false
                        self.localFollowersCount = max(0, self.localFollowersCount - 1)
                    }
                } catch {
                    print("❌ Error unfollowing user during block: \(error)")
                }
            }
            
            // Set blocked state and show alert
            await MainActor.run {
                self.isUserBlocked = true
                self.showingBlockAlert = true
            }
            
            // Here you would typically call an actual block API
            // For now, just print for debugging
            if let user = userService.loadedUsers[userId] {
                print("🚫 User blocked: \(user.username)")
            }
        }
    }
}

// Helper view for stats
struct StatView: View {
    let count: Int
    let label: String

    var body: some View {
        VStack {
            Text("\(count)")
                .font(.headline).bold()
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// Challenge Progress View for user profiles
struct ChallengeProgressView: View {
    let challenge: Challenge
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: challenge.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorForType(challenge.type))
                
                Text(challenge.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(Int(challenge.progressPercentage))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorForType(challenge.type))
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForType(challenge.type))
                        .frame(width: geometry.size.width * CGFloat(challenge.progressPercentage / 100), height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: challenge.progressPercentage)
                }
            }
            .frame(height: 4)
            
            Text("\(formattedValue(challenge.currentValue, type: challenge.type)) / \(formattedValue(challenge.targetValue, type: challenge.type))")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
    
    private func colorForType(_ type: ChallengeType) -> Color {
        switch type {
        case .bankroll: return .green
        case .hands: return .purple
        case .session: return .orange
        }
    }
    
    private func formattedValue(_ value: Double, type: ChallengeType) -> String {
        switch type {
        case .bankroll:
            return "$\(Int(value).formattedWithCommas)"
        case .hands:
            return "\(Int(value))"
        case .session:
            return "\(Int(value))"
        }
    }
}

// Preview needs adjustment for the new structure
struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleUserId = "sampleUser123"
        let mockUserService = UserService()
        // Preload a sample user for preview
        mockUserService.loadedUsers[sampleUserId] = UserProfile(
            id: sampleUserId, 
            username: "sampleUser", 
            displayName: "Sample User Display Name", 
            createdAt: Date(), 
            favoriteGames: ["Poker", "Chess"],
            bio: "This is a sample bio for preview purposes. It can be a bit longer to see how it wraps.", 
            avatarURL: nil, // Or a placeholder image URL string
            location: "Sample Location", 
            favoriteGame: "Poker", 
            hyperlinkText: "My Website",
            hyperlinkURL: "https://example.com",
            followersCount: 125, 
            followingCount: 78
        )
        
        return NavigationView {
            UserProfileView(userId: sampleUserId)
                .environmentObject(mockUserService)
                //.environmentObject(PostService()) // If PostService is needed for previewing posts
        }
        .preferredColorScheme(.dark)
    }
} 
