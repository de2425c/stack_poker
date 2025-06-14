import Foundation
import FirebaseFirestore
import FirebaseStorage
import Combine
import FirebaseAuth

@MainActor
class PostService: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var lastDocument: DocumentSnapshot?
    private var refreshTimer: Timer?
    private var autoRefreshCancellable: AnyCancellable?
    private var followingUserIds: Set<String> = []
    private var cachedPosts: [Post] = []
    private var lastCacheUpdate: Date?
    private var cachedFollowingUsers: Set<String> = []
    private var lastFollowingCacheUpdate: Date?
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let postsPerPage = 20
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes for better real-time updates
    private let followingCacheValidityDuration: TimeInterval = 1800 // 30 minutes for following users
    private let persistentCacheKey = "cached_posts_data"
    private let followingCacheKey = "cached_following_users"
    
    init() {
        loadPersistedCache()
        setupAutoRefresh()
        
        // Add an observer to handle sign out cleanup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cleanupOnSignOut),
            name: NSNotification.Name("UserWillSignOut"),
            object: nil
        )
        
        // Add observer to refresh feed when following relationships change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFollowingChanged),
            name: NSNotification.Name("UserFollowingChanged"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // In case notification-based cleanup didn't happen, we need to use a nonisolated method
        if autoRefreshCancellable != nil {
            performNonisolatedCleanup()
        }
    }
    
    // Load persisted cache from UserDefaults
    private func loadPersistedCache() {
        // Load cached posts
        if let data = UserDefaults.standard.data(forKey: persistentCacheKey),
           let cacheData = try? JSONDecoder().decode(CachedPostsData.self, from: data) {
            
            // Check if cache is still valid (within 2 hours for persistent cache)
            let persistentCacheValidityDuration: TimeInterval = 7200 // 2 hours
            if Date().timeIntervalSince(cacheData.timestamp) < persistentCacheValidityDuration {
                cachedPosts = cacheData.posts
                lastCacheUpdate = cacheData.timestamp
                
                // Show cached posts immediately for instant loading
                posts = Array(cachedPosts.prefix(postsPerPage))
                print("DEBUG: Loaded \(posts.count) posts from persistent cache")
            }
        }
        
        // Load cached following users
        if let data = UserDefaults.standard.data(forKey: followingCacheKey),
           let followingData = try? JSONDecoder().decode(CachedFollowingData.self, from: data) {
            
            if Date().timeIntervalSince(followingData.timestamp) < followingCacheValidityDuration {
                cachedFollowingUsers = Set(followingData.userIds)
                lastFollowingCacheUpdate = followingData.timestamp
                print("DEBUG: Loaded \(cachedFollowingUsers.count) following users from cache")
            }
        }
    }
    
    // Persist cache to UserDefaults
    private func persistCache() {
        // Persist posts cache
        let cacheData = CachedPostsData(posts: cachedPosts, timestamp: lastCacheUpdate ?? Date())
        if let encoded = try? JSONEncoder().encode(cacheData) {
            UserDefaults.standard.set(encoded, forKey: persistentCacheKey)
        }
        
        // Persist following users cache
        let followingData = CachedFollowingData(userIds: Array(cachedFollowingUsers), timestamp: lastFollowingCacheUpdate ?? Date())
        if let encoded = try? JSONEncoder().encode(followingData) {
            UserDefaults.standard.set(encoded, forKey: followingCacheKey)
        }
    }
    
    // Safely cleanup resources when called from within the actor
    @objc private func cleanupOnSignOut() {
        cleanupResources()
    }
    
    // Handle following relationship changes by refreshing feed
    @objc private func handleFollowingChanged() {
        Task {
            do {
                // Invalidate following cache and feed cache
                invalidateFollowingCache()
                invalidateCache()
                
                // Force a fresh fetch
                try await forceRefresh()
            } catch {
                print("ERROR: Failed to refresh feed after following change: \(error)")
            }
        }
    }
    
    // Safe cleanup method for use within the actor context
    private func cleanupResources() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        posts = []
        followingUserIds = []
        cachedPosts = []
        lastCacheUpdate = nil
        cachedFollowingUsers = []
        lastFollowingCacheUpdate = nil
        
        // Clear persistent cache on sign out
        UserDefaults.standard.removeObject(forKey: persistentCacheKey)
        UserDefaults.standard.removeObject(forKey: followingCacheKey)
    }
    
    // This method is explicitly nonisolated so it can be called from deinit
    private nonisolated func performNonisolatedCleanup() {
        // Since we're in a nonisolated context, we need to use Task to get back to the MainActor
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.autoRefreshCancellable?.cancel()
            self.autoRefreshCancellable = nil
            self.refreshTimer?.invalidate()
            self.refreshTimer = nil
            // Don't reset published properties as the object is being deallocated anyway
        }
    }
    
    private func setupAutoRefresh() {
        // Set up auto refresh every 2 minutes (less aggressive)
        autoRefreshCancellable = Timer.publish(every: 120, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    // Only auto-refresh if cache is getting stale (older than 10 minutes)
                    if let lastUpdate = self?.lastCacheUpdate,
                       Date().timeIntervalSince(lastUpdate) > 600 {
                        try? await self?.refreshInBackground()
                    }
                }
            }
    }
    
    // Background refresh that doesn't show loading state
    private func refreshInBackground() async throws {
        // Don't set isLoading = true for background refresh
        do {
            let oldPosts = posts
            try await fetchPostsInternal(showLoading: false)
            
            // Only update UI if we got new posts
            if posts.count != oldPosts.count || posts.first?.createdAt != oldPosts.first?.createdAt {
                print("DEBUG: Background refresh found new posts")
            }
        } catch {
            print("DEBUG: Background refresh failed: \(error)")
            // Don't throw error for background refresh
        }
    }
    
    private func fetchFollowingUsers() async throws -> Set<String> {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }
        
        // Check if we can use cached following users
        if let lastUpdate = lastFollowingCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < followingCacheValidityDuration,
           !cachedFollowingUsers.isEmpty {
            print("DEBUG: Using cached following users (\(cachedFollowingUsers.count) users)")
            return cachedFollowingUsers
        }
        
        var userIds: Set<String> = [currentUserId]
        
        let snapshot = try await db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
            .getDocuments()
        
        for document in snapshot.documents {
            if let followeeId = document.data()["followeeId"] as? String {
                userIds.insert(followeeId)
            }
        }
        
        // Cache the following users
        cachedFollowingUsers = userIds
        lastFollowingCacheUpdate = Date()
        persistCache()
        
        return userIds
    }
    
    func fetchPosts() async throws {
        try await fetchPostsInternal(showLoading: true)
    }
    
    private func fetchPostsInternal(showLoading: Bool) async throws {
        if showLoading {
            isLoading = true
        }
        defer { 
            if showLoading {
                isLoading = false 
            }
        }
        
        do {
            // Get all user IDs we want to see posts from (current user + following)
            self.followingUserIds = try await fetchFollowingUsers()
            
            print("DEBUG: Following \(followingUserIds.count) users: \(Array(followingUserIds).prefix(5))...")
            
            // Debug: Print if user is following themselves
            if let currentUserId = Auth.auth().currentUser?.uid {
                print("DEBUG: Current user ID: \(currentUserId), included in following: \(followingUserIds.contains(currentUserId))")
            }
            
            guard !self.followingUserIds.isEmpty else {
                self.posts = []
                self.lastDocument = nil
                return
            }
            
            // Check if we can use cached posts (if cache is still valid)
            if let lastUpdate = lastCacheUpdate,
               Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
               !cachedPosts.isEmpty {
                print("DEBUG: Using cached posts (\(cachedPosts.count) total)")
                self.posts = Array(cachedPosts.prefix(postsPerPage))
                return
            }
            
            var allPosts: [Post] = []
            
            // If we have 10 or fewer users to follow, we can use Firebase 'in' query efficiently
            if followingUserIds.count <= 10 {
                print("DEBUG: Using efficient 'in' query for \(followingUserIds.count) users")
                allPosts = try await fetchPostsWithInQuery(userIds: Array(followingUserIds))
            } else {
                print("DEBUG: Using client-side filtering for \(followingUserIds.count) users")
                allPosts = try await fetchPostsWithClientFiltering()
            }
            
            // Sort all posts chronologically
            allPosts.sort { $0.createdAt > $1.createdAt }
            
            print("DEBUG: Fetched \(allPosts.count) posts total")
            
            // Cache the results
            self.cachedPosts = allPosts
            self.lastCacheUpdate = Date()
            persistCache()
            
            // Set the posts for display
            self.posts = Array(allPosts.prefix(postsPerPage))
            self.lastDocument = nil // Reset for new fetch
            
            print("DEBUG: Displaying \(posts.count) posts")
            
        } catch {
            print("ERROR: Failed to fetch posts: \(error)")
            throw error
        }
    }
    
    // Efficient method for ≤10 followed users
    private func fetchPostsWithInQuery(userIds: [String]) async throws -> [Post] {
        let query = db.collection("posts")
            .whereField("userId", in: userIds)
            .order(by: "createdAt", descending: true)
            .limit(to: 100) // Fetch more to ensure we have enough after processing
        
        let snapshot = try await query.getDocuments()
        var processedIds = Set<String>()
        return try await processPosts(from: snapshot, existingIds: &processedIds)
    }
    
    // Method for >10 followed users - fetch chronologically and filter
    private func fetchPostsWithClientFiltering() async throws -> [Post] {
        // Fetch recent posts chronologically (more than we need)
        let query = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: 200) // Fetch 200 most recent posts from all users
        
        let snapshot = try await query.getDocuments()
        var processedIds = Set<String>()
        let allRecentPosts = try await processPosts(from: snapshot, existingIds: &processedIds)
        
        // Filter for only users we follow
        return allRecentPosts.filter { post in
            followingUserIds.contains(post.userId)
        }
    }
    
    // Helper for processing posts and avoiding duplicates - now with batched like checks
    private func processPosts(from snapshot: QuerySnapshot, existingIds: inout Set<String>) async throws -> [Post] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            // If no current user, process posts without like status
            return try snapshot.documents.compactMap { document in
                let postId = document.documentID
                guard !existingIds.contains(postId) else { return nil }
                
                var post = try document.data(as: Post.self)
                post.id = postId
                post.isLiked = false
                existingIds.insert(postId)
                return post
            }
        }
        
        var posts: [Post] = []
        var postIds: [String] = []
        
        // First pass: create posts without like status
        for document in snapshot.documents {
            let postId = document.documentID
            if !existingIds.contains(postId) {
                do {
                    var post = try document.data(as: Post.self)
                    post.id = postId
                    post.isLiked = false // Default to false
                    posts.append(post)
                    postIds.append(postId)
                    existingIds.insert(postId)
                } catch {
                    // Log error but continue processing other posts
                    print("Error processing post \(postId): \(error)")
                }
            }
        }
        
        // Batch check like status for all posts at once
        await withTaskGroup(of: (String, Bool).self) { group in
            for postId in postIds {
                group.addTask {
                    let likeDoc = try? await self.db.collection("posts")
                        .document(postId)
                        .collection("likes")
                        .document(currentUserId)
                        .getDocument()
                    return (postId, likeDoc?.exists == true)
                }
            }
            
            // Collect results and update posts
            for await (postId, isLiked) in group {
                if let index = posts.firstIndex(where: { $0.id == postId }) {
                    posts[index].isLiked = isLiked
                }
            }
        }
        
        return posts
    }
    
    func fetchMorePosts() async throws {
        guard !isLoading, !posts.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let oldestPost = posts.last!
        let oldestTimestamp = oldestPost.createdAt
        
        // Ensure we have following user IDs
        if followingUserIds.isEmpty {
            followingUserIds = try await fetchFollowingUsers()
        }
        
        guard !followingUserIds.isEmpty else { return }
        
        var newPosts: [Post] = []
        
        if followingUserIds.count <= 10 {
            // Use 'in' query for efficient pagination
            let query = db.collection("posts")
                .whereField("userId", in: Array(followingUserIds))
                .whereField("createdAt", isLessThan: oldestTimestamp)
                .order(by: "createdAt", descending: true)
                .limit(to: postsPerPage)
            
            let snapshot = try await query.getDocuments()
            var existingIds = Set<String>(posts.compactMap { $0.id })
            newPosts = try await processPosts(from: snapshot, existingIds: &existingIds)
            
        } else {
            // Fetch older posts and filter
            let query = db.collection("posts")
                .whereField("createdAt", isLessThan: oldestTimestamp)
                .order(by: "createdAt", descending: true)
                .limit(to: 100) // Fetch more candidates
            
            let snapshot = try await query.getDocuments()
            var existingIds = Set<String>(posts.compactMap { $0.id })
            let candidatePosts = try await processPosts(from: snapshot, existingIds: &existingIds)
            
            // Filter for followed users and limit
            newPosts = candidatePosts
                .filter { followingUserIds.contains($0.userId) }
                .prefix(postsPerPage)
                .map { $0 }
        }
        
        // Sort and append new posts
        newPosts.sort { $0.createdAt > $1.createdAt }
        self.posts.append(contentsOf: newPosts)
        
        // Update cache if we're using it
        if !cachedPosts.isEmpty {
            cachedPosts.append(contentsOf: newPosts)
            cachedPosts.sort { $0.createdAt > $1.createdAt }
        }
    }
    
    func uploadImage(_ image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert image to data"])
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("post_images/\(filename)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL.absoluteString
    }
    
    func uploadImages(images: [UIImage], userId: String) async throws -> [String] {
        return try await withThrowingTaskGroup(of: String.self) { group in
            for image in images {
                group.addTask {
                    try await self.uploadImage(image)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
    }
    
    // Keep this compatibility method for old code that still uses it
    func createPost(content: String, userId: String, username: String, displayName: String? = nil, profileImage: String?, images: [UIImage]? = nil, sessionId: String? = nil, isNote: Bool = false) async throws {
        // Upload images if present
        var imageURLs: [String]? = nil
        if let images = images {
            imageURLs = try await uploadImages(images: images, userId: userId)
        }
        
        // Call the main createPost method
        try await createPost(
            content: content,
            userId: userId,
            username: username,
            displayName: displayName,
            profileImage: profileImage,
            imageURLs: imageURLs,
            postType: .text,
            handHistory: nil,
            sessionId: sessionId,
            location: nil,
            isNote: isNote // Pass the provided isNote value
        )
    }
    
    // Cache management
    private func invalidateCache() {
        cachedPosts = []
        lastCacheUpdate = nil
        UserDefaults.standard.removeObject(forKey: persistentCacheKey)
    }
    
    // Force refresh without using cache
    func forceRefresh() async throws {
        invalidateCache()
        invalidateFollowingCache() // Also invalidate following cache for fresh relationships
        try await fetchPosts()
    }
    
    // Cache management for following users
    private func invalidateFollowingCache() {
        cachedFollowingUsers = []
        lastFollowingCacheUpdate = nil
        UserDefaults.standard.removeObject(forKey: followingCacheKey)
    }
    
    func createPost(content: String, userId: String, username: String, displayName: String? = nil, profileImage: String?, imageURLs: [String]? = nil, postType: Post.PostType = .text, handHistory: ParsedHandHistory? = nil, sessionId: String? = nil, location: String? = nil, isNote: Bool = false) async throws {
        let documentRef = db.collection("posts").document()
        
        let post = Post(
            id: documentRef.documentID,
            userId: userId,
            content: content,
            createdAt: Date(),
            username: username,
            displayName: displayName,
            profileImage: profileImage,
            imageURLs: imageURLs,
            likes: 0,
            comments: 0,
            postType: postType,
            handHistory: handHistory,
            sessionId: sessionId,
            location: location,
            isNote: isNote
        )
        
        try await documentRef.setData(from: post)
        
        await MainActor.run {
            posts.insert(post, at: 0)
            // Invalidate cache since we have new content
            invalidateCache()
        }
        
        print("DEBUG: Created new post, total posts in memory: \(posts.count)")
    }
    
    func createHandPost(content: String, userId: String, username: String, displayName: String?, profileImage: String?, hand: ParsedHandHistory, sessionId: String?, location: String?) async throws {
        try await createPost(
            content: content,
            userId: userId,
            username: username,
            displayName: displayName,
            profileImage: profileImage,
            imageURLs: nil,
            postType: .hand,
            handHistory: hand,
            sessionId: sessionId,
            location: location,
            isNote: false
        )
    }
    
    func toggleLike(postId: String, userId: String) async throws {
        let postRef = db.collection("posts").document(postId)
        let likeRef = postRef.collection("likes").document(userId)
        
        let document = try await likeRef.getDocument()
        if document.exists {
            // Unlike
            try await likeRef.delete()
            try await postRef.updateData(["likes": FieldValue.increment(Int64(-1))])
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == postId }) {
                    posts[index].likes -= 1
                    posts[index].isLiked = false
                }
            }
        } else {
            // Like
            try await likeRef.setData(["timestamp": FieldValue.serverTimestamp()])
            try await postRef.updateData(["likes": FieldValue.increment(Int64(1))])
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == postId }) {
                    posts[index].likes += 1
                    posts[index].isLiked = true
                }
            }
        }
    }
    
    func deletePost(postId: String) async throws {
        try await db.collection("posts").document(postId).delete()
        await MainActor.run {
            posts.removeAll { $0.id == postId }
        }
    }
    
    // Get comments for a post (filters for top-level comments client-side)
    func getComments(for postId: String) async throws -> [Comment] {
        let commentsRef = db.collection("posts").document(postId).collection("comments")
        // Fetch all comments for the post, order by creation date
        let snapshot = try await commentsRef
            .order(by: "createdAt", descending: false)
            .getDocuments()

        let allComments = try snapshot.documents.compactMap { document -> Comment? in
            // Ensure you handle potential decoding errors gracefully
            do {
                var comment = try document.data(as: Comment.self)
                comment.id = document.documentID
                return comment
            } catch {

                return nil
            }
        }
        
        // Filter for top-level comments (where parentCommentId is nil or empty string)
        // This handles new comments (parentCommentId explicitly null),
        // old comments (parentCommentId field might be missing, decoding to nil for Optional type),
        // or very old comments (parentCommentId might be an empty string).
        let topLevelComments = allComments.filter { $0.parentCommentId == nil || $0.parentCommentId == "" }
        
        return topLevelComments
    }
    
    // Get replies for a specific comment
    func getReplies(for parentCommentId: String, on postId: String) async throws -> [Comment] {
        let commentsRef = db.collection("posts").document(postId).collection("comments")
        let snapshot = try await commentsRef
            .whereField("parentCommentId", isEqualTo: parentCommentId)
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return try snapshot.documents.compactMap { document in
            var comment = try document.data(as: Comment.self)
            comment.id = document.documentID
            return comment
        }
    }
    
    // Add a comment to a post or reply to a comment
    func addComment(to postId: String, userId: String, username: String, profileImage: String?, content: String, parentCommentId: String? = nil) async throws {
        let postRef = db.collection("posts").document(postId)
        let commentRef = postRef.collection("comments").document()

        let isReply = parentCommentId != nil
        let newComment = Comment(
            id: commentRef.documentID,
            postId: postId,
            userId: userId,
            username: username,
            profileImage: profileImage,
            content: content,
            createdAt: Date(),
            parentCommentId: parentCommentId,
            replies: 0, // Replies will be 0 for new comments/replies initially
            isReplyable: !isReply // Top-level comments are replyable, replies are not
        )

        try await commentRef.setData(from: newComment)

        if isReply {
            // Increment replies count on the parent comment
            if let parentId = parentCommentId {
                let parentCommentRef = postRef.collection("comments").document(parentId)
                try await parentCommentRef.updateData(["replies": FieldValue.increment(Int64(1))])
                // Note: Post.comments count is not directly incremented for replies here.
                // The overall count of interactions might be managed differently or Post.comments refers only to top-level.
            }
        } else {
            // Increment comment count on the post for top-level comments
            try await postRef.updateData(["comments": FieldValue.increment(Int64(1))])
            
            // Update local post object
            // Ensure this runs on the main actor if posts is a @Published property
            await MainActor.run {
                if let index = self.posts.firstIndex(where: { $0.id == postId }) {
                    self.posts[index].comments += 1
                }
            }
        }
    }
    
    // Delete a comment (and its replies if it's a top-level comment)
    // Or delete a reply
    func deleteComment(postId: String, commentId: String) async throws {
        let postRef = db.collection("posts").document(postId)
        let commentRef = postRef.collection("comments").document(commentId)

        // Fetch the comment to determine if it's a top-level or a reply, and if it has replies
        let commentSnapshot = try await commentRef.getDocument()
        guard commentSnapshot.exists, var commentData = try? commentSnapshot.data(as: Comment.self) else {

            throw NSError(domain: "CommentError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Comment not found or could not be decoded"])
        }
        commentData.id = commentSnapshot.documentID // Ensure ID is set

        try await commentRef.delete()

        if let parentId = commentData.parentCommentId { // This is a reply being deleted
            // Decrement replies count on the parent comment
            let parentCommentRef = postRef.collection("comments").document(parentId)
            try await parentCommentRef.updateData(["replies": FieldValue.increment(Int64(-1))])
            // Post.comments count is not affected by deleting a reply directly.
        } else { // This is a top-level comment being deleted
            // Decrement comment count on the post
            try await postRef.updateData(["comments": FieldValue.increment(Int64(-1))])
            
            await MainActor.run {
                if let index = self.posts.firstIndex(where: { $0.id == postId }) {
                    if self.posts[index].comments > 0 { // Ensure counter doesn't go negative
                         self.posts[index].comments -= 1
                    }
                }
            }

            // If it was a replyable comment and had replies, delete its replies
            if commentData.isReplyable && commentData.replies > 0 {
                let repliesSnapshot = try await postRef.collection("comments")
                    .whereField("parentCommentId", isEqualTo: commentId)
                    .getDocuments()
                
                for replyDoc in repliesSnapshot.documents {
                    try await replyDoc.reference.delete()
                    // Note: We don't need to individually decrement parent's reply count here,
                    // as the parent (the comment being deleted) is gone.
                }
            }
        }
    }
    
    // Add a method to get posts for a specific session
    func getSessionPosts(sessionId: String) async -> [Post] {
        do {
            let query = db.collection("posts")
                .whereField("sessionId", isEqualTo: sessionId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
            
            let snapshot = try await query.getDocuments()
            
            var existingIds = Set<String>() // Initialize an empty set for this context
            return try await processPosts(from: snapshot, existingIds: &existingIds)
        } catch {

            return []
        }
    }
    
    // MARK: - Fetching Posts for a Specific User
    func fetchPosts(forUserId userId: String) async throws {
        isLoading = true
        defer { isLoading = false }



        let query = db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: postsPerPage * 2) // Fetch a decent amount for initial load

        do {
            let snapshot = try await query.getDocuments()
            var fetchedPosts: [Post] = []
            var processedPostIDs = Set<String>() // To avoid duplicates if any, though unlikely for single user fetch

            // Use the existing processPosts helper
            fetchedPosts = try await processPosts(from: snapshot, existingIds: &processedPostIDs)
            
            // Assign to the main posts array for this service instance
            // This assumes this PostService instance on UserProfileView is dedicated to that profile's posts
            self.posts = fetchedPosts
            
            // Set lastDocument for potential pagination if we implement "load more" on profile
            // For now, the primary use case is fetching the initial set.
            self.lastDocument = snapshot.documents.last 
            


        } catch {

            // Clear posts on error or handle as needed
            self.posts = []
            self.lastDocument = nil
            throw error
        }
    }
    
    // MARK: - Fetching Single Post by ID
    func fetchSinglePost(byId postId: String) async throws -> Post? {

        let documentSnapshot = try await db.collection("posts").document(postId).getDocument()
        
        guard documentSnapshot.exists else {

            return nil
        }
        
        do {
            var post = try documentSnapshot.data(as: Post.self)
            post.id = documentSnapshot.documentID // Ensure ID is set from the document

            // Optionally, fetch like status for the current user if PostDetailView needs it
            // and if your Post model has an `isLiked` property.
            if let currentUserId = Auth.auth().currentUser?.uid {
                let likeDocRef = db.collection("posts").document(postId).collection("likes").document(currentUserId)
                let likeDoc = try? await likeDocRef.getDocument() // Use try? to not fail if like doc doesn't exist
                if let likeDoc = likeDoc, likeDoc.exists {
                    post.isLiked = true // Assuming your Post model has `isLiked: Bool?` or `isLiked: Bool = false`
                } else {
                    post.isLiked = false // Ensure isLiked is set even if no like document exists
                }
            }
            

            return post
        } catch {

            // It might be better to throw a specific error or return nil depending on desired behavior
            // For now, re-throwing the decoding error.
            throw error 
        }
    }
}

// MARK: - Cache Data Structures
private struct CachedPostsData: Codable {
    let posts: [Post]
    let timestamp: Date
}

private struct CachedFollowingData: Codable {
    let userIds: [String]
    let timestamp: Date
} 
