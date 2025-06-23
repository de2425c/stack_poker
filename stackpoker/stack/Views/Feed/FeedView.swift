import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import Kingfisher
import MessageUI

struct FeedView: View {
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @StateObject private var handStore: HandStore // Added HandStore
    @StateObject private var sessionStore: SessionStore // Added SessionStore
    @State private var showingNewPost = false
    @State private var isRefreshing = false
    @State private var showingUserSearchView = false
    @State private var selectedPost: Post? = nil
    @State private var showingFullScreenImage = false
    @State private var selectedImageURL: String? = nil
    @State private var showingComments = false
    
    // Global image viewer state
    @State private var viewerImageURL: String? = nil
    
    // Holds the profile to navigate to after search dismisses
    @State private var userIdToOpen: String? = nil
    @State private var navigateToProfile = false
    
    // New state for action buttons
    @State private var showNewHandEntryViewSheet = false
    @State private var showingLiveSession = false
    @State private var showingOpenHomeGameFlow = false
    
    // State for suggested users
    @State private var suggestedUsers: [UserProfile] = []
    @State private var loadingSuggestedUsers = false
    
    let userId: String
    
    // Parameters to track whether bars are showing
    let hasStandaloneGameBar: Bool
    let hasInviteBar: Bool
    let hasLiveSessionBar: Bool
    
    // Optional callback for navigating to explore tab
    let onNavigateToExplore: (() -> Void)?
    
    // Add computed property for dynamic top padding based on bar visibility
    private var dynamicTopPadding: CGFloat {
        // When any top bars are visible, use minimal padding since they provide spacing
        if hasLiveSessionBar || hasStandaloneGameBar || hasInviteBar {
            return 0 // No padding when bars are present - they handle safe area
        } else {
            // When no bars, need padding to account for safe area
            return 55 // Enough padding to clear the safe area and provide proper spacing
        }
    }
    
