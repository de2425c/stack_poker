import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import Kingfisher

struct FeedView: View {
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @State private var showingNewPost = false
    @State private var isRefreshing = false
    @State private var showingDiscoverUsers = false
    @State private var showingUserSearchView = false
    @State private var selectedPost: Post? = nil
    @State private var showingFullScreenImage = false
    @State private var selectedImageURL: String? = nil
    @State private var showingComments = false
    
    let userId: String
    
    init(userId: String = Auth.auth().currentUser?.uid ?? "") {
        self.userId = userId
        
        // Configure the Kingfisher cache
        let cache = ImageCache.default
        
        // Set memory cache limit correctly as Int
        let memoryCacheMB = 300
        cache.memoryStorage.config.totalCostLimit = memoryCacheMB * 1024 * 1024
        
        // Set disk cache limit (breaking into simpler expressions)
        let diskCacheMB: UInt = 1000
        let diskCacheBytes = diskCacheMB * 1024 * 1024
        cache.diskStorage.config.sizeLimit = diskCacheBytes
        
        // Configure navigation bar appearance to prevent white bar when scrolling
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        // Break the color creation into separate steps
        let bgRed: CGFloat = 12/255
        let bgGreen: CGFloat = 12/255
        let bgBlue: CGFloat = 16/255
        let backgroundColor = UIColor(red: bgRed, green: bgGreen, blue: bgBlue, alpha: 1.0)
        
        appearance.backgroundColor = backgroundColor
        appearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Use the AppBackgroundView for a rich background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top bar: Search placeholder and Add Post button
                    HStack(spacing: 12) {
                        // Tappable Search Bar Placeholder
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color.gray.opacity(0.7))
                            Text("Search people to follow...")
                                .foregroundColor(Color.gray.opacity(0.9))
                                .font(.system(size: 16))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(10)
                        .contentShape(Rectangle()) // Make the whole area tappable
                        .onTapGesture {
                            showingUserSearchView = true
                        }
                        
                        // Add Post Button
                        Button(action: {
                            showingNewPost = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))) // Accent color
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, (UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0) + 8) // Safe area + some padding
                    .padding(.bottom, 8)
                    .background(Color(UIColor(red: 12/255, green: 12/255, blue: 16/255, alpha: 1.0))) // Background for the top bar area

                    // Feed content
                    if postService.isLoading && postService.posts.isEmpty {
                        // Loading state - enhanced with animation
                        VStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                                    .scaleEffect(1.5)
                            }
                            .shadow(color: Color.black.opacity(0.2), radius: 5)
                            
                            Text("Loading Feed")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 16)
                            Spacer()
                        }
                    } else if postService.posts.isEmpty {
                        // Empty feed state
                        EmptyFeedView(showDiscoverUsers: {
                            showingDiscoverUsers = true
                        })
                    } else {
                        // Twitter-like feed with posts
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) { // Twitter has no spacing between posts
                                ForEach(postService.posts) { post in
                                    VStack(spacing: 0) {
                                        PostView(
                                            post: post,
                                            onLike: {
                                                Task {
                                                    do {
                                                        try await postService.toggleLike(postId: post.id ?? "", userId: userId)
                                                    } catch {
                                                        print("Error toggling like: \(error)")
                                                    }
                                                }
                                            },
                                            onComment: {
                                                selectedPost = post
                                                showingComments = true
                                            },
                                            userId: userId
                                        )
                                        
                                        // Twitter-like divider between posts
                                        Rectangle()
                                            .fill(Color.white.opacity(0.06))
                                            .frame(height: 0.5)
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
                            }
                        }
                        .refreshable {
                            // Pull to refresh
                            await refreshFeed()
                        }
                    }
                }
                .onAppear {
                    // Load posts when the view appears
                    if postService.posts.isEmpty {
                        Task {
                            try? await postService.fetchPosts()
                        }
                    }
                }
                .sheet(isPresented: $showingNewPost) {
                    PostEditorView(userId: userId)
                        .environmentObject(postService)
                        .environmentObject(userService)
                }
                .sheet(isPresented: $showingDiscoverUsers) {
                    DiscoverUsersView(userId: userId)
                        .environmentObject(userService)
                }
                .sheet(isPresented: $showingUserSearchView) {
                    UserSearchView(currentUserId: userId, userService: userService)
                }
                .sheet(item: $selectedPost) { post in
                    PostDetailView(post: post, userId: userId)
                        .environmentObject(postService)
                        .environmentObject(userService)
                }
                .fullScreenCover(isPresented: $showingFullScreenImage) {
                    if let imageUrl = selectedImageURL {
                        FullScreenImageView(imageURL: imageUrl, onDismiss: { showingFullScreenImage = false })
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationBarTitle("", displayMode: .inline)
            .edgesIgnoringSafeArea(.top)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // Refresh the feed
    private func refreshFeed() async {
        isRefreshing = true
        try? await postService.fetchPosts()
        isRefreshing = false
    }
    
    // Handle like action
    private func likePost(_ post: Post) {
        Task {
            do {
                if let postId = post.id {
                    try await postService.toggleLike(postId: postId, userId: userId)
                }
            } catch {
                print("Error liking post: \(error)")
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
                }
            } catch {
                print("Error deleting post: \(error)")
            }
        }
    }
}

