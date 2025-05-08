import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import Kingfisher

struct FeedView: View {
    @StateObject private var postService = PostService()
    @EnvironmentObject var userService: UserService
    @State private var showingNewPost = false
    @State private var isRefreshing = false
    @State private var showingDiscoverUsers = false
    @State private var selectedPost: Post? = nil
    @State private var showingFullScreenImage = false
    @State private var selectedImageURL: String? = nil
    
    let userId: String
    
    init(userId: String = Auth.auth().currentUser?.uid ?? "") {
        self.userId = userId
        
        // Configure the Kingfisher cache
        let cache = ImageCache.default
        
        // Set memory cache limit correctly as Int
        let memoryCacheMB = 300
        cache.memoryStorage.config.totalCostLimit = memoryCacheMB * 1024 * 1024
        
        // Set disk cache limit (breaking into simpler expressions)
        let diskCacheMB = UInt(1000)
        let diskCacheBytes = diskCacheMB
        let kilobytes = diskCacheBytes * 1024
        let bytes = kilobytes * 1024
        cache.diskStorage.config.sizeLimit = bytes
        
        // Configure navigation bar appearance to prevent white bar when scrolling
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(red: 12/255, green: 12/255, blue: 16/255, alpha: 1.0)
        appearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    var body: some View {
        let feedContent = ZStack {
            // Use the AppBackgroundView for a rich background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
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
                                Group {
                                    if post.postType == .hand {
                                        // Use the full card view with replay for hand posts
                                        PostCardView(
                                            post: post,
                                            onLike: { likePost(post) },
                                            onComment: { selectedPost = post },
                                            onDelete: { deletePost(post) },
                                            isCurrentUser: post.userId == userId,
                                            userId: userId
                                        )
                                    } else {
                                        // Use the basic card view without replay for regular posts
                                        BasicPostCardView(
                                            post: post,
                                            onLike: { likePost(post) },
                                            onComment: { selectedPost = post },
                                            onDelete: { deletePost(post) },
                                            isCurrentUser: post.userId == userId
                                        )
                                    }
                                }
                                .contentShape(Rectangle()) // Make entire post tappable
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
                                
                                // Twitter-like divider between posts
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 0.5)
                            }
                            
                            // Loading indicator at bottom when fetching more
                            if postService.isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.6))))
                                        .scaleEffect(1.2)
                                    Spacer()
                                }
                                .padding()
                            }
                            
                            // Bottom padding for better scrolling experience
                            Color.clear.frame(height: 100)
                        }
                        .padding(.top, 1) // Minimal top padding
                    }
                    .refreshable {
                        // Pull to refresh
                        await refreshFeed()
                    }
                }
            }
        }
        
        return NavigationView {
            feedContent
                .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
                .toolbar {
                    // Leading: Feed title with enhanced styling
                    ToolbarItem(placement: .navigationBarLeading) {
                        Text("FEED")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white)
                            .tracking(1.5)
                            .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                            .padding(.leading, 4)
                    }
                    
                    // Add post button in top right
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingNewPost = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .navigationBarBackground {
                    Color(red: 14/255, green: 14/255, blue: 18/255).opacity(0.4)
                        .blur(radius: 3)
                        .ignoresSafeArea(edges: .top)
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
    @State private var comments: [Comment] = []
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
                        
                        // Post content with enhanced styling
                        VStack(alignment: .leading, spacing: 18) {
                            if !post.content.isEmpty {
                                Text(post.content)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                            }
                            
                            // Hand post content - with showReplayButton set to false
                            if post.postType == .hand, let hand = post.handHistory {
                                HandSummaryView(hand: hand, showReplayButton: false)
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
                                                        .clipShape(Rectangle())
                                                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            selectedImageURL = url
                                                            showingFullScreenImage = true
                                                        }
                                                }
                                            }
                                        }
                                        .padding(.leading, 16)
                                        .padding(.trailing, 8)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
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
                                
                                // Removed the Replay button here
                                
                                Spacer()
                            }
                            .padding(.top, 12)
                            .padding(.horizontal, 16)
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 16)
                        
                        // Comments section with enhanced styling
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
                                // Loading state with enhanced styling
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
                                // No comments state with enhanced styling
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
                                // Comments list with enhanced styling
                                VStack(spacing: 18) {
                                    ForEach(comments) { comment in
                                        CommentRow(
                                            comment: comment,
                                            isCurrentUser: comment.userId == userId,
                                            onDelete: {
                                                deleteComment(comment.id ?? "")
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                        
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
                            TextField("Add a comment...", text: $newCommentText)
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
        
        Task {
            do {
                if let postId = post.id {
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
    
    private func addComment() {
        guard !newCommentText.isEmpty, let postId = post.id else { return }
        
        // Get current user's profile image from userService
        let profileImage = userService.currentUserProfile?.avatarURL
        let username = userService.currentUserProfile?.username ?? "User"
        
        Task {
            do {
                try await postService.addComment(
                    to: postId,
                    userId: userId,
                    username: username,
                    profileImage: profileImage,
                    content: newCommentText
                )
                
                // Refresh comments
                let updatedComments = try await postService.getComments(for: postId)
                
                await MainActor.run {
                    comments = updatedComments
                    newCommentText = ""
                    isCommentFieldFocused = false
                }
            } catch {
                print("Error adding comment: \(error)")
            }
        }
    }
    
    private func deleteComment(_ commentId: String) {
        guard let postId = post.id else { return }
        
        Task {
            do {
                try await postService.deleteComment(postId: postId, commentId: commentId)
                
                // Refresh comments
                let updatedComments = try await postService.getComments(for: postId)
                
                await MainActor.run {
                    comments = updatedComments
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
    let onDelete: () -> Void
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
                                onDelete()
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
            }
        }
        .padding(.vertical, 10)
    }
}

// Scale Button Style - Enhanced with smoother animation
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
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