    init(userId: String = Auth.auth().currentUser?.uid ?? "", hasStandaloneGameBar: Bool = false, hasInviteBar: Bool = false, hasLiveSessionBar: Bool = false, onNavigateToExplore: (() -> Void)? = nil) {
        self.userId = userId
        self.hasStandaloneGameBar = hasStandaloneGameBar
        self.hasInviteBar = hasInviteBar
        self.hasLiveSessionBar = hasLiveSessionBar
        self.onNavigateToExplore = onNavigateToExplore
        _handStore = StateObject(wrappedValue: HandStore(userId: userId)) // Initialize HandStore
        
        // Create bankrollStore first, then pass it to sessionStore
        let bankrollStore = BankrollStore(userId: userId)
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId, bankrollStore: bankrollStore)) // Initialize SessionStore with bankrollStore
        
        // Configure the Kingfisher cache
        let cache = ImageCache.default
        
        // Set memory cache limit correctly as Int
        let memoryCacheMB = 300
        cache.memoryStorage.config.totalCostLimit = memoryCacheMB * 1024 * 1024
        
        // Set disk cache limit (breaking into simpler expressions)
        let diskCacheMB: UInt = 1000
        let diskCacheBytes = diskCacheMB * 1024 * 1024
        cache.diskStorage.config.sizeLimit = diskCacheBytes
    }
    
    var body: some View {
        // Simple ZStack without fixed header - directly show content
        ZStack {
            // Background that fills the entire screen but respects top safe area
            AppBackgroundView(edges: .horizontal) // Changed to .horizontal
                .ignoresSafeArea() 
            
            // Content area - now directly includes the header for scrolling
            contentView // This will now include the header as part of its scrollable content
        }
        // Sheets and modals
        .fullScreenCover(isPresented: $showingNewPost) {
          GeometryReader { geometry in
            PostEditorView(userId: userId)
              .environmentObject(postService)
              .environmentObject(userService)
              .environmentObject(handStore)
              .environmentObject(sessionStore)
              // make it fill the sheet
              .frame(width: geometry.size.width,
                     height: geometry.size.height)
              // now ignores the keyboard entirely
              .ignoresSafeArea(.keyboard)
          }
        }
        .fullScreenCover(isPresented: $showingUserSearchView) {
            UserSearchView(currentUserId: userId,
                           userService: userService,
                           onUserSelected: { id in
                               userIdToOpen = id
                               navigateToProfile = true
                           })
        }
        .fullScreenCover(item: $selectedPost) { post in // Changed from .sheet to .fullScreenCover
            NavigationView {
                PostDetailView(post: post, userId: userId)
                    .environmentObject(postService)
                    .environmentObject(userService)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        // Overlay for full-screen image display (replaces fullScreenCover)
        .overlay(
            Group {
                if showingFullScreenImage, let imageUrl = selectedImageURL {
                    FullScreenImageView(imageURL: imageUrl, onDismiss: { showingFullScreenImage = false })
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
        )
        // Global image viewer for all post images
        .fullScreenCover(item: $viewerImageURL) { url in
            FullScreenImageView(imageURL: url, onDismiss: { viewerImageURL = nil })
        }
        // Push profile once search sheet closes and `userIdToOpen` is set
        .background(
            NavigationLink(
                destination: Group {
                    if let id = userIdToOpen {
                        UserProfileView(userId: id)
                            .environmentObject(userService)
                            .environmentObject(postService)
                    }
                },
                isActive: $navigateToProfile,
                label: { EmptyView() }
            )
            .hidden()
        )
        // New sheet presentations for action buttons
        .sheet(isPresented: $showNewHandEntryViewSheet) {
            NewHandEntryView()
        }
        .fullScreenCover(isPresented: $showingLiveSession) {
            EnhancedLiveSessionView(userId: userId, sessionStore: sessionStore)
        }
        .sheet(isPresented: $showingOpenHomeGameFlow) {
            HomeGameView(groupId: nil, onGameCreated: { _ in
                showingOpenHomeGameFlow = false
            })
            .environmentObject(userService)
        }
        .onAppear {
            // Load posts when the view appears - but only if we don't have recent data
            if postService.posts.isEmpty || shouldRefreshFeed() {
                // Pre-mark as loading to avoid flashing empty state
                postService.isLoading = true
                Task {
                    try? await postService.fetchPosts()
                }
            }
            // Ensure user profile is loaded for the avatar
            if userService.currentUserProfile == nil {
                Task {
                    try? await userService.fetchUserProfile()
                }
            }
            
            // Load suggested users for both empty state and feed injection
            loadSuggestedUsers()
            print("DEBUG: Loading suggested users on appear")
            
            // Add observer for following changes to refresh suggested users
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UserFollowingChanged"),
                object: nil,
                queue: .main
            ) { _ in
                loadSuggestedUsers() // Refresh suggested users when following changes
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh feed and suggested users when app becomes active
            Task {
                try? await postService.forceRefresh()
                loadSuggestedUsers() // Refresh suggested users too
            }
        }
        .ignoresSafeArea(.keyboard) // Prevent keyboard from resizing view
        .onDisappear {
            // Clean up notification observers
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("UserFollowingChanged"), object: nil)
        }
    }
    
    // MARK: - Content View
    private var contentView: some View {
        Group {
            if postService.isLoading && postService.posts.isEmpty {
                // Loading state with header visible
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        // Add the same top spacing as the loaded feed
                        Spacer().frame(height: dynamicTopPadding)
                        
                        // Header should be in the same position as when loaded
                        feedHeader()

                        Spacer()

                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)

                            Text("Loading Feed")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if postService.posts.isEmpty {
                // Empty feed state
                ScrollView { 
                    VStack(spacing: 0) {
                        Spacer().frame(height: dynamicTopPadding)
                        // Top spacer removed
                        feedHeader() // Add header here
                        
                        // Enhanced empty feed content - Strava-style post cards
                        LazyVStack(spacing: 0) {
                            Spacer().frame(height: 20)
                            
                            // Record Activity Post Card
                            RecordActivityPostCard(
                                onLiveSessionTapped: { showingLiveSession = true },
                                onHostHomeGameTapped: { 
                                    showingOpenHomeGameFlow = true
                                },
                                onExploreEventsTapped: { 
                                    onNavigateToExplore?() 
                                }
                            )
                            
                            // Divider between cards
                            Divider()
                                .frame(height: 0.5)
                                .background(Color.white.opacity(0.1))
                            
                            // Suggested Users Post Card
                            SuggestedUsersPostCard(
                                users: Array(suggestedUsers.prefix(3)), // Show fewer users in feed
                                isLoading: loadingSuggestedUsers,
                                userId: userId,
                                onUserTapped: { selectedUserId in
                                    userIdToOpen = selectedUserId
                                    navigateToProfile = true
                                },
                                onUserFollowed: {
                                    // Refresh suggested users after following
                                    loadSuggestedUsers()
                                    
                                    // Force refresh the feed to show new content
                                    Task {
                                        try? await postService.forceRefresh()
                                    }
                                }
                            )
                            .environmentObject(userService)
                            
                            Spacer().frame(height: 40)
                        }
                    }
                }
            } else {
                // Twitter-like feed with posts
                feedContent // This will now include the header
            }
        }
    }

    // Extracted Header View
    @ViewBuilder
    private func feedHeader() -> some View {
        VStack(spacing: 0) {
            // Removed top Spacer().frame(height: 45) as the header is now part of scroll content
            
            HStack(spacing: 0) { // Main HStack for the bar
                // Profile Picture and Search Icon (Left Aligned Group)
                HStack(spacing: 12) {
                    if let profile = userService.currentUserProfile {
                        // Profile picture with navigation to current user's profile
                        NavigationLink(destination: UserProfileView(userId: userId).environmentObject(userService).environmentObject(postService)) {
                            Group {
                                if let avatarURLString = profile.avatarURL, let avatarURL = URL(string: avatarURLString) {
                                    KFImage(avatarURL)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 36, height: 36)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                } else {
                                    PlaceholderAvatarView(size: 36)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Placeholder if profile is not loaded
                        PlaceholderAvatarView(size: 36)
                    }

                    Button(action: {
                        showingUserSearchView = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

                // Centered Stack Logo
                Image("stack_logo") 
                    .resizable()
                    .renderingMode(.template) // Assuming you want to color it
                    .foregroundColor(.white)   // Color set to white
                    .scaledToFit()
                    .frame(height: 35)      // User updated height

                // Write Post (Right Aligned)
                HStack {
                    Spacer()
                    Button(action: {
                        showingNewPost = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white) // Changed from green to white
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
            }
            .frame(height: 44) // Set a fixed height for the HStack
            .padding(.vertical, 8) // Add some vertical padding
            .background(Color.clear) 
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.7)) // This was the previous color for the bottom divider
                .frame(height: 2)
                // .shadow(color: Color.black.opacity(0.3), radius: 1, y: 1) // Optional shadow
        }
        // Removed .safeAreaInset as this is now part of the scrollable content
    }
    
    // MARK: - Feed Content
    private var feedContent: some View {
        ZStack { 
            // The StackLogo watermark is fine here if it should be behind all content
            Image("StackLogo") 
                .resizable()
                .scaledToFit()
                .frame(width: 100) 
                .opacity(0.1) 

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) { 
                    Spacer().frame(height: dynamicTopPadding)
                    // Top spacer removed
                    feedHeader() // Header is now the first item in LazyVStack

                    // Quick Actions Card at the top of feed
                    VStack(spacing: 0) {
                        RecordActivityPostCard(
                            onLiveSessionTapped: { showingLiveSession = true },
                            onHostHomeGameTapped: { 
                                showingOpenHomeGameFlow = true
                            },
                            onExploreEventsTapped: { 
                                onNavigateToExplore?() 
                            }
                        )
                        .background(
                            // Subtle highlight background
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.02),
                                    Color.white.opacity(0.01)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        Divider()
                            .frame(height: 0.5)
                            .background(Color.white.opacity(0.1))
                    }
                    
                    ForEach(0..<postService.posts.count, id: \.self) { index in
                        let post = postService.posts[index]
                        
                        // Insert suggestion card BEFORE certain posts
                        if shouldShowSuggestedContent(at: index) {
                            let _ = print("DEBUG: Should show content at index \(index), suggestedUsers.count: \(suggestedUsers.count)")
                            VStack(spacing: 0) {
                                // Add a subtle background to make it stand out
                                VStack(spacing: 0) {
                                    // Alternate between card types based on position
                                    let cardPosition = (index / 5)
                                    let _ = print("DEBUG: Card position: \(cardPosition), isEven: \(cardPosition % 2 == 0)")
                                    
                                    if cardPosition % 2 == 0 {
                                        // Even positions (0, 2, 4...) show Record Activity
                                        RecordActivityPostCard(
                                            onLiveSessionTapped: { showingLiveSession = true },
                                            onHostHomeGameTapped: { 
                                                showingOpenHomeGameFlow = true
                                            },
                                            onExploreEventsTapped: { 
                                                onNavigateToExplore?() 
                                            }
                                        )
                                    } else {
                                        // Odd positions (1, 3, 5...) show Suggested Users
                                        if !suggestedUsers.isEmpty {
                                            SuggestedUsersPostCard(
                                                users: Array(suggestedUsers.prefix(3)), // Show fewer users in feed
                                                isLoading: loadingSuggestedUsers,
                                                userId: userId,
                                                onUserTapped: { selectedUserId in
                                                    userIdToOpen = selectedUserId
                                                    navigateToProfile = true
                                                },
                                                onUserFollowed: {
                                                    // Refresh suggested users after following
                                                    loadSuggestedUsers()
                                                    
                                                    // Force refresh the feed to show new content
                                                    Task {
                                                        try? await postService.forceRefresh()
                                                    }
                                                }
                                            )
                                            .environmentObject(userService)
                                        } else {
                                            // Fallback to Record Activity if no suggested users
                                            RecordActivityPostCard(
                                                onLiveSessionTapped: { showingLiveSession = true },
                                                onHostHomeGameTapped: { 
                                                    showingOpenHomeGameFlow = true
                                                },
                                                onExploreEventsTapped: { 
                                                    onNavigateToExplore?() 
                                                }
                                            )
                                        }
                                    }
                                }
                                .background(
                                    // Subtle highlight background
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.02),
                                            Color.white.opacity(0.01)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                
                                Divider()
                                    .frame(height: 0.5)
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                        
                        // Show the actual post
                        VStack(spacing: 0) {
                            PostCardView(
                                post: post,
                                onLike: {
                                    Task {
                                        do {
                                            try await postService.toggleLike(postId: post.id ?? "", userId: userId)
                                        } catch {

                                        }
                                    }
                                },
                                onComment: {
                                    selectedPost = post
                                    showingComments = true
                                },
                                isCurrentUser: post.userId == userId,
                                userId: userId
                            )
                            Divider() 
                                .frame(height: 0.5) 
                                .background(Color.white.opacity(0.1)) 
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPost = post
                        }
                        .onAppear {
                            // Load more posts when reaching the end
                            if post.id == postService.posts.last?.id {
                                Task {
                                    try? await postService.fetchMorePosts()
                                }
                            }
                        }
                    }
                    
                    Spacer().frame(height: 20)
                }
            }
            // .refreshable is fine on ScrollView
            .refreshable {
                await refreshFeed()
            }
            .edgesIgnoringSafeArea(.horizontal) // This is okay for horizontal scroll content
        }
    }
    
    // Refresh the feed
    private func refreshFeed() async {
        isRefreshing = true
        try? await postService.forceRefresh() // Use forceRefresh to bypass cache
        isRefreshing = false
    }
    
    // Check if feed should be refreshed based on last activity
    private func shouldRefreshFeed() -> Bool {
        // Always refresh if no posts
        guard !postService.posts.isEmpty else { return true }
        
        // If we have posts but they're more than 5 minutes old, refresh for better real-time updates
        if let firstPost = postService.posts.first,
           Date().timeIntervalSince(firstPost.createdAt) > 300 {
            return true
        }
        
        return false
    }
    
    // Handle like action
    private func likePost(_ post: Post) {
        Task {
            do {
                if let postId = post.id {
                    try await postService.toggleLike(postId: postId, userId: userId)
                }
            } catch {

            }
        }
    }
    
    // Add deletePost function
    private func deletePost(_ post: Post) {
        Task {
            do {
                if let postId = post.id {

                    try await postService.deletePost(postId: postId)

                    // Refresh feed after deletion
                    try await postService.fetchPosts()
                } else {

                }
            } catch {

            }
        }
    }
    
    // Load suggested users function
    private func loadSuggestedUsers() {
        loadingSuggestedUsers = true
        Task {
            do {
                let users = try await userService.fetchSuggestedUsers(limit: 5)
                await MainActor.run {
                    suggestedUsers = users
                    loadingSuggestedUsers = false
                }
            } catch {
                await MainActor.run {
                    loadingSuggestedUsers = false
                }
            }
        }
    }
    
    // Helper function to determine when to show suggested content
    private func shouldShowSuggestedContent(at index: Int) -> Bool {
        // Show every 7 posts starting from index 6 (7th post)
        // This creates pattern: posts 0-6, then suggestion, posts 7-13, then suggestion, etc.
        let shouldShow = (index > 0) && ((index % 7) == 0)
        print("DEBUG: Index \(index), shouldShow: \(shouldShow)")
        return shouldShow
    }
}

// Add the new PostContextTagView struct here
private struct PostContextTagView: View {
    let title: String
    let iconName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundColor(isChallenge ? .yellow : Color.gray.opacity(0.8))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isChallenge ? .yellow : Color.gray.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isChallenge ? .yellow.opacity(0.8) : Color.gray.opacity(0.8))
            Spacer()
        }
        .padding(.bottom, 8) // Add some space below this tag
    }
    
    private var isChallenge: Bool {
        return title.contains("Challenge") || iconName == "flag.fill"
    }
}

// Update BasicPostCardView with the optimized layout
struct BasicPostCardView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let isCurrentUser: Bool
    var onImageTapped: ((String) -> Void)?
    var openPostDetail: (() -> Void)?
    var onReplay: (() -> Void)?
    @State private var isLiked: Bool
    @State private var animateLike = false
    @EnvironmentObject private var userService: UserService // Added to pass along to destination view

    init(post: Post, onLike: @escaping () -> Void, onComment: @escaping () -> Void, onDelete: @escaping () -> Void, isCurrentUser: Bool, onImageTapped: ((String) -> Void)? = nil, openPostDetail: (() -> Void)? = nil, onReplay: (() -> Void)? = nil) {
        self.post = post
        self.onLike = onLike
        self.onComment = onComment
        self.onDelete = onDelete
        self.isCurrentUser = isCurrentUser
        self.onImageTapped = onImageTapped
        self.openPostDetail = openPostDetail
        self.onReplay = onReplay
        _isLiked = State(initialValue: post.isLiked)
    }

    // Computed property for context tag information
    private var contextTagInfo: (title: String, iconName: String)? {
        let iconName = "rectangle.stack.fill"
        var tempTitle: String? // Use a temporary variable to build the core title

        // Check for challenge posts first
        if let challengeStatus = challengeStatusText(post.content) {
            return (challengeStatus, "flag.fill")
        }

        // Initial debug prints




        if post.postType == .hand, let hand = post.handHistory {

            let smallBlind = hand.raw.gameInfo.smallBlind
            let bigBlind = hand.raw.gameInfo.bigBlind
            if bigBlind > 0 || smallBlind > 0 {
                let stakesString = String(format: "$%g/$%g", smallBlind, bigBlind)
                tempTitle = "Playing \(stakesString)"
            }
        } else if post.content.starts(with: "Started a new session at ") {

            let relevantContent = String(post.content.dropFirst("Started a new session at ".count))
            if let lastParenOpen = relevantContent.lastIndex(of: "("),
               let lastParenClose = relevantContent.lastIndex(of: ")"),
               lastParenOpen < lastParenClose,
               relevantContent.index(after: lastParenClose) == relevantContent.endIndex {
                
                let gamePart = String(relevantContent[..<lastParenOpen]).trimmingCharacters(in: .whitespaces)
                let stakesPart = String(relevantContent[relevantContent.index(after: lastParenOpen)..<lastParenClose]).trimmingCharacters(in: .whitespaces)

                if !gamePart.isEmpty {
                    tempTitle = "Playing \(gamePart)"
                    if !stakesPart.isEmpty {
                        tempTitle! += " (\(stakesPart))"
                    }
                }
            } else if !relevantContent.isEmpty {
                let gamePart = relevantContent.trimmingCharacters(in: .whitespaces)

                if !gamePart.isEmpty {
                    tempTitle = "Playing \(gamePart)"
                }
            }
        } else {

            let (completedOpt, _) = parseCompletedSessionInfo(from: post.content)
            if let completed = completedOpt {

                if !completed.gameName.isEmpty && completed.gameName != "N/A" {
                    tempTitle = "Playing \(completed.gameName)"
                    if !completed.stakes.isEmpty && completed.stakes != "N/A" {
                        tempTitle! += " (\(completed.stakes))"
                    }
                } else if !completed.stakes.isEmpty && completed.stakes != "N/A" {
                    tempTitle = "Playing \(completed.stakes)"
                }
            } else {

                let sessionInfoTuple = extractSessionInfo(from: post.content)
                let gameNameFromInfo = sessionInfoTuple.0
                let stakesFromInfo = sessionInfoTuple.1


                if let game = gameNameFromInfo, !game.isEmpty {
                    tempTitle = "Playing \(game)"
                    if let stakes = stakesFromInfo, !stakes.isEmpty {
                        tempTitle! += " (\(stakes))"
                    }
                } else if let stakes = stakesFromInfo, !stakes.isEmpty {
                    tempTitle = "Playing \(stakes)"
                }

                if tempTitle == nil && post.sessionId != nil {

                    if let parsed = parseSessionContent(from: post.content) {

                        if !parsed.gameName.isEmpty {
                            tempTitle = "Playing \(parsed.gameName)"
                            if !parsed.stakes.isEmpty {
                                tempTitle! += " (\(parsed.stakes))"
                            }
                        } else if !parsed.stakes.isEmpty {
                            tempTitle = "Playing \(parsed.stakes)"
                        }
                    } else if post.content.lowercased().starts(with: "playing ") {

                        if let firstLine = post.content.components(separatedBy: "\n").first {
                             let trimmedTitle = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                             if !trimmedTitle.isEmpty {
                                tempTitle = trimmedTitle
                             }
                        }
                    }
                }
            }
        }

        // Append location if a title was formed and location exists
        if var title = tempTitle, let loc = post.location, !loc.isEmpty {
            // Avoid appending "at location" if the title *already* contains "at location" from "Playing ... at location"
            if !(title.lowercased().starts(with: "playing ") && title.lowercased().contains(" at \(loc.lowercased())")) {
                 if !title.lowercased().contains(" at ") { // general check to avoid double "at"
                    title += " at \(loc)"
                 }
            }
            tempTitle = title
        }
        
        if let finalTitle = tempTitle {

            return (finalTitle, iconName)
        }
        

        return nil
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Use the computed property to display the tag
                if let tagInfo = contextTagInfo {
                    PostContextTagView(title: tagInfo.title, iconName: tagInfo.iconName)
                        .padding(.horizontal, 16)
                        .padding(.top, 10) // Added top padding for the tag view
                }
                
                // Header with user info & optional delete button
                HStack(alignment: .top, spacing: 10) {
                    // Smaller profile image with navigation to public profile
                    NavigationLink(destination: UserProfileView(userId: post.userId).environmentObject(userService)) {
                        Group {
                            if let profileImage = post.profileImage {
                                KFImage(URL(string: profileImage))
                                    .placeholder {
                                        PlaceholderAvatarView(size: 40)
                                    }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            } else {
                                PlaceholderAvatarView(size: 40)
                            }
                        }
                    }
                    
                    // User info (username, etc.)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .center, spacing: 4) {
                            Text(post.displayName ?? post.username)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                
                            Text("@\(post.username)")
                                .font(.system(size: 13))
                                .foregroundColor(.gray.opacity(0.8))
                        }
                        
                        Text(post.createdAt.timeAgo())
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                // Adjust top padding based on tag presence
                .padding(.top, contextTagInfo == nil ? 14 : 6) 
                .padding(.bottom, 8)
                
                // Check for Completed Session Info FIRST
                let (parsedCompletedSessionInfo, remainingContentForCompletedSession) = parseCompletedSessionInfo(from: post.content)

                if let completedSession = parsedCompletedSessionInfo {
                    CompletedSessionFeedCardView(sessionInfo: completedSession)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    if !remainingContentForCompletedSession.isEmpty {
                        Text(remainingContentForCompletedSession)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 6) // Adjusted padding
                            .padding(.bottom, 8)
                    }
                } else if post.isNote { // Check for notes BEFORE session ID check for chip updates
                    let cleanedContent = cleanContentForNoteDisplay(post.content)
                    NoteCardView(noteText: cleanedContent)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                } else if post.postType == .hand {
                    if let hand = post.handHistory {
                        HandSummaryView(hand: hand, showReplayButton: false)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                    if let handComment = extractCommentContent(from: post.content), !handComment.isEmpty {
                        Text(handComment)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, post.handHistory != nil ? 4 : 14)
                            .padding(.bottom, 8)
                    }
                } else if post.sessionId != nil { // Live session posts (chip updates or start)
                    if let parsed = parseSessionContent(from: post.content) {
                        if parsed.elapsedTime == 0 && parsed.buyIn > 0 { // Condition for "Session Started"
                            SessionStartedCardView(
                                gameName: parsed.gameName,
                                stakes: parsed.stakes,
                                location: post.location, // PostContextTagView also shows this, but card can too if desired
                                buyIn: parsed.buyIn,
                                userComment: parsed.actualContent
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        } else { // Regular chip update
                            LiveStackUpdateCardView(parsedContent: parsed)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    } else { // Fallback for session posts that don't parse with parseSessionContent
                        Text(post.content)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                    }
                } else if !post.content.isEmpty { // Regular text posts
                    // Use the unified challenge parser
                    if let challengeDisplayModel = ChallengePostParser.parse(post.content) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Extract and show user comment if any
                            if let userComment = ChallengePostParser.extractUserComment(post.content), !userComment.isEmpty {
                                Text(userComment)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 6)
                                    .padding(.bottom, 8)
                            }

                            // Display the challenge progress component using the display model
                            ChallengeProgressComponent(
                                challenge: challengeDisplayModel.challenge,
                                isCompact: true // Use compact for the feed
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    } else {
                        Text(post.content)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 6) // Reduced from 14 to bring comment closer to top
                            .padding(.bottom, 8)
                    }
                }
                
                // Images - Square display with side padding
                if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(imageURLs, id: \.self) { url in
                            if let imageUrl = URL(string: url) {
                                KFImage(imageUrl)
                                    .placeholder {
                                        Rectangle()
                                            .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                                            .overlay(
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                            )
                                    }
                                    .resizable()
                                    .scaledToFill()
                                    .aspectRatio(1, contentMode: .fill) // Square aspect ratio
                                    .clipped() // Crop to square
                                    .cornerRadius(8) // Add slight rounding
                                    .contentShape(Rectangle()) // Ensure the whole area is tappable
                                    .onTapGesture {
                                        onImageTapped?(url)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 16) // Add side padding
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                
                // Twitter-like actions bar
                HStack(spacing: 36) {
                    // Like Button (Moved to be first)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            animateLike = true
                            isLiked.toggle()
                            onLike()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                animateLike = false
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundColor(isLiked ? .red : .gray.opacity(0.7))
                                .scaleEffect(animateLike ? 1.3 : 1.0)
                            
                            Text("\(post.likes)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    }
                    
                    // Comment Button (Moved to be second)
                    Button(action: {
                        if let postDetailAction = openPostDetail {
                            postDetailAction()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 16))
                                .foregroundColor(.gray.opacity(0.7))
                            
                            Text("\(post.comments)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    }
                    
                    if post.postType == .hand {
                        Button(action: { 
                            if let onReplay = onReplay {
                                onReplay()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 16))
                                Text("Replay")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)))
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color.clear) // Modified for transparency
            .cornerRadius(0) // Modified for transparency
            
            // Make the entire cell tappable
            if let postDetailAction = openPostDetail {
                Button(action: {
                    postDetailAction()
                }) {
                    Rectangle()
                        .fill(Color.clear)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// Update PostCardView to match the optimized BasicPostCardView
struct PostCardView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let isCurrentUser: Bool
    let userId: String
    @State private var showingReplay = false
    @State private var isLiked: Bool
    @State private var animateLike = false
    @EnvironmentObject private var userService: UserService // Added env object for navigation
    
    init(post: Post, onLike: @escaping () -> Void, onComment: @escaping () -> Void, isCurrentUser: Bool, userId: String) {
        self.post = post
        self.onLike = onLike
        self.onComment = onComment
        self.isCurrentUser = isCurrentUser
        self.userId = userId
        _isLiked = State(initialValue: post.isLiked)
    }
    
    // Computed property for context tag information
    private var contextTagInfo: (title: String, iconName: String)? {
        let iconName = "rectangle.stack.fill"
        var tempTitle: String? // Use a temporary variable to build the core title

        // Check for challenge posts first
        if let challengeStatus = challengeStatusText(post.content) {
            return (challengeStatus, "flag.fill")
        }

        // Initial debug prints




        if post.postType == .hand, let hand = post.handHistory {

            let smallBlind = hand.raw.gameInfo.smallBlind
            let bigBlind = hand.raw.gameInfo.bigBlind
            if bigBlind > 0 || smallBlind > 0 {
                let stakesString = String(format: "$%g/$%g", smallBlind, bigBlind)
                tempTitle = "Playing \(stakesString)"
            }
        } else if post.content.starts(with: "Started a new session at ") {

            let relevantContent = String(post.content.dropFirst("Started a new session at ".count))
            if let lastParenOpen = relevantContent.lastIndex(of: "("),
               let lastParenClose = relevantContent.lastIndex(of: ")"),
               lastParenOpen < lastParenClose,
               relevantContent.index(after: lastParenClose) == relevantContent.endIndex {
                
                let gamePart = String(relevantContent[..<lastParenOpen]).trimmingCharacters(in: .whitespaces)
                let stakesPart = String(relevantContent[relevantContent.index(after: lastParenOpen)..<lastParenClose]).trimmingCharacters(in: .whitespaces)

                if !gamePart.isEmpty {
                    tempTitle = "Playing \(gamePart)"
                    if !stakesPart.isEmpty {
                        tempTitle! += " (\(stakesPart))"
                    }
                }
            } else if !relevantContent.isEmpty {
                let gamePart = relevantContent.trimmingCharacters(in: .whitespaces)

                if !gamePart.isEmpty {
                    tempTitle = "Playing \(gamePart)"
                }
            }
        } else {

            let (completedOpt, _) = parseCompletedSessionInfo(from: post.content)
            if let completed = completedOpt {

                if !completed.gameName.isEmpty && completed.gameName != "N/A" {
                    tempTitle = "Playing \(completed.gameName)"
                    if !completed.stakes.isEmpty && completed.stakes != "N/A" {
                        tempTitle! += " (\(completed.stakes))"
                    }
                } else if !completed.stakes.isEmpty && completed.stakes != "N/A" {
                    tempTitle = "Playing \(completed.stakes)"
                }
            } else {

                let sessionInfoTuple = extractSessionInfo(from: post.content)
                let gameNameFromInfo = sessionInfoTuple.0
                let stakesFromInfo = sessionInfoTuple.1


                if let game = gameNameFromInfo, !game.isEmpty {
                    tempTitle = "Playing \(game)"
                    if let stakes = stakesFromInfo, !stakes.isEmpty {
                        tempTitle! += " (\(stakes))"
                    }
                } else if let stakes = stakesFromInfo, !stakes.isEmpty {
                    tempTitle = "Playing \(stakes)"
                }

                if tempTitle == nil && post.sessionId != nil {

                    if let parsed = parseSessionContent(from: post.content) {

                        if !parsed.gameName.isEmpty {
                            tempTitle = "Playing \(parsed.gameName)"
                            if !parsed.stakes.isEmpty {
                                tempTitle! += " (\(parsed.stakes))"
                            }
                        } else if !parsed.stakes.isEmpty {
                            tempTitle = "Playing \(parsed.stakes)"
                        }
                    } else if post.content.lowercased().starts(with: "playing ") {

                        if let firstLine = post.content.components(separatedBy: "\n").first {
                            let trimmedTitle = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedTitle.isEmpty {
                               tempTitle = trimmedTitle
                            }
                        }
                    }
                }
            }
        }

        // Append location if a title was formed and location exists
        if var title = tempTitle, let loc = post.location, !loc.isEmpty {
             if !(title.lowercased().starts(with: "playing ") && title.lowercased().contains(" at \(loc.lowercased())")) {
                 if !title.lowercased().contains(" at ") {
                    title += " at \(loc)"
                 }
            }
            tempTitle = title
        }
        
        if let finalTitle = tempTitle {

            return (finalTitle, iconName)
        }
        

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use the computed property to display the tag
            if let tagInfo = contextTagInfo {
                PostContextTagView(title: tagInfo.title, iconName: tagInfo.iconName)
                    .padding(.horizontal, 16)
                    .padding(.top, 10) // Added top padding for the tag view
            }

            // Header with user info & optional delete button
            HStack(alignment: .top, spacing: 10) {
                // Smaller profile image with navigation to public profile
                NavigationLink(destination: UserProfileView(userId: post.userId).environmentObject(userService)) {
                    Group {
                        if let profileImage = post.profileImage {
                            KFImage(URL(string: profileImage))
                                .placeholder {
                                    PlaceholderAvatarView(size: 40)
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        } else {
                            PlaceholderAvatarView(size: 40)
                        }
                    }
                }
                
                // User info (username, etc.)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 4) {
                        Text(post.displayName ?? post.username)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            
                        Text("@\(post.username)")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    
                    Text(post.createdAt.timeAgo())
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            // Adjust top padding based on tag presence
            .padding(.top, contextTagInfo == nil ? 14 : 6)
            .padding(.bottom, 8)
            
            // Check for Completed Session Info FIRST
            let (parsedCompletedSessionInfo, remainingContentForCompletedSession) = parseCompletedSessionInfo(from: post.content)

            if let completedSession = parsedCompletedSessionInfo {
                CompletedSessionFeedCardView(sessionInfo: completedSession)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8) // Add consistent padding
                if !remainingContentForCompletedSession.isEmpty {
                    Text(remainingContentForCompletedSession)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 6) // Adjusted padding
                        .padding(.bottom, 8)
                }
            } else if post.isNote { // Check for notes BEFORE session ID check for chip updates
                let cleanedContent = cleanContentForNoteDisplay(post.content)
                NoteCardView(noteText: cleanedContent)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else if post.postType == .hand {
                if let hand = post.handHistory {
                     HandDisplayCardView(hand: hand,
                                         onReplayTap: { showingReplay = true },
                                         location: post.location,
                                         createdAt: post.createdAt,
                                         showReplayInFeed: true)
                }
                if let handComment = extractCommentContent(from: post.content), !handComment.isEmpty {
                    Text(handComment)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, post.handHistory != nil ? 4 : 14)
                        .padding(.bottom, 8)
                }
            } else if post.sessionId != nil { // Live session posts (chip updates or start)
                if let parsed = parseSessionContent(from: post.content) {
                    if parsed.elapsedTime == 0 && parsed.buyIn > 0 { // Condition for "Session Started"
                        SessionStartedCardView(
                            gameName: parsed.gameName,
                            stakes: parsed.stakes,
                            location: post.location,
                            buyIn: parsed.buyIn,
                            userComment: parsed.actualContent
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    } else { // Regular chip update
                        LiveStackUpdateCardView(parsedContent: parsed)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                } else { // Fallback for session posts that don't parse with parseSessionContent
                    Text(post.content)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                }
            } else if !post.content.isEmpty { // Regular text posts
                // Use the unified challenge parser
                if let challengeDisplayModel = ChallengePostParser.parse(post.content) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Extract and show user comment if any
                        if let userComment = ChallengePostParser.extractUserComment(post.content), !userComment.isEmpty {
                            Text(userComment)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.95))
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 8)
                        }

                        // Display the challenge progress component using the display model
                        ChallengeProgressComponent(
                            challenge: challengeDisplayModel.challenge,
                            isCompact: true // Use compact for the feed
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                } else {
                    Text(post.content)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 6) // Reduced from 14 to bring comment closer to top
                        .padding(.bottom, 8)
                }
            }
            
            // Images - Square display with side padding
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(imageURLs, id: \.self) { url in
                        if let imageUrl = URL(string: url) {
                            KFImage(imageUrl)
                                .placeholder {
                                    Rectangle()
                                        .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                                        .overlay(
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                        )
                                }
                                .resizable()
                                .scaledToFill()
                                .aspectRatio(1, contentMode: .fill) // Square aspect ratio
                                .clipped() // Crop to square
                                .cornerRadius(8) // Add slight rounding
                                .contentShape(Rectangle()) // Ensure the whole area is tappable
                                // PostCardView doesn't handle image taps
                        }
                    }
                }
                .padding(.horizontal, 16) // Add side padding
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            
            // Twitter-like actions bar
            HStack(spacing: 36) {
                // Like Button (Moved to be first)
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        animateLike = true
                        isLiked.toggle()
                        onLike()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            animateLike = false
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(isLiked ? .red : .gray.opacity(0.7))
                            .scaleEffect(animateLike ? 1.3 : 1.0)
                        
                        Text("\(post.likes)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                // Comment Button (Moved to be second)
                Button(action: onComment) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Text("\(post.comments)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                if post.postType == .hand {
                    Button(action: { showingReplay = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 16))
                            Text("Replay")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.clear) 
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand, userId: userId)
            }
        }
    }

    // Determine challenge status for this post
    private func challengeStatusText(_ content: String) -> String? {
        if content.contains("🎯 Started a new challenge") {
            return "Challenge Started"
        } else if content.contains("🎯 Challenge Update") {
            return "Challenge Update"
        } else if content.contains("🎉 Session Challenge Completed") || content.contains("🎉 Challenge Completed") {
            return "Challenge Completed"
        }
        return nil
    }
}

// Empty Feed View
struct EmptyFeedView: View {
    let onFindPlayersTapped: () -> Void // Renamed from showDiscoverUsers
    @State private var animateGlow = false
    
    var body: some View {
        ZStack {
            // Additional background elements
            VStack {
                Spacer()
                HStack {
                    // Floating cards in the background
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.03))
                            .frame(width: 120, height: 180)
                            .rotationEffect(.degrees(Double(index * 15 - 15)))
                            .offset(x: CGFloat(index * 40 - 40), y: CGFloat(index * 10))
                            .blur(radius: 2)
                    }
                }
                .offset(y: 120)
                Spacer()
            }
            
            VStack(spacing: 40) {
                Spacer()
                
                // Enhanced empty state icon with animation
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.2)))
                        .frame(width: 160, height: 160)
                        .scaleEffect(animateGlow ? 1.1 : 0.9)
                        .opacity(animateGlow ? 0.6 : 0.3)
                        .blur(radius: 30)
                    
                    Circle()
                        .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.1)))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: "newspaper")
                        .font(.system(size: 70))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)))
                }
                .shadow(color: Color.black.opacity(0.2), radius: 10)
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        animateGlow = true
                    }
                }
                
                VStack(spacing: 12) {
                    Text("Your feed is empty")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Follow other players or create a post to\nstart seeing content here")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
                
                Button(action: onFindPlayersTapped) { // Updated action
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18))
                        
                        Text("Find Players")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 40)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)),
                                Color(UIColor(red: 100/255, green: 230/255, blue: 85/255, alpha: 1.0))
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.4)), radius: 8, y: 3)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 16)
                
                Spacer()
            }
            .padding(32)
        }
    }
}

