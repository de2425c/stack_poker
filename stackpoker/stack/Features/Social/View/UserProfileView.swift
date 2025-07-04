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
    
    // Loading state for robust profile loading
    @State private var isLoadingProfile: Bool = true
    @State private var loadingAttempt: Int = 1
    
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
            if isLoadingProfile {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                        .scaleEffect(1.5)
                    
                    if loadingAttempt == 1 {
                        Text("Loading profile...")
                            .foregroundColor(.gray)
                            .font(.body)
                    } else {
                        Text("Retrying... (attempt \(loadingAttempt))")
                            .foregroundColor(.gray)
                            .font(.body)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else if let user = userService.loadedUsers[userId] {
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
                    HStack(spacing: 12) {
                        // Stats section - fixed size to prevent wrapping
                        HStack(spacing: 16) {
                            NavigationLink(destination: BasicFollowListView(
                                userId: userId, 
                                listType: .followers, 
                                userName: user.displayName ?? user.username
                            ).environmentObject(userService)) {
                                StatView(count: localFollowersCount, label: "Followers")
                            }
                            .buttonStyle(PlainButtonStyle())
                            .fixedSize()
                            
                            NavigationLink(destination: BasicFollowListView(
                                userId: userId, 
                                listType: .following, 
                                userName: user.displayName ?? user.username
                            ).environmentObject(userService)) {
                                StatView(count: localFollowingCount, label: "Following")
                            }
                            .buttonStyle(PlainButtonStyle())
                            .fixedSize()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        
                        Spacer(minLength: 8)
                        
                        // Action buttons section
                        HStack(spacing: 8) {
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
                                    .fixedSize()
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
                                .fixedSize()

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
                        .fixedSize(horizontal: true, vertical: false)
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
                // Error loading profile
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Error loading profile")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Button("Try again") {
                        Task {
                            await loadUserProfile()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .foregroundColor(.black)
                    .cornerRadius(20)
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
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
                await loadUserProfile()
            }
        }
        .onChange(of: userId) { newUserId in
            // If the userId changes (navigation to different profile), reload
            Task {
                await loadUserProfile()
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
    
    @MainActor
    private func loadUserProfile() async {
        await loadUserProfileWithRetry(attempt: 1)
    }
    
    @MainActor
    private func loadUserProfileWithRetry(attempt: Int) async {
        let maxAttempts = 3
        print("🔄 [UserProfileView] Starting loadUserProfile for userId: \(userId) (attempt \(attempt)/\(maxAttempts))")
        
        // Set loading state
        self.isLoadingProfile = true
        self.loadingAttempt = attempt
        
        // Wait for UserService to be fully initialized
        if !userService.isInitialized {
            print("⏳ [UserProfileView] Waiting for UserService initialization...")
            while !userService.isInitialized {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second checks
            }
            print("✅ [UserProfileView] UserService is now initialized")
        }
        
        // Add delays for stability
        if attempt == 1 {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second initial delay
        } else {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay between retries
        }
        
        // Step 1: ALWAYS fetch the user profile first and wait for completion
        // This ensures we have the profile data before proceeding
        // Force refresh on retries to bypass cache
        await userService.fetchUser(id: userId, forceRefresh: attempt > 1)
        
        // Step 2: Verify we have the profile loaded - this should always succeed now
        guard let profile = userService.loadedUsers[userId] else {
            print("❌ [UserProfileView] Failed to load user profile for userId: \(userId) on attempt \(attempt)")
            
            if attempt < maxAttempts {
                print("🔄 [UserProfileView] Retrying... (attempt \(attempt + 1)/\(maxAttempts))")
                await loadUserProfileWithRetry(attempt: attempt + 1)
                return
            } else {
                print("❌ [UserProfileView] Failed to load profile after \(maxAttempts) attempts")
                self.isLoadingProfile = false
                return
            }
        }
        
        print("✅ [UserProfileView] Successfully loaded profile for user: \(profile.username)")
        
        // Step 3: Initialize local state with profile data
        self.localFollowersCount = profile.followersCount
        self.localFollowingCount = profile.followingCount
        
        // Step 4: Show the profile UI immediately once we have the basic data
        self.isLoadingProfile = false
        
        // Debug: Print hyperlink data
        print("🔗 [UserProfileView] User \(profile.username) hyperlink data:")
        print("   - hyperlinkText: '\(profile.hyperlinkText ?? "nil")'")
        print("   - hyperlinkURL: '\(profile.hyperlinkURL ?? "nil")'")
        
        // Step 5: Now fetch follow state and other data in parallel
        // These can run in parallel since they don't depend on each other
        async let followStateTask: Void = {
            if let currentLoggedInUserId = loggedInUserId {
                let following = await userService.isUserFollowing(targetUserId: userId, currentUserId: currentLoggedInUserId)
                await MainActor.run {
                    self.isFollowing = following
                }
                
                // If following, also fetch post notification preference
                if following {
                    let notificationsEnabled = await userService.getPostNotificationPreference(targetUserId: userId, currentUserId: currentLoggedInUserId)
                    await MainActor.run {
                        self.postNotificationsEnabled = notificationsEnabled
                    }
                }
            }
        }()
        
        async let postsTask: Void = {
            try? await profilePostService.fetchPosts(forUserId: userId)
        }()
        
        async let sessionsTask: Void = {
            try? await fetchUserPublicSessions()
        }()
        
        async let challengesTask: Void = {
            await fetchActiveChallenges()
        }()
        
        // Wait for all parallel tasks to complete
        let _ = await (followStateTask, postsTask, sessionsTask, challengesTask)
        
        print("✅ [UserProfileView] Completed loading all profile data for user: \(profile.username)")
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
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline).bold()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .fixedSize()
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
