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
            // Use AppBackgroundView for the main background
            AppBackgroundView(edges: .all)
            
            VStack(spacing: 0) {
                // Feed content
                if postService.isLoading && postService.posts.isEmpty {
            VStack {
                Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                            .padding(.bottom, 16)
                        
                        Text("Loading posts...")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                } else if postService.posts.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.bottom, 16)
                        
                        Text("No posts yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                    .foregroundColor(.white)
                            .padding(.bottom, 8)
                        
                        Text("Create a post or follow more players to see content in your feed")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) { // Increased spacing between posts
                            ForEach(postService.posts) { post in
                                // Enhanced post card
                                PostCardView(post: post)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6) // Added vertical padding
                                    .background(
                                        // Glass effect background
                                        RoundedRectangle(cornerRadius: 0)
                                            .fill(Color.black.opacity(0.2))
                                            .background(
                                                // Subtle gradient overlay
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 30/255, green: 30/255, blue: 40/255).opacity(0.35),
                                                        Color(red: 15/255, green: 15/255, blue: 25/255).opacity(0.25)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                .blendMode(.overlay)
                                            )
                                            .overlay(
                                                // Subtle border
                                                RoundedRectangle(cornerRadius: 0)
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [
                                                                Color.white.opacity(0.09),
                                                                Color.white.opacity(0.05),
                                                                Color.clear,
                                                                Color.clear
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                                    .onTapGesture {
                                        selectedPost = post
                                    }
                            }
                            
                            // Load more indicator
                            if postService.hasMorePosts && !postService.posts.isEmpty {
                                ProgressView()
                                    .tint(.white.opacity(0.7))
                                    .padding(.vertical, 20)
                                    .onAppear {
                                        postService.loadMorePosts()
                                    }
                            }
                            
                            // Spacer at bottom
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(height: 80) // Space for floating action button
                        }
                        .padding(.top, 16)
                    }
                    .refreshable {
                        Task {
                            await postService.refreshPosts()
                        }
                    }
                }
            }
            
            // Floating action button for new post
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            showingNewPost = true
                        }
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 60, height: 60)
                            .background(
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 123/255, green: 255/255, blue: 99/255),
                                                    Color(red: 150/255, green: 255/255, blue: 120/255)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                }
                            )
                            .shadow(
                                color: Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.4),
                                radius: 10,
                                x: 0,
                                y: 4
                            )
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.9))
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        
        return NavigationView {
            feedContent
                .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
                .toolbar {
                    // Leading: Feed title with animated gradient
                    ToolbarItem(placement: .navigationBarLeading) {
                        Text("FEED")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 123/255, green: 255/255, blue: 99/255),
                                        Color(red: 140/255, green: 255/255, blue: 120/255),
                                        Color(red: 160/255, green: 255/255, blue: 140/255)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.5), radius: 3, x: 0, y: 0)
                            .tracking(1.5)
                            .padding(.leading, 4)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingDiscoverUsers = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                }
                .toolbarBackground(
                    // Custom toolbar background with glass effect
                    ZStack {
                        Color.black.opacity(0.75)
                        
                        // Subtle texture
                        Rectangle()
                            .fill(
                                Color.white.opacity(0.03)
                            )
                            .blendMode(.overlay)
                        
                        // Bottom highlight
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.07),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 1)
                        }
                    },
                    for: .navigationBar
                )
                .toolbarBackground(.visible, for: .navigationBar)
                .onAppear {
                    if postService.posts.isEmpty {
                        Task {
                            await postService.fetchPosts()
                        }
                    }
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
    
    // Enhance PostCardView
    struct PostCardView: View {
        let post: Post
        @EnvironmentObject var postService: PostService
        @EnvironmentObject var userService: UserService
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // User profile section
                HStack(spacing: 12) {
                    // Enhanced profile image
                    AsyncImage(url: URL(string: post.authorProfileImage)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if phase.error != nil {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .foregroundColor(.gray)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.white.opacity(0.1), radius: 3, x: 0, y: 0)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(post.authorUsername)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(post.createdAt.timeAgo())
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Post content - text with better styling
                if !post.text.isEmpty {
                    Text(post.text)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(5) // Better line spacing
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
                
                // Hand summary if exists
                if post.hand != nil {
                    HandSummaryView(hand: post.hand!, isHovered: false)
                        .padding(.horizontal, 16)
                }
                
                // Images if any
                if !post.images.isEmpty {
                    ImagesGalleryView(urls: post.images)
                        .frame(maxHeight: 300)
                        .cornerRadius(0)
                }
                
                // Action buttons
                HStack(spacing: 20) {
                    // Like button
                    Button(action: {
                        if post.isLiked {
                            Task {
                                await postService.unlikePost(post)
                            }
                        } else {
                            Task {
                                await postService.likePost(post)
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(post.isLiked ? Color(red: 255/255, green: 100/255, blue: 100/255) : .white.opacity(0.85))
                            
                            Text("\(post.likeCount)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    
                    // Comment button
                    Button(action: {
                        // TBD for comment action
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.85))
                            
                            Text("\(post.commentCount)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    
                    Spacer()
                }
                    .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
        }
    }
}

// Basic Post Card View - For regular posts (without replay button)
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
        VStack(spacing: 0) {
            // User info header with delete button for user's own posts
            HStack(spacing: 10) {
                // Profile image with glow effect
                Group {
                    if let profileImage = post.profileImage {
                        KFImage(URL(string: profileImage))
                            .placeholder {
                                Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 2)
                    } else {
                        Circle()
                            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(post.createdAt.timeAgo())
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                Spacer()
                
                // Delete button (only for user's own posts)
                if isCurrentUser {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.7))
                            .padding(8)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // Post content
            VStack(alignment: .leading, spacing: 12) {
                if !post.content.isEmpty {
                    Text(post.content)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                
                // Images
                if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
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
                                        .clipShape(Rectangle())
                                        .overlay(
                                            Rectangle()
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Light separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 8)
            
            // Actions - No replay button
            HStack(spacing: 24) {
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isLiked ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .gray.opacity(0.7))
                            .scaleEffect(animateLike ? 1.3 : 1.0)
                        
                        Text("\(post.likes)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
                
                Button(action: onComment) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Text("\(post.comments)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
                    .background(
            // Refined card background with enhanced gradient and glass effect
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 22/255, green: 22/255, blue: 28/255),
                                Color(red: 25/255, green: 25/255, blue: 32/255)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Top highlight
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.07),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 1.5)
                    Spacer()
                }
                
                // Subtle edge highlights
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
}

// Post Card View - Enhanced version with replay button for hand posts
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
        VStack(spacing: 0) {
            // User info header with delete button
            HStack(spacing: 10) {
                // Profile image with glow effect
                Group {
                    if let profileImage = post.profileImage {
                        KFImage(URL(string: profileImage))
                            .placeholder {
                                Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 2)
                    } else {
                        Circle()
                            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(post.createdAt.timeAgo())
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                Spacer()
                
                // Delete button (only for user's own posts)
                if isCurrentUser {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.7))
                            .padding(8)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // Post content
            VStack(alignment: .leading, spacing: 12) {
                if !post.content.isEmpty {
                    Text(post.content)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                
                // Hand post content with enhanced styling
                if post.postType == .hand, let hand = post.handHistory {
                    HandSummaryView(hand: hand, showReplayButton: false)
                        .padding(.top, 4)
                }
                
                // Images
                if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
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
                                        .clipShape(Rectangle())
                                        .overlay(
                                            Rectangle()
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Light separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 8)
            
            // Actions
            HStack(spacing: 24) {
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isLiked ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .gray.opacity(0.7))
                            .scaleEffect(animateLike ? 1.3 : 1.0)
                        
                        Text("\(post.likes)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
                
                Button(action: onComment) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Text("\(post.comments)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
                
                if post.postType == .hand {
                    Button(action: { showingReplay = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Replay")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.9)),
                                    Color(UIColor(red: 123/255, green: 230/255, blue: 99/255, alpha: 0.9))
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(
            // Refined card background with enhanced gradient and glass effect
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 22/255, green: 22/255, blue: 28/255),
                                Color(red: 25/255, green: 25/255, blue: 32/255)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Top highlight
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.07),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 1.5)
                    Spacer()
                }
                
                // Subtle edge highlights
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
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
    @State private var animateBackground = false
    
    var body: some View {
        ZStack {
            // Animated circular gradient in background
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.03),
                            Color(red: 0/255, green: 0/255, blue: 0/255, opacity: 0.0)
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: 300
                    )
                )
                .scaleEffect(animateBackground ? 1.1 : 0.9)
                .opacity(animateBackground ? 0.7 : 0.3)
                .blur(radius: 20)
        .onAppear {
                    withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                        animateBackground.toggle()
                    }
                }
            
            VStack(spacing: 36) {
                Spacer()
                
                // Icon with animation
                ZStack {
                    Circle()
                        .fill(Color(red: 22/255, green: 22/255, blue: 30/255))
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.black.opacity(0.3), radius: 20)
                    
                    Image(systemName: "newspaper")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.7),
                                    Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.2), radius: 15)
                
                VStack(spacing: 16) {
                    Text("Your feed is empty")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.7)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("Follow other players or create a post to\nstart seeing content here")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                }
                
                Button(action: showDiscoverUsers) {
                    Text("Find Players")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 40)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 123/255, green: 255/255, blue: 99/255),
                                    Color(red: 150/255, green: 255/255, blue: 120/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(
                            color: Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.4),
                            radius: 10,
                            x: 0,
                            y: 5
                        )
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.96))
                
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
            // Use AppBackgroundView instead of plain color
            AppBackgroundView(edges: .all)
            
            VStack(spacing: 0) {
                // Top header bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
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
                                        .fill(Color.black.opacity(0.3))
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    // Enhanced glass effect header
                    ZStack {
                        Rectangle()
                            .fill(Color(red: 16/255, green: 16/255, blue: 20/255, opacity: 0.92))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            
                        // Subtle highlight at bottom edge
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.08),
                                            Color.white.opacity(0.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 1)
                        }
                    }
                )
                
                // Content area
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Post header
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
                                        .frame(width: 46, height: 46)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                        .frame(width: 46, height: 46)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.username)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text(post.createdAt.timeAgo())
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.8))
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        
                        // Post content
                        VStack(alignment: .leading, spacing: 16) {
                            if !post.content.isEmpty {
                                Text(post.content)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // Hand post content
                            if post.postType == .hand, let hand = post.handHistory {
                                HandSummaryView(hand: hand, onReplayTap: { showingReplay = true })
                                    .padding(.top, 4)
                            }
                            
                            // Images
                            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                                ImagesGalleryView(
                                    imageURLs: imageURLs,
                                    onImageTap: { url in
                                        selectedImageURL = url
                                        showingFullScreenImage = true
                                    }
                                )
                                .padding(.top, 4)
                            }
                            
                            // Actions
                            HStack(spacing: 30) {
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
                                    HStack(spacing: 8) {
                                        Image(systemName: isLiked ? "heart.fill" : "heart")
                                            .font(.system(size: 18))
                                            .foregroundColor(isLiked ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .gray.opacity(0.7))
                                            .scaleEffect(animateLike ? 1.3 : 1.0)
                                        
                                        Text("\(post.likes)")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.gray.opacity(0.8))
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 18))
                                        .foregroundColor(.gray.opacity(0.7))
                                    
                                    Text("\(post.comments)")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.gray.opacity(0.8))
                                }
                                
                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 16)
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 16)
                        
                        // Comments section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Comments")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                            
                            if isLoadingComments {
                                // Loading state
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.6))))
                                        .scaleEffect(1.2)
                                    Spacer()
                                }
                                .padding()
                            } else if comments.isEmpty {
                                // No comments state
                                HStack {
                                    Spacer()
                                    VStack(spacing: 12) {
                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 36))
                                            .foregroundColor(.gray.opacity(0.3))
                                        
                                        Text("No comments yet")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.gray.opacity(0.7))
                                        
                                        Text("Be the first to comment")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                    .padding(.vertical, 30)
                                    Spacer()
                                }
                            } else {
                                // Comments list
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
                                .padding(.bottom, 16)
                            }
                        }
                        
                        // Space at the bottom to account for comment input
                        Color.clear
                            .frame(height: 80)
                    }
                }
                
                // Comment input field
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    HStack(spacing: 12) {
                        TextField("Add a comment...", text: $newCommentText)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(Color(red: 25/255, green: 25/255, blue: 30/255))
                            .cornerRadius(20)
                            .foregroundColor(.white)
                            .focused($isCommentFieldFocused)
                        
                        Button(action: addComment) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(newCommentText.isEmpty ? Color.gray.opacity(0.5) : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        }
                        .disabled(newCommentText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 18/255, green: 18/255, blue: 22/255))
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

// CommentRow
struct CommentRow: View {
    let comment: Comment
    let isCurrentUser: Bool
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile image
            Group {
                if let profileImage = comment.profileImage {
                    KFImage(URL(string: profileImage))
                        .placeholder {
                            Circle().fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        .frame(width: 34, height: 34)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(comment.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
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
    let scale: CGFloat
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