// Post Detail View
struct PostDetailView: View {
    let post: Post
    let userId: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @State private var showingReplay = false
    @State private var isLiked: Bool
    @State private var animateLike = false
    
    // Comment-related state
    @State private var comments: [Comment] = []
    @State private var replies: [String: [Comment]] = [:]
    @State private var isLoadingReplies: [String: Bool] = [:]
    @State private var replyingToComment: Comment? = nil
    @State private var commentToExpandReplies: Comment? = nil

    @State private var newCommentText = ""
    @State private var isLoadingComments = true
    @State private var showDeleteConfirm = false
    @FocusState private var isCommentFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0 // Added for manual keyboard handling
    @State private var showFlaggedAlert = false
    
    // Global image viewer state for this detail view
    @State private var viewerImageURL: String? = nil
    
    init(post: Post, userId: String) {
        self.post = post
        self.userId = userId
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        // REMOVED NavigationView from here
        GeometryReader { _ in
            ZStack { 
                AppBackgroundView().ignoresSafeArea() 

                // Main content layout (Header and ScrollView)
                VStack(spacing: 0) {
                    // Top header bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.25)))
                        }
                        Spacer()
                        // Report button
                        Button(action: { showFlaggedAlert = true }) {
                            Image(systemName: "flag")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.25)))
                        }