// Update BasicPostCardView to be more Twitter-like
struct BasicPostCardView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let isCurrentUser: Bool
    @State private var isLiked: Bool
    @State private var animateLike = false
    @State private var showDeleteConfirm = false
    
    init(post: Post, onLike: @escaping () -> Void, onComment: @escaping () -> Void, onDelete: @escaping () -> Void, isCurrentUser: Bool) {
        self.post = post
        self.onLike = onLike
        self.onComment = onComment
        self.onDelete = onDelete
        self.isCurrentUser = isCurrentUser
        // Initialize isLiked from the post's state
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Twitter-like header layout
            HStack(alignment: .top, spacing: 12) {
                // Profile image with Twitter-like styling, wrapped in NavigationLink
                NavigationLink(destination: UserProfileView(userId: post.userId)) {
                    Group {
                        if let profileImage = post.profileImage {
                            KFImage(URL(string: profileImage))
                                .placeholder {
                                    Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                .frame(width: 48, height: 48)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle()) // Add this to make the NavigationLink tap area precise
                
                VStack(alignment: .leading, spacing: 2) {
                    // Display name and username in Twitter-like format
                    HStack(alignment: .center, spacing: 4) {
                        Text(post.displayName ?? post.username)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            
                        Text("@\(post.username)")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                        
                        Text("·")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                            
                        Text(post.createdAt.timeAgo())
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    
                    // Post content directly under the username (Twitter-style)
                    if !post.content.isEmpty {
                        Text(post.content)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    
                    // Images - Twitter-like layout
                    if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
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
                                            .frame(width: 200, height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 10)) // Twitter has slightly rounded images
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    // Twitter-like actions bar
                    HStack(spacing: 48) {
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
                        
                        // Delete option (only for user's own posts) - more subtle
                        if isCurrentUser {
                            Button(action: { showDeleteConfirm = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            .confirmationDialog(
                                "Delete this post?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    onDelete()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This action cannot be undone.")
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 12)
                }
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(red: 18/255, green: 18/255, blue: 24/255)) // More neutral Twitter-like background
    }
}

// Update PostCardView to match the Twitter-like layout of BasicPostCardView
struct PostCardView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let isCurrentUser: Bool
    let userId: String
    @State private var showingReplay = false
    @State private var isLiked: Bool
    @State private var animateLike = false
    @State private var showDeleteConfirm = false
    
    init(post: Post, onLike: @escaping () -> Void, onComment: @escaping () -> Void, onDelete: @escaping () -> Void, isCurrentUser: Bool, userId: String) {
        self.post = post
        self.onLike = onLike
        self.onComment = onComment
        self.onDelete = onDelete
        self.isCurrentUser = isCurrentUser
        self.userId = userId
        // Initialize isLiked from the post's state
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Twitter-like header layout
            HStack(alignment: .top, spacing: 12) {
                // Profile image with Twitter-like styling
                Group {
                    if let profileImage = post.profileImage {
                        KFImage(URL(string: profileImage))
                            .placeholder {
                                Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            .frame(width: 48, height: 48)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Display name and username in Twitter-like format
                    HStack(alignment: .center, spacing: 4) {
                        Text(post.displayName ?? post.username)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            
                        Text("@\(post.username)")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                        
                        Text("·")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                            
                        Text(post.createdAt.timeAgo())
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    
                    // Post content directly under the username (Twitter-style)
                    if !post.content.isEmpty {
                        Text(post.content)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    
                    // Hand post content
                    if post.postType == .hand, let hand = post.handHistory {
                        HandSummaryView(hand: hand, showReplayButton: false)
                            .padding(.top, 8)
                    }
                    
                    // Images - Twitter-like layout
                    if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
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
                                            .frame(width: 200, height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 10)) // Twitter has slightly rounded images
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    // Twitter-like actions bar
                    HStack(spacing: 36) {
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
                        
                        // Delete option (only for user's own posts)
                        if isCurrentUser {
                            Button(action: { showDeleteConfirm = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            .confirmationDialog(
                                "Delete this post?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    onDelete()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This action cannot be undone.")
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 12)
                }
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(red: 18/255, green: 18/255, blue: 24/255)) // More neutral Twitter-like background
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand, userId: userId)
            }
        }
    }
}

// Empty Feed View
struct EmptyFeedView: View {
    let showDiscoverUsers: () -> Void
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
                
                Button(action: showDiscoverUsers) {
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
    @State private var showingFullScreenImage = false
    @State private var selectedImageURL: String? = nil
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
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isCommentFieldFocused: Bool
    
    init(post: Post, userId: String) {
        self.post = post
        self.userId = userId
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        ZStack {
            // Use AppBackgroundView for consistent design
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top header bar with enhanced styling
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.25))
                                    .shadow(color: .black.opacity(0.2), radius: 2)
                            )
                    }
                    
                    Spacer()
                    
                    if post.userId == userId {
                        Button(action: { showDeleteConfirm = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(12)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.25))
                                        .shadow(color: .black.opacity(0.2), radius: 2)
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(
                    Rectangle()
                        .fill(Color(red: 16/255, green: 16/255, blue: 20/255).opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                )
                
                // Content area with enhanced styling
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Post header with enhanced profile image
                        HStack(spacing: 12) {
                            // Profile image
                            Group {
                                if let profileImage = post.profileImage {
                                    KFImage(URL(string: profileImage))
                                        .placeholder {
                                            Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                        }
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                } else {
                                    Circle()
                                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                // Display name and username in format: "DisplayName @username"
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
                        .padding(.top, 20)
                        
                        PostBodyContentView(post: post, showingReplay: $showingReplay, selectedImageURL: $selectedImageURL, showingFullScreenImage: $showingFullScreenImage)
                            
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
                            .padding(.vertical, 16)
                        
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
                        
                        // Space at the bottom to account for comment input
                        Color.clear
                            .frame(height: 80)
                    }
                }
                
                // Comment input field with enhanced styling
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    HStack(spacing: 14) {
                        // User avatar for comment input
                        if let profileImageURL = userService.currentUserProfile?.avatarURL {
                            KFImage(URL(string: profileImageURL))
                                .placeholder {
                                    Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                .frame(width: 32, height: 32)
                        }
                        
                        ZStack(alignment: .trailing) {
                            TextField(replyingToComment != nil ? "Replying to @\(replyingToComment!.username)..." : "Add a comment...", text: $newCommentText)
                                .font(.system(size: 16))
                                .padding(12)
                                .background(Color(red: 25/255, green: 25/255, blue: 30/255))
                                .cornerRadius(20)
                                .foregroundColor(.white)
                                .focused($isCommentFieldFocused)
                            
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
                    .padding(.vertical, 12)
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
                .offset(y: -keyboardHeight > 0 ? -keyboardHeight + (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0) : 0)
                .animation(.easeOut(duration: 0.16), value: keyboardHeight)
            }
        }
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
            // Dismiss keyboard when tapping outside
            isCommentFieldFocused = false
        }
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let imageUrl = selectedImageURL {
                FullScreenImageView(imageURL: imageUrl, onDismiss: { showingFullScreenImage = false })
            }
        }
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand, userId: userId)
            }
        }
        .onAppear {
            loadComments()
            
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
            // Clean up keyboard observers
            NotificationCenter.default.removeObserver(self)
        }
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
                print("Error loading comments: \(error)")
                await MainActor.run {
                    isLoadingComments = false
                }
            }
        }
    }

    // Renamed and refactored: primary role is to fetch replies if needed.
    // Expansion is controlled by expandAfterLoading or by toggleRepliesExpansion.
    private func loadReplies(for parentComment: Comment, expandAfterLoading: Bool = true) {
        guard let parentCommentId = parentComment.id, let postId = post.id else { return }

        // Only load if replies are not already fetched for this parentCommentId
        if replies[parentCommentId] == nil {
            isLoadingReplies[parentCommentId] = true
            Task {
                do {
                    let loadedReplies = try await postService.getReplies(for: parentCommentId, on: postId)
                    await MainActor.run {
                        self.replies[parentCommentId] = loadedReplies
                        self.isLoadingReplies[parentCommentId] = false
                        if expandAfterLoading {
                            // If we were asked to expand after loading, and no other comment is currently set to expand,
                            // or if the currently expanding comment is this one, then set it.
                            if self.commentToExpandReplies == nil || self.commentToExpandReplies?.id == parentCommentId {
                                self.commentToExpandReplies = parentComment
                            }
                        }
                    }
                } catch {
                    print("Error loading replies for \(parentCommentId): \(error)")
                    await MainActor.run {
                        self.isLoadingReplies[parentCommentId] = false
                    }
                }
            }
        } else if expandAfterLoading {
            // Replies are already loaded, and we want to ensure this comment's replies are shown.
            // This will effectively re-assert that this comment should be the one expanded.
            self.commentToExpandReplies = parentComment
        }
        // If expandAfterLoading is false and replies are already loaded, this function does nothing further.
    }

    // New function to explicitly handle the user tapping "View/Hide Replies"
    private func toggleRepliesExpansion(for comment: Comment) {
        guard let commentId = comment.id else { return }

        if commentToExpandReplies?.id == commentId {
            commentToExpandReplies = nil // Collapse if currently expanded
        } else {
            commentToExpandReplies = comment // Expand this comment's replies
            // If replies for this comment haven't been loaded yet, load them.
            // loadReplies will handle the isLoadingReplies state and populate self.replies.
            // The expandAfterLoading: true ensures that if it successfully loads, it keeps this comment expanded.
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
            let localCurrentUserId = self.userId // Assuming self.userId is the current user's ID

            // Step 1: Get current profile or fetch if needed
            let userProfile: UserProfile?
            if let existingProfile = userService.currentUserProfile {
                userProfile = existingProfile
            } else {
                print("[FeedView.addComment] Profile nil, attempting fetch for user ID: \(localCurrentUserId)...")
                do {
                    // Ensure fetchUserProfile is called for the correct user if it takes a userId parameter
                    // If it inherently knows the current user, this is fine.
                    try await userService.fetchUserProfile() // Assuming this fetches for self.userId
                    userProfile = userService.currentUserProfile
                    if userProfile == nil {
                        print("[FeedView.addComment] Profile still nil after fetch for user ID: \(localCurrentUserId).")
                    } else {
                        print("[FeedView.addComment] Profile fetched successfully for user ID: \(localCurrentUserId). Username: \(userProfile!.username)")
                    }
                } catch {
                    print("[FeedView.addComment] Error fetching profile for user ID \(localCurrentUserId): \(error.localizedDescription). Cannot add comment.")
                    // Optionally show an alert to the user or handle error
                    return
                }
            }

            // Step 2: Validate the obtained profile
            guard let validProfile = userProfile else {
                print("[FeedView.addComment] User profile is nil even after fetch attempt for user ID: \(localCurrentUserId). Cannot add comment.")
                // Optionally show an alert or handle
                return
            }

            // Step 3: Username is non-optional on UserProfile, so direct access.
            let fetchedUsername = validProfile.username

            // Step 4: Validate username
            guard !fetchedUsername.isEmpty else {
                print("[FeedView.addComment] Error: Username in profile for user ID \(localCurrentUserId) is empty. Username: '\(fetchedUsername)'. Cannot add comment.")
                // Optionally show an alert or handle
                return
            }
            
            guard fetchedUsername != "User" else {
                 print("[FeedView.addComment] Error: Username for user ID \(localCurrentUserId) is placeholder 'User'. Username: '\(fetchedUsername)'. Cannot add comment.")
                // Optionally show an alert or handle
                return
            }

            // Step 5: If all checks pass
            usernameToUse = fetchedUsername
            profileImageToUse = validProfile.avatarURL // Assuming avatarURL is the correct property
            print("[FeedView.addComment] Using username: '\(usernameToUse)' and profile image: '\(profileImageToUse ?? "nil")' for comment on post \(postId) by user \(localCurrentUserId).")

            // Proceed with adding comment
            do {
                let parentId = replyingToComment?.id // Assuming replyingToComment logic exists or is adapted
                try await postService.addComment(
                    to: postId,
                    userId: localCurrentUserId, // Ensure this is the actual current user's ID
                    username: usernameToUse,
                    profileImage: profileImageToUse,
                    content: newCommentText,
                    parentCommentId: parentId // nil if not a reply
                )
                print("[FeedView.addComment] Comment successfully added to post \(postId) by user \(localCurrentUserId).")

                // Refresh comments or UI
                if let parent = replyingToComment, let parentId = parent.id {
                     // If it's a reply, update reply list for the parent comment
                     // This might involve re-fetching replies for that specific parent comment
                     // Example:
                     // await loadReplies(for: parent, expandAfterLoading: true) // If loadReplies is adapted
                    print("[FeedView.addComment] It was a reply to comment \(parentId). Refreshing replies (logic to be implemented).")
                    // For FeedView, direct replies might not be shown, or handled differently.
                    // If comments are reloaded for the post, that might be sufficient.
                    await refreshPostComments(postId: postId)


                } else {
                    // If it's a top-level comment, refresh all comments for the post
                    await refreshPostComments(postId: postId)
                    print("[FeedView.addComment] It was a top-level comment. Refreshed comments for post \(postId).")
                }
                
                await MainActor.run {
                    newCommentText = ""
                    replyingToComment = nil // Reset reply state
                    // activePostForComment = nil // Or however you manage the comment input UI state
                    isCommentFieldFocused = false // Dismiss keyboard if applicable
                     print("[FeedView.addComment] UI reset after adding comment.")
                }

            } catch {
                print("[FeedView.addComment] Error occurred while finally trying to add comment to post \(postId) by user \(localCurrentUserId): \(error.localizedDescription)")
                // Optionally show an alert
            }
        }
    }

    // Helper function to refresh comments for a specific post in the list
    // This is a conceptual example; implementation depends on how posts array is managed
    private func refreshPostComments(postId: String) async {
        // Find the post in postService.posts and update its comment count or reload its comments
        // For simplicity, we can just re-fetch all posts if granular update is complex
        // or if PostService handles comment count updates internally when a comment is added.
        // The Post object itself has a 'comments' count. We need to ensure this is updated.
        
        // Option 1: Optimistically update local post data (if possible)
        if let index = postService.posts.firstIndex(where: { $0.id == postId }) {
            var postToUpdate = postService.posts[index]
            // Assuming addComment in PostService updates the comment count in Firestore
            // We might need to re-fetch this specific post or just increment its comment count locally
            // For now, let's assume PostService handles the backend, and we might need a fresh fetch
            // or PostService could publish changes to the specific post.

            // If PostService's addComment doesn't return the updated post or new count directly,
            // we might need a way to get the new comment count.
            // For now, let's simulate an increment.
            // This is a simplification. Ideally, the backend or PostService.addComment tells us the new count.
            postToUpdate.comments += 1 // Optimistic update.
            
            // This direct mutation might not work if postService.posts is not directly mutable
            // or if it doesn't trigger UI updates.
            // A better way might be for PostService to publish the updated post.
            // await postService.fetchPost(id: postId) // if such a function exists and updates the posts array
            
            // Simplest for now: refresh the whole feed if granular update is tricky
            // await postService.fetchPosts()
            print("[FeedView.refreshPostComments] Post \(postId) comment count potentially updated. UI should refresh.")
        }
        // If FeedView displays comments directly (it doesn't seem to, PostDetailView does),
        // then here you would reload the comments for THAT post.
        // Since FeedView shows a summary (PostView), updating the comment count on the Post object is key.
    }
    
    // The commentId is the ID of the comment/reply to delete.
    // The optional parentComment is the Comment object if we are deleting a reply (so we can refresh its replies).
    private func deleteComment(_ commentId: String, forPost postId: String, parentOfDeletedReply: Comment? = nil) {
        Task {
            do {
                try await postService.deleteComment(postId: postId, commentId: commentId)
                
                // Refresh comments after deletion
                if let parent = parentOfDeletedReply {
                    // We deleted a reply, refresh the replies for its parent
                    // Also, the parent's reply count in DB was decremented by PostService.
                    // We need to update our local copy of the parent comment.
                    if let index = comments.firstIndex(where: { $0.id == parent.id }) {
                        var updatedParent = parent
                        if updatedParent.replies > 0 { updatedParent.replies -= 1 }
                        comments[index] = updatedParent
                        loadReplies(for: comments[index]) // Refresh and potentially collapse/expand
                    } else {
                         // Parent not found in top-level, this case should be rare with 1-level deep replies
                         // Fallback to reloading all comments
                        loadComments()
                    }
                } else {
                    // We deleted a top-level comment, so reload all top-level comments
                    // This will also clear out any loaded replies from the state.
                    loadComments()
                }
            } catch {
                print("Error deleting comment: \(error)")
            }
        }
    }
    
    private func likePost() {
        Task {
            do {
                if let postId = post.id {
                    try await postService.toggleLike(postId: postId, userId: userId)
                }
            } catch {
                print("Error liking post: \(error)")
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
                }
            } catch {
                print("Error deleting post: \(error)")
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
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Profile image with enhanced styling
            Group {
                if let profileImage = comment.profileImage {
                    KFImage(URL(string: profileImage))
                        .placeholder {
                            Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
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
                    Circle()
                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(comment.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
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

// Full Screen Image View
struct FullScreenImageView: View {
    let imageURL: String
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let url = URL(string: imageURL) {
                KFImage(url)
                    .resizable()
                    .placeholder {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1), 5)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                offset = CGSize(
                                    width: lastOffset.width + gesture.translation.width,
                                    height: lastOffset.height + gesture.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = scale > 1 ? 1 : 2
                            if scale == 1 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            } else {
                Text("Invalid image URL")
                    .foregroundColor(.white)
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 40)
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
        .gesture(
            TapGesture()
                .onEnded { _ in
                    onDismiss()
                }
        )
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

private func extractSessionInfo(from content: String) -> (String, String)? {
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
    
    return nil
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
    @Binding var selectedImageURL: String?
    @Binding var showingFullScreenImage: Bool

    // Helper functions like isNote, extractSessionInfo, extractCommentContent, 
    // extractNoteContent, parseSessionContent should be accessible here.
    // If they are private to PostDetailView, they need to be moved or made available.
    // For now, assuming they are top-level private functions in the file or accessible.

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !post.content.isEmpty {
                // Check for session posts
                if post.sessionId != nil || post.content.starts(with: "SESSION_INFO:") {
                    // Check if this is a note
                    if isNote(content: post.content) {
                        // Note post with session badge
                        VStack(alignment: .leading, spacing: 12) {
                            // Session badge at the top
                            if let (gameName, stakes) = extractSessionInfo(from: post.content) {
                                SessionBadgeView(
                                    gameName: gameName,
                                    stakes: stakes
                                )
                                .padding(.bottom, 8)
                            }
                            
                            // Show comment if present
                            if let commentText = extractCommentContent(from: post.content), !commentText.isEmpty {
                                Text(commentText)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 2)
                            }
                            
                            // Note content using SharedNoteView
                            SharedNoteView(note: extractNoteContent(from: post.content))
                        }
                        .padding(.horizontal, 16)
                    } 
                    // Hand post with session badge
                    else if post.postType == .hand {
                        VStack(alignment: .leading, spacing: 12) {
                            // Session badge at the top
                            if let (gameName, stakes) = extractSessionInfo(from: post.content) {
                                SessionBadgeView(
                                    gameName: gameName,
                                    stakes: stakes
                                )
                                .padding(.bottom, 8)
                            }
                            
                            // Comment text for the hand (excluding SESSION_INFO)
                            if let commentText = extractCommentContent(from: post.content), !commentText.isEmpty {
                                Text(commentText)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    // Regular session post (chip update)
                    else if let parsed = parseSessionContent(from: post.content) {
                        VStack(alignment: .leading, spacing: 12) {
                            LiveSessionStatusView(
                                gameName: parsed.gameName,
                                stakes: parsed.stakes,
                                chipAmount: parsed.chipAmount,
                                buyIn: parsed.buyIn,
                                elapsedTime: parsed.elapsedTime,
                                isLive: true
                            )
                            .padding(.bottom, 12)
                            
                            if !parsed.actualContent.isEmpty {
                                Text(parsed.actualContent)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                    } 
                    // Fallback for other session posts
                    else {
                        Text(post.content)
                            .font(.system(size: 17))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                } 
                // Check for non-session notes
                else if isNote(content: post.content) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Comment text
                        if let commentText = extractCommentContent(from: post.content), !commentText.isEmpty {
                            Text(commentText)
                                .font(.system(size: 17))
                                .foregroundColor(.white.opacity(0.95))
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 2)
                        }
                        
                        // Note content
                        SharedNoteView(note: extractNoteContent(from: post.content))
                    }
                    .padding(.horizontal, 16)
                }
                // Regular post
                else {
                    Text(post.content)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
            
            // Hand post content
            if post.postType == .hand, let hand = post.handHistory {
                Button(action: {
                    showingReplay = true
                }) {
                    HandSummaryView(hand: hand, onReplayTap: {
                        showingReplay = true
                    })
                }
                .padding(.top, 4)
                .padding(.horizontal, 16)
            }
            
            // Images with enhanced styling
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                VStack(alignment: .leading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(imageURLs, id: \.self) { url in
                                if let imageUrl = URL(string: url) {
                                    KFImage(imageUrl)
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
                                        .frame(width: 250, height: 220)
                                        .clipShape(Rectangle()) // Changed from RoundedRectangle for image gallery style
                                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedImageURL = url
                                            showingFullScreenImage = true
                                        }
                                }
                            }
                        }
                        .padding(.leading, 16) // Keep horizontal padding for the content within ScrollView
                        .padding(.trailing, 8) // Adjusted for better spacing
                    }
                }
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
                                print("Diagnostic onDelete() for top-level comment ID: \(comment.id ?? "N/A")")
                                // self.handleDeleteAction(commentId: comment.id ?? "", parentComment: nil) // Original logic temporarily bypassed
                            },
                            areRepliesExpanded: commentToExpandReplies?.id == comment.id && (replies[comment.id ?? ""]?.isEmpty == false)
                        )
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
                                                print("Diagnostic onDelete() for reply ID: \(reply.id ?? "N/A") to parent: \(comment.id ?? "N/A")")
                                                // self.handleDeleteAction(commentId: reply.id ?? "", parentComment: comment) // Original logic temporarily bypassed
                                            },
                                            areRepliesExpanded: false
                                        )
                                        
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