                        if post.userId == userId { // Keep delete button logic
                            Button(action: { showDeleteConfirm = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(12)
                                    .background(Circle().fill(Color.black.opacity(0.25)))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .background(Color.clear) 

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) { 
                            postHeaderAndBody 
                            postActionsAndComments 
                        }
                        .padding(.bottom, 70) 
                    }
                }
            } 
            .overlay( 
                VStack(spacing:0) {
                    Spacer() 
                    commentInputView
                        .padding(.bottom, keyboardHeight) // Fixed: Remove extra padding to make input bar flush with bottom
                        .animation(.easeInOut(duration: 0.25), value: keyboardHeight)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                , alignment: .bottom
            )
        } 
        .ignoresSafeArea(.keyboard)
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePost()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onTapGesture {
            isCommentFieldFocused = false
        }
        // Global image viewer using .fullScreenCover
        .fullScreenCover(item: $viewerImageURL) { imageURL in
            FullScreenImageView(imageURL: imageURL, onDismiss: { viewerImageURL = nil })
        }
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand, userId: userId)
            }
        }
        .alert("Flagged for Review", isPresented: $showFlaggedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This post has been flagged for review.")
        }
        .onAppear {
            loadComments()
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                self.keyboardHeight = keyboardFrame.height
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                self.keyboardHeight = 0
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }
    
    // Extracted ViewBuilder for Post Header and Body
    @ViewBuilder
    private var postHeaderAndBody: some View {
        // Post header with enhanced profile image
        HStack(spacing: 12) {
            // Profile image - Clickable to navigate to user profile
            NavigationLink(destination: UserProfileView(userId: post.userId).environmentObject(userService)) {
                Group {
                    if let profileImage = post.profileImage {
                        KFImage(URL(string: profileImage))
                            .placeholder {
                                PlaceholderAvatarView(size: 50)
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    } else {
                        PlaceholderAvatarView(size: 50)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(post.displayName ?? post.username)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        
                    Text("@\(post.username)")
                        .font(.system(size: 15))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                Text(post.createdAt.timeAgo())
                    .font(.system(size: 13))
                    .foregroundColor(.gray.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20) // This padding is within the ScrollView now
        
        PostBodyContentView(
            post: post, 
            showingReplay: $showingReplay,
            onImageTapped: { imageURL in
                viewerImageURL = imageURL
            }
        )
    }
    
    // Extracted ViewBuilder for Post Actions and Comments
    @ViewBuilder
    private var postActionsAndComments: some View {
        // Actions with enhanced styling - but no replay button
        HStack(spacing: 32) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    animateLike = true
                    isLiked.toggle()
                    likePost()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        animateLike = false
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundColor(isLiked ? .red : .gray.opacity(0.7))
                        .scaleEffect(animateLike ? 1.3 : 1.0)
                    
                    Text("\(post.likes)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray.opacity(0.9))
                }
            }
            
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 20))
                    .foregroundColor(.gray.opacity(0.7))
                
                Text("\(post.comments)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray.opacity(0.9))
            }
            
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.vertical, 8) // Reduced from 16
        
        // EXTRACTED COMMENTS SECTION
        if let postId = post.id {
            PostCommentsSectionView(
                comments: comments,
                replies: replies,
                isLoadingComments: isLoadingComments,
                isLoadingReplies: isLoadingReplies,
                userId: userId,
                postId: postId,
                commentToExpandReplies: commentToExpandReplies,
                userService: userService,
                onReplyTapped: { comment in
                                replyingToComment = comment
                                newCommentText = "@\(comment.username) "
                                isCommentFieldFocused = true
                            },
                onToggleRepliesTapped: { comment in
                    self.toggleRepliesExpansion(for: comment)
                },
                onDeleteTapped: { (commentId, parentComment) in
                    self.deleteComment(commentId, forPost: postId, parentOfDeletedReply: parentComment)
                }
            )
        }
    }
    
    // Extracted ViewBuilder for Comment Input View
    @ViewBuilder
    private var commentInputView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack(spacing: 14) {
                if let profileImageURL = userService.currentUserProfile?.avatarURL {
                    KFImage(URL(string: profileImageURL))
                        .placeholder {
                            PlaceholderAvatarView(size: 32)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    PlaceholderAvatarView(size: 32)
                }
                
                ZStack(alignment: .trailing) {
                    TextField(replyingToComment != nil ? "Replying to @\(replyingToComment!.username)..." : "Add a comment...", text: $newCommentText)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(Color(red: 25/255, green: 25/255, blue: 30/255))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                        .focused($isCommentFieldFocused)
                        // .ignoresSafeArea(.keyboard, edges: .bottom) // REMOVE
                    
                    if !newCommentText.isEmpty {
                        Button(action: addComment) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .padding(.trailing, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12) // This is the internal padding of the input bar
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 20/255, green: 20/255, blue: 24/255),
                        Color(red: 18/255, green: 18/255, blue: 22/255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .shadow(color: .black.opacity(0.3), radius: 5, y: -2)
            )
        }
        // No .ignoresSafeArea(.keyboard) here on the commentInputView itself
    }

    private func loadComments() {
        isLoadingComments = true
        replies = [:] // Clear any previously loaded replies
        isLoadingReplies = [:] // Clear loading states for replies
        commentToExpandReplies = nil // Reset any expanded replies view

        Task {
            do {
                if let postId = post.id {
                    // This now fetches only top-level comments due to PostService changes
                    let loadedComments = try await postService.getComments(for: postId)
                    await MainActor.run {
                        comments = loadedComments
                        isLoadingComments = false
                    }
                }
            } catch {

                await MainActor.run {
                    isLoadingComments = false
                }
            }
        }
    }

    private func loadReplies(for parentComment: Comment, expandAfterLoading: Bool = true) {
        guard let parentCommentId = parentComment.id, let postId = post.id else { return }

        if replies[parentCommentId] == nil {
            isLoadingReplies[parentCommentId] = true
            Task {
                do {
                    let loadedReplies = try await postService.getReplies(for: parentCommentId, on: postId)
                    await MainActor.run {
                        self.replies[parentCommentId] = loadedReplies
                        self.isLoadingReplies[parentCommentId] = false
                        if expandAfterLoading {
                            if self.commentToExpandReplies == nil || self.commentToExpandReplies?.id == parentCommentId {
                                self.commentToExpandReplies = parentComment
                            }
                        }
                    }
                } catch {

                    await MainActor.run {
                        self.isLoadingReplies[parentCommentId] = false
                    }
                }
            }
        } else if expandAfterLoading {
            self.commentToExpandReplies = parentComment
        }
    }

    private func toggleRepliesExpansion(for comment: Comment) {
        guard let commentId = comment.id else { return }

        if commentToExpandReplies?.id == commentId {
            commentToExpandReplies = nil 
        } else {
            commentToExpandReplies = comment 
            if replies[commentId] == nil {
                loadReplies(for: comment, expandAfterLoading: true)
            }
        }
    }
    
    private func addComment() {
        guard !newCommentText.isEmpty, let postId = self.post.id else { return }
        
        Task {
            var usernameToUse: String
            var profileImageToUse: String?
            let localCurrentUserId = self.userId 

            let userProfile: UserProfile?
            if let existingProfile = userService.currentUserProfile {
                userProfile = existingProfile
            } else {

                do {
                    try await userService.fetchUserProfile() 
                    userProfile = userService.currentUserProfile
                    if userProfile == nil {

                    } else {

                    }
                } catch {

                    return
                }
            }

            guard let validProfile = userProfile else {

                return
            }

            let fetchedUsername = validProfile.username

            guard !fetchedUsername.isEmpty else {

                return
            }
            
            guard fetchedUsername != "User" else {

                return
            }

            usernameToUse = fetchedUsername
            profileImageToUse = validProfile.avatarURL


            do {
                let parentId = replyingToComment?.id 
                try await postService.addComment(
                    to: postId,
                    userId: localCurrentUserId, 
                    username: usernameToUse,
                    profileImage: profileImageToUse,
                    content: newCommentText,
                    parentCommentId: parentId 
                )


                if let parent = replyingToComment, let parentId = parent.id {

                    await refreshPostComments(postId: postId)


                } else {
                    await refreshPostComments(postId: postId)

                }
                
                await MainActor.run {
                    newCommentText = ""
                    replyingToComment = nil 
                    isCommentFieldFocused = false 

                }

            } catch {

            }
        }
    }

    private func refreshPostComments(postId: String) async {
        if let index = postService.posts.firstIndex(where: { $0.id == postId }) {
            var postToUpdate = postService.posts[index]
            postToUpdate.comments += 1 
            // This direct mutation may not trigger UI updates depending on how PostService.posts is published.
            // If PostService publishes changes to individual posts or re-fetches, this might not be needed,
            // or a more robust update mechanism from PostService would be better.
            // For now, this attempts a local optimistic update.
            // postService.posts[index] = postToUpdate // This line might be problematic if posts is not directly mutable or doesn't trigger updates.

        }
         // Reload comments for the detail view
        loadComments()
    }
    
    private func deleteComment(_ commentId: String, forPost postId: String, parentOfDeletedReply: Comment? = nil) {
        Task {
            do {
                try await postService.deleteComment(postId: postId, commentId: commentId)
                
                if let parent = parentOfDeletedReply {
                    if let index = comments.firstIndex(where: { $0.id == parent.id }) {
                        var updatedParent = parent
                        if updatedParent.replies > 0 { updatedParent.replies -= 1 }
                        comments[index] = updatedParent
                        loadReplies(for: comments[index]) 
                    } else {
                        loadComments()
                    }
                } else {
                    loadComments()
                }
            } catch {

            }
        }
    }
    
    private func likePost() {
        Task {
            do {
                if let postId = post.id {
                    try await postService.toggleLike(postId: postId, userId: userId)
                    // Optionally update local post like count if needed, or rely on PostService to publish update
                }
            } catch {

            }
        }
    }
    
    private func deletePost() {
        Task {
            do {
                if let postId = post.id {

                    try await postService.deletePost(postId: postId)

                    await MainActor.run {
                       dismiss()
                    }
                    // Optionally, trigger a refresh of the feed in FeedView via a callback or service update
                } else {

                }
            } catch {

            }
        }
    }
}

// CommentRow with enhanced styling
struct CommentRow: View {
    let comment: Comment
    let isCurrentUser: Bool
    let isReply: Bool
    let parentCommentIdForReplyDeletion: String?
    let onReply: (() -> Void)?
    let onToggleReplies: (() -> Void)?
    let onDelete: () -> Void // REVERTED to original
    let areRepliesExpanded: Bool
    @EnvironmentObject var userService: UserService // Access to get displayName
    
    @State private var showDeleteConfirm = false
    @State private var navigateToProfile = false // For programmatic navigation
    
    // Get display name from userService if available, fallback to username
    // TODO: Comments should store displayName to avoid needing to fetch from userService
    private var displayName: String {
        if let userProfile = userService.loadedUsers[comment.userId],
           let profileDisplayName = userProfile.displayName,
           !profileDisplayName.isEmpty {
            return profileDisplayName
        }
        return comment.username
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Profile image with enhanced styling - Tappable to navigate to user profile
            Group {
                if let profileImage = comment.profileImage {
                    KFImage(URL(string: profileImage))
                        .placeholder {
                            PlaceholderAvatarView(size: 36)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    PlaceholderAvatarView(size: 36)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                navigateToProfile = true
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    // Make username tappable too
                    Text(displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateToProfile = true
                        }
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.system(size: 13))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.7)))
                    }
                    
                    Spacer()
                    
                    Text(comment.createdAt.timeAgo())
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    if isCurrentUser {
                        Button(action: {
                            showDeleteConfirm = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(6)
                        }
                        .confirmationDialog(
                            "Delete this comment?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                onDelete() // REVERTED to original
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
                
                Text(comment.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Action buttons: Reply, View/Hide Replies
                HStack(spacing: 20) {
                    if !isReply && comment.isReplyable, let onReplyAction = onReply { // Reply only for top-level, replyable comments
                        Button(action: onReplyAction) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Reply")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.9)))
                        }
                    }

                    if !isReply && comment.replies > 0, let onToggleRepliesAction = onToggleReplies { // View/Hide for top-level comments with replies
                        Button(action: onToggleRepliesAction) {
                            HStack(spacing: 4) {
                                Image(systemName: areRepliesExpanded ? "chevron.up" : "chevron.down")
                                     .font(.system(size: 11, weight: .medium))
                                Text(areRepliesExpanded ? "Hide Replies" : "View Replies")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.gray)
                        }
                    }
                    Spacer() // Pushes buttons to the left
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 10)
        // Add left padding if it's a reply
        .padding(.leading, isReply ? 30 : 0)
        // Hidden NavigationLink for programmatic navigation
        .background(
            NavigationLink(
                destination: UserProfileView(userId: comment.userId).environmentObject(userService),
                isActive: $navigateToProfile,
                label: { EmptyView() }
            )
            .hidden()
        )
    }
}

// Image Gallery View with caching
struct ImagesGalleryView: View {
    let imageURLs: [String]
    let onImageTap: (String) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(imageURLs, id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        KFImage(url)
                            .placeholder {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Rectangle())
                            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onImageTap(urlString)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}


// Add this extension at the end of the file
extension View {
    func navigationBarBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        self.modifier(NavigationBarBackground(background: background()))
    }
}

struct NavigationBarBackground<Background>: ViewModifier where Background: View {
    let background: Background
    
    func body(content: Content) -> some View {
        ZStack {
            content
            VStack {
                background
                    .edgesIgnoringSafeArea([.horizontal, .top])
                    .frame(height: 0)
                Spacer()
            }
        }
    }
}

// Add this helper struct and functions at the end of the PostDetailView struct
private struct ParsedSessionContent {
    let gameName: String
    let stakes: String
    let chipAmount: Double
    let buyIn: Double
    let elapsedTime: TimeInterval
    let actualContent: String
}

private func parseSessionContent(from content: String) -> ParsedSessionContent? {
    // First check for SESSION_INFO format
    if content.starts(with: "SESSION_INFO:") {
        let lines = content.components(separatedBy: "\n")
        if let firstLine = lines.first, firstLine.starts(with: "SESSION_INFO:") {
            let parts = firstLine.components(separatedBy: ":")
            if parts.count >= 3 {
                let gameName = parts[1].trimmingCharacters(in: .whitespaces)
                let stakes = parts[2].trimmingCharacters(in: .whitespaces)
                
                // Use default values for chip amount, buy-in, and elapsed time
                let chipAmount: Double = 0
                let buyIn: Double = 0
                let elapsedTime: TimeInterval = 0
                
                // Get the actual content without the SESSION_INFO line
                let actualContent = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                
                return ParsedSessionContent(
                    gameName: gameName,
                    stakes: stakes,
                    chipAmount: chipAmount,
                    buyIn: buyIn,
                    elapsedTime: elapsedTime,
                    actualContent: actualContent
                )
            }
        }
    }

    // Original parsing logic for session details format
    // Split by lines and trim whitespace
    let rawLines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    guard rawLines.count >= 3 else { return nil }
    
    // Attempt to identify summary lines
    var gameLine: String?
    var stackLine: String?
    var timeLine: String?
    var remainingLines: [String] = []
    
    for line in rawLines {
        if line.hasPrefix("Session at ") { gameLine = line; continue }
        if line.hasPrefix("Stack:") { stackLine = line; continue }
        if line.hasPrefix("Time:") { timeLine = line; continue }
        remainingLines.append(line)
    }
    guard let gLine = gameLine, let sLine = stackLine, let tLine = timeLine else { return nil }
    
    let (gameName, stakes) = parseGameAndStakes(from: gLine)
    let (chipAmount, buyIn) = parseStackInfo(from: sLine)
    let elapsedTime = parseSessionTime(from: tLine)
    let actualContent = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    
    return ParsedSessionContent(gameName: gameName, stakes: stakes, chipAmount: chipAmount, buyIn: buyIn, elapsedTime: elapsedTime, actualContent: actualContent)
}

private func parseGameAndStakes(from line: String) -> (String, String) {
    var gameName = "Cash Game"
    var stakes = "$1/$2"
    
    if line.hasPrefix("Session at ") {
        let parts = line.dropFirst("Session at ".count).split(separator: "(")
        if parts.count >= 2 {
            gameName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            stakes = String(parts[1]).replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
        }
    }
    
    return (gameName, stakes)
}

private func parseStackInfo(from line: String) -> (Double, Double) {
    var chipAmount: Double = 0
    var buyIn: Double = 0
    
    if let stackMatch = line.range(of: "Stack: \\$([0-9]+)", options: .regularExpression) {
        let stackStr = String(line[stackMatch]).replacingOccurrences(of: "Stack: $", with: "")
        chipAmount = Double(stackStr) ?? 0
    }
    
    // Calculate buy-in based on profit
    if let profitMatch = line.range(of: "\\(([+-]\\$[0-9]+)\\)", options: .regularExpression) {
        let profitStr = String(line[profitMatch])
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "$", with: "")
        
        if let profit = Double(profitStr.replacingOccurrences(of: "+", with: "")) {
            buyIn = chipAmount - profit
        }
    }
    
    return (chipAmount, buyIn)
}

private func parseSessionTime(from line: String) -> TimeInterval {
    var elapsedTime: TimeInterval = 0
    
    if let timeMatch = line.range(of: "Time: ([0-9]+)h ([0-9]+)m", options: .regularExpression) {
        let timeStr = String(line[timeMatch]).replacingOccurrences(of: "Time: ", with: "")
        let timeParts = timeStr.split(separator: "h ")
        if timeParts.count >= 2 {
            let hours = Int(String(timeParts[0])) ?? 0
            let minutes = Int(String(timeParts[1]).replacingOccurrences(of: "m", with: "")) ?? 0
            elapsedTime = TimeInterval(hours * 3600 + minutes * 60)
        }
    }
    
    return elapsedTime
}

private func isNote(content: String) -> Bool {
    // Check for note in content after SESSION_INFO
    if content.starts(with: "SESSION_INFO:") {
        let contentWithoutSessionInfo = content.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        if contentWithoutSessionInfo.contains("\n\nNote: ") || contentWithoutSessionInfo.contains("Note: ") {
            return true
        }
    }
    
    // Regular note detection
    if content.contains("\n\nNote: ") || content.starts(with: "Note: ") {
        return true
    }
    
    return false
}

private func extractSessionInfo(from content: String) -> (String?, String?) {
    // First check for explicitly formatted session info
    if content.starts(with: "SESSION_INFO:") {
        let lines = content.components(separatedBy: "\n")
        if let firstLine = lines.first, firstLine.starts(with: "SESSION_INFO:") {
            let parts = firstLine.components(separatedBy: ":")
            if parts.count >= 3 {
                let gameName = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let stakes = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                return (gameName, stakes)
            }
        }
    }
    
    // Fallback to regular parsing if needed
    if let parsed = parseSessionContent(from: content) {
        return (parsed.gameName, parsed.stakes)
    }
    
    return (nil, nil)
}

private func extractCommentContent(from content: String) -> String? {
    // Handle SESSION_INFO format
    if content.starts(with: "SESSION_INFO:") {
        let lines = content.components(separatedBy: "\n")
        if lines.count > 1 {
            let contentWithoutSessionInfo = lines.dropFirst().joined(separator: "\n")
            
            if let range = contentWithoutSessionInfo.range(of: "\n\nNote:") {
                return String(contentWithoutSessionInfo[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if !contentWithoutSessionInfo.starts(with: "Note: ") {
                return contentWithoutSessionInfo.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
    }
    
    // Regular extraction
    if let range = content.range(of: "\n\nNote:") {
        return String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if !content.starts(with: "Note: ") {
        return content
    }
    
    return nil
}

private func extractNoteContent(from content: String) -> String {
    // Handle SESSION_INFO format
    if content.starts(with: "SESSION_INFO:") {
        let contentWithoutSessionInfo = content.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        
        if let range = contentWithoutSessionInfo.range(of: "Note: ") {
            return String(contentWithoutSessionInfo[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    // Regular extraction
    if let range = content.range(of: "Note: ") {
        return String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    return ""
}

// Define PostBodyContentView within PostDetailView or at the same file level if preferred
// For this example, placing it before PostDetailView's closing brace

private struct PostBodyContentView: View {
    let post: Post
    @Binding var showingReplay: Bool
    var onImageTapped: ((String) -> Void)?

    // Helper functions like isNote, extractSessionInfo, extractCommentContent,
    // extractNoteContent, parseSessionContent should be accessible here.
    // If they are private to PostDetailView, they need to be moved or made available.
    // For now, assuming they are top-level private functions in the file or accessible.
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { // Reduced from 18 to 12
            // Parse completed session info first
            let (parsedCompletedSession, commentTextForCompletedSession) = parseCompletedSessionInfo(from: post.content)

            // Check for challenge posts first using unified parser
            if let challengeDisplayModel = ChallengePostParser.parse(post.content) {
                VStack(alignment: .leading, spacing: 8) {
                    // Extract and show user comment if any
                    if let userComment = ChallengePostParser.extractUserComment(post.content), !userComment.isEmpty {
                        Text(userComment)
                            .font(.system(size: 17))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    
                    // Display the challenge progress component using the display model
                    ChallengeProgressComponent(
                        challenge: challengeDisplayModel.challenge,
                        isCompact: false // Always show full detail in PostDetailView context
                    )
                    .padding(.horizontal, 16)
                }
            } else 
            if let completedInfo = parsedCompletedSession {
                CompletedSessionFeedCardView(sessionInfo: completedInfo)
                    .padding(.horizontal, 16) // Added horizontal padding for detail view context
                if !commentTextForCompletedSession.isEmpty {
                    Text(commentTextForCompletedSession)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8) // Add some space between card and comment
                }
            } else if post.isNote { // Check for notes BEFORE session ID check
                 // Note post with session badge (PostContextTagView is handled by PostDetailView's header area usually)
                VStack(alignment: .leading, spacing: 12) {
                    // If there's a comment with the note, display it
                    if let commentText = extractCommentContent(from: post.content), !commentText.isEmpty {
                        Text(commentText)
                            .font(.system(size: 17))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 2)
                    }
                    NoteCardView(noteText: extractNoteContent(from: post.content)) // Note content itself
                }
                .padding(.horizontal, 16)
            } else if post.postType == .hand {
                 // Hand post content (HandDisplayCardView handles its own display)
                 // The PostContextTagView is handled by PostDetailView header
                 // Comment for hand:
                if let commentText = extractCommentContent(from: post.content), !commentText.isEmpty {
                    Text(commentText)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16) // Add padding for the comment
                        .padding(.top, post.handHistory == nil ? 0 : 8) // Space below hand card if present
                }
            } else if post.sessionId != nil { // Live session posts (chip updates or start)
                if let parsed = parseSessionContent(from: post.content) {
                    if parsed.elapsedTime == 0 && parsed.buyIn > 0 { // Condition for "Session Started"
                        SessionStartedCardView(
                            gameName: parsed.gameName,
                            stakes: parsed.stakes,
                            location: post.location,
                            buyIn: parsed.buyIn,
                            userComment: parsed.actualContent
                        )
                        .padding(.horizontal, 16)
                    } else { // Regular chip update
                        LiveStackUpdateCardView(parsedContent: parsed)
                            .padding(.horizontal, 16)
                    }
                } else { // Fallback for session posts that don't parse with parseSessionContent
                    Text(post.content)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            } else if !post.content.isEmpty { // Regular post
                Text(post.content)
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.95))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            
            // Hand history card for .hand posts (distinct from comment above)
            if post.postType == .hand, let hand = post.handHistory {
                HandDisplayCardView(hand: hand, 
                                    onReplayTap: { showingReplay = true }, 
                                    location: post.location, 
                                    createdAt: post.createdAt,
                                    showReplayInFeed: true)
            }
            
            // Images - Square display with side padding
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(imageURLs, id: \.self) { url in
                        if let imageUrl = URL(string: url) {
                            KFImage(imageUrl)
                                .placeholder {
                                    Rectangle()
                                        .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                                        .overlay(
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        )
                                }
                                .resizable()
                                .scaledToFill()
                                .aspectRatio(1, contentMode: .fill) // Square aspect ratio
                                .clipped() // Crop to square
                                .cornerRadius(8) // Add slight rounding
                                .contentShape(Rectangle()) // Ensure the whole area is tappable
                                .onTapGesture {
                                    onImageTapped?(url)
                                }
                        }
                    }
                }
                .padding(.horizontal, 16) // Add side padding
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - PostCommentsSectionView

private struct PostCommentsSectionView: View {
    let comments: [Comment]
    let replies: [String: [Comment]]
    let isLoadingComments: Bool
    let isLoadingReplies: [String: Bool]
    let userId: String
    let postId: String // Needed for delete action on top-level comments
    let commentToExpandReplies: Comment?
    let userService: UserService // Added to pass to CommentRow

    // Callbacks
    let onReplyTapped: (Comment) -> Void
    let onToggleRepliesTapped: (Comment) -> Void
    let onDeleteTapped: (String, Comment?) -> Void // commentIdToDelete, parentCommentIfItWasAReply

    // Intermediate function to handle delete action
    private func handleDeleteAction(commentId: String, parentComment: Comment?) {
        onDeleteTapped(commentId, parentComment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Comments")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(comments.count)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.1)))
                    )
            }
            .padding(.horizontal, 16)
            
            if isLoadingComments {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 50, height: 50)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8))))
                            .scaleEffect(1.2)
                    }
                    Spacer()
                }
                .padding(.vertical, 30)
            } else if comments.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.1))
                                .frame(width: 70, height: 70)
                            
                            Image(systemName: "bubble.left")
                                .font(.system(size: 36))
                                .foregroundColor(.gray.opacity(0.3))
                        }
                        
                        VStack(spacing: 8) {
                            Text("No comments yet")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("Be the first to comment")
                                .font(.system(size: 14))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { comment in
                        CommentRow(
                            comment: comment,
                            isCurrentUser: comment.userId == userId,
                            isReply: false,
                            parentCommentIdForReplyDeletion: nil,
                            onReply: {
                                onReplyTapped(comment)
                            },
                            onToggleReplies: {
                                onToggleRepliesTapped(comment)
                            },
                            onDelete: { () -> Void in // REVERTED to original

                                // self.handleDeleteAction(commentId: comment.id ?? "", parentComment: nil) // Original logic temporarily bypassed
                            },
                            areRepliesExpanded: commentToExpandReplies?.id == comment.id && (replies[comment.id ?? ""]?.isEmpty == false)
                        )
                        .environmentObject(userService)
                        .padding(.horizontal, 16)

                        if commentToExpandReplies?.id == comment.id {
                            if isLoadingReplies[comment.id ?? ""] == true {
                                HStack {
                                    Spacer()
                                    ProgressView().padding(.vertical, 10)
                                    Spacer()
                                }
                                .padding(.horizontal, 16 + 15)
                            } else if let currentReplies = replies[comment.id ?? ""], !currentReplies.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(currentReplies) { reply in
                                        CommentRow(
                                            comment: reply,
                                            isCurrentUser: reply.userId == userId,
                                            isReply: true,
                                            parentCommentIdForReplyDeletion: comment.id,
                                            onReply: nil,
                                            onToggleReplies: nil,
                                            onDelete: { () -> Void in // REVERTED to original

                                                // self.handleDeleteAction(commentId: reply.id ?? "", parentComment: comment) // Original logic temporarily bypassed
                                            },
                                            areRepliesExpanded: false
                                        )
                                        .environmentObject(userService)
                                        
                                        if reply.id != currentReplies.last?.id {
                                            Divider()
                                                .background(Color.white.opacity(0.03))
                                                .padding(.leading, 30 + 16)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        
                        if comment.id != comments.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}

// IMPORTANT: The helper functions (isNote, extractSessionInfo, parseSessionContent, etc.)
// used within PostBodyContentView must be accessible. If they are private to PostDetailView,
// they need to be moved to be top-level private functions in the file, or passed into PostBodyContentView.
// Assuming they are accessible for now.

// MARK: - Completed Session Feed Card View

private struct CompletedSessionFeedCardView: View {
    let sessionInfo: ParsedCompletedSessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sessionInfo.title)
                .font(.system(size: 22, weight: .bold)) // Prominent title for feed
                .foregroundColor(.white)
                .lineLimit(2)
                .padding(.bottom, 6)

            // Strava-like stats display for the feed
            HStack(alignment: .top, spacing: 12) { // Use spacing for distinct metrics
                FeedStatDisplayView(label: "DURATION", value: sessionInfo.duration)
                Spacer()
                FeedStatDisplayView(label: "BUY-IN", value: sessionInfo.buyIn)
                Spacer()
                FeedStatDisplayView(label: "CASHOUT", value: sessionInfo.cashout)
                Spacer()
                FeedStatDisplayView(label: "PROFIT", value: sessionInfo.profit, 
                                  valueColor: sessionInfo.profit.contains("-") ? .red : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            }
        }
        .padding(.vertical, 10) 
    }
}

// Renamed FeedStatView to FeedStatDisplayView for clarity and consistency
private struct FeedStatDisplayView: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var isWide: Bool = false

    var body: some View {
        VStack(alignment: isWide ? .leading : .center, spacing: 2) { // Center align normal stats, left align wide ones
            Text(value)
                .font(.system(size: dynamicFontSize, weight: .bold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4) // More aggressive scaling to prevent cutoff
            Text(label) // Label below value, as in Strava
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: isWide ? .infinity : nil, alignment: isWide ? .leading : .center)
    }
    
    // Use consistent font size for all metrics in a row
    private var dynamicFontSize: CGFloat {
        return isWide ? 18 : 20 // Consistent size within each category
    }
}

// Add a helper function to clean content for note display (after the post card views)
func cleanContentForNoteDisplay(_ content: String) -> String {
    // If content starts with SESSION_INFO, remove that line
    if content.starts(with: "SESSION_INFO:") {
        let lines = content.components(separatedBy: "\n")
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    // Otherwise return the original content
    return content
}

// New View for Live Stack Updates
private struct LiveStackUpdateCardView: View {
    let parsedContent: ParsedSessionContent
    // Location is handled by the PostContextTagView above this card.

    private var profitOrLoss: Double {
        return parsedContent.chipAmount - parsedContent.buyIn
    }

    private var profitLossString: String {
        let value = profitOrLoss
        return String(format: "%@$%.2f", value >= 0 ? "+" : "-", abs(value))
    }

    private var profitLossColor: Color {
        profitOrLoss > 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : (profitOrLoss < 0 ? .red : .gray)
    }
    
    private var durationString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: parsedContent.elapsedTime) ?? "0m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(parsedContent.gameName) - \(parsedContent.stakes)") // Corrected string interpolation
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.8))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 4)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT STACK")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.gray.opacity(0.8))
                    Text(String(format: "$%.0f", parsedContent.chipAmount))
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("PROFIT / LOSS")
                         .font(.system(size: 11, weight: .medium)).foregroundColor(.gray.opacity(0.8))
                    Text(profitLossString)
                        .font(.system(size: 22, weight: .bold)).foregroundColor(profitLossColor)
                }
            }

            if parsedContent.elapsedTime > 0 {
                Divider().background(Color.white.opacity(0.1))
                HStack {
                    Text("SESSION TIME")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.gray.opacity(0.8))
                    Spacer()
                    Text(durationString)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                }
            }
            
            if !parsedContent.actualContent.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                Text(parsedContent.actualContent)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.25))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// New View for "Session Started"
private struct SessionStartedCardView: View {
    let gameName: String
    let stakes: String
    let location: String?
    let buyIn: Double
    let userComment: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.playing.poker")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                Text("Session Started!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 4)
            
            HStack {
                Text("INITIAL BUY-IN")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.gray.opacity(0.8))
                Spacer()
                Text(String(format: "$%.0f", buyIn))
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            }

            if let comment = userComment, !comment.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                Text(comment)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.25))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// Allow using a String directly in `fullScreenCover(item:)`
extension String: Identifiable {
    public var id: String { self }
}



// MARK: - Record Activity Post Card (Strava-style)
struct RecordActivityPostCard: View {
    let onLiveSessionTapped: () -> Void
    let onHostHomeGameTapped: () -> Void
    let onExploreEventsTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Content - centered
            VStack(spacing: 4) {
                Text("Quick Actions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                Text("Start playing or discover new games")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            
            // Action buttons in vertical layout for better spacing
            VStack(spacing: 10) {
                // Start Live Session Button (primary action)
                Button(action: onLiveSessionTapped) {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.black)
                        
                        Text("Start Live Session")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.6))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
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
                .buttonStyle(PlainButtonStyle())
                
                // Secondary actions row - perfectly centered
                HStack(spacing: 10) {
                    // Host Home Game Button
                    Button(action: onHostHomeGameTapped) {
                        HStack(spacing: 8) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            
                            Text("Host Home Game")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Explore Events Button
                    Button(action: onExploreEventsTapped) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            
                            Text("Explore Events")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.clear)
    }
}

// MARK: - Suggested Users Post Card (Strava-style)
struct SuggestedUsersPostCard: View {
    let users: [UserProfile]
    let isLoading: Bool
    let userId: String
    let onUserTapped: (String) -> Void
    let onUserFollowed: () -> Void
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (simplified, no faux profile picture)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested Players")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    if !isLoading && !users.isEmpty {
                        Text("\(users.count) players")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            // Content
            Text("Follow players to see their poker content!")
                .font(.system(size: 14))
                .foregroundColor(.gray.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            
            if isLoading {
                // Compact loading state
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        CompactUserSkeletonView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            } else if users.isEmpty {
                // Empty state
                Text("No suggestions available")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else {
                // User list in compact format
                VStack(spacing: 8) {
                    ForEach(users, id: \.id) { user in
                        CompactUserRowView(
                            user: user,
                            currentUserId: userId,
                            onTapped: { onUserTapped(user.id) },
                            onFollowTapped: {
                                // Call the parent callback when user is followed
                                onUserFollowed()
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Compact User Row for Post-style Feed
struct CompactUserRowView: View {
    let user: UserProfile
    let currentUserId: String
    let onTapped: () -> Void
    let onFollowTapped: () -> Void
    @State private var isFollowing = false
    @State private var isProcessing = false
    @State private var showFollowed = false
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        Button(action: onTapped) {
            HStack(spacing: 12) {
                // Profile Picture (smaller)
                Group {
                    if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                        KFImage(url)
                            .placeholder {
                                PlaceholderAvatarView(size: 36)
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    } else {
                        PlaceholderAvatarView(size: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                
                // User Info (more compact)
                VStack(alignment: .leading, spacing: 2) {
                    if let displayName = user.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 4) {
                        Text("@\(user.username)")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))
                            .lineLimit(1)
                        
                        if user.followersCount > 0 {
                            Text("• \(user.followersCount) followers")
                                .font(.system(size: 13))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                }
                
                Spacer()
                
                // Follow Button (smaller)
                Button(action: {
                    guard !isProcessing else { return }
                    handleFollowTap()
                }) {
                    Group {
                        if showFollowed {
                            Text("✓ Followed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        } else {
                            Text(isProcessing ? "..." : "Follow")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(showFollowed ? Color.clear : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(showFollowed ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isProcessing || showFollowed)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            checkIfFollowing()
        }
    }
    
    private func checkIfFollowing() {
        Task {
            do {
                let following = try await userService.isFollowing(userId: user.id)
                await MainActor.run {
                    self.isFollowing = following
                    self.showFollowed = following
                }
            } catch {
                // Error checking, assume not following
                await MainActor.run {
                    self.isFollowing = false
                    self.showFollowed = false
                }
            }
        }
    }
    
    private func handleFollowTap() {
        isProcessing = true
        
        Task {
            do {
                try await userService.followUser(userIdToFollow: user.id)
                await MainActor.run {
                    self.showFollowed = true
                    self.isFollowing = true
                    self.isProcessing = false
                }
                
                // Refresh current user profile to update following count
                try? await userService.fetchUserProfile()
                
                // Call the original callback
                await MainActor.run {
                    onFollowTapped()
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                }
                print("Error following user: \(error)")
            }
        }
    }
}

// MARK: - Compact Skeleton Loading View
struct CompactUserSkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture skeleton (smaller)
            Circle()
                .fill(Color.gray.opacity(isAnimating ? 0.1 : 0.3))
                .frame(width: 36, height: 36)
                .animation(Animation.easeInOut(duration: 1.5).repeatForever(), value: isAnimating)
            
            // User info skeleton
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.gray.opacity(isAnimating ? 0.1 : 0.3))
                    .frame(width: 100, height: 14)
                    .cornerRadius(3)
                
                Rectangle()
                    .fill(Color.gray.opacity(isAnimating ? 0.1 : 0.3))
                    .frame(width: 120, height: 12)
                    .cornerRadius(3)
            }
            
            Spacer()
            
            // Follow button skeleton (smaller)
            Rectangle()
                .fill(Color.gray.opacity(isAnimating ? 0.1 : 0.3))
                .frame(width: 60, height: 24)
                .cornerRadius(12)
        }
        .padding(.vertical, 4)
        .onAppear {
            isAnimating = true
        }
    }
}

// Determine challenge post status (start / update / completed)
private func challengeStatusText(_ content: String) -> String? {
    if content.contains("🎯 Started a new challenge") {
        return "Challenge Started"
    } else if content.contains("🎯 Challenge Update") {
        return "Challenge Update"
    } else if content.contains("🎉 Session Challenge Completed") || content.contains("🎉 Challenge Completed") {
        return "Challenge Completed"
    }
    return nil
}





