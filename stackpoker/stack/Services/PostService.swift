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
    private var followingUserIds: [String] = []
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let postsPerPage = 10
    
    init() {
        setupAutoRefresh()
        
        // Add an observer to handle sign out cleanup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cleanupOnSignOut),
            name: NSNotification.Name("UserWillSignOut"),
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
    
    // Safely cleanup resources when called from within the actor
    @objc private func cleanupOnSignOut() {
        cleanupResources()
    }
    
    // Safe cleanup method for use within the actor context
    private func cleanupResources() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        posts = []
        followingUserIds = []
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
        // Set up auto refresh every 30 seconds
        autoRefreshCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    try? await self?.fetchPosts()
                }
            }
    }
    
    private func fetchFollowingUsers() async throws -> [String] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }
        
        // Add current user ID to include their posts in the feed
        var userIds: Set<String> = [currentUserId]
        
        // --- Legacy sub-collection (still in use by some parts of the app) ---
        let legacySnapshot = try await db.collection("users").document(currentUserId).collection("following").getDocuments()
        for document in legacySnapshot.documents {
            userIds.insert(document.documentID)
        }
        
        // --- New shared collection ---
        let newSnapshot = try await db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
            .getDocuments()
        for document in newSnapshot.documents {
            if let followeeId = document.data()["followeeId"] as? String {
                userIds.insert(followeeId)
            }
        }
        
        return Array(userIds)
    }
    
    func fetchPosts() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Ensure followingUserIds is up-to-date
            self.followingUserIds = try await fetchFollowingUsers()
            
            guard !self.followingUserIds.isEmpty else {
                // If not following anyone (including self), clear posts and return
                self.posts = []
                self.lastDocument = nil
                return
            }

            let batchSize = 10 // Firebase limit for 'in' queries
            var allFetchedPosts: [Post] = []
            
            // Use a Set to keep track of document IDs to avoid duplicates
            var processedPostIDs = Set<String>()

            // Define a larger limit for fetching posts per user batch initially,
            // to ensure we get enough candidates for the chronological feed.
            // This isn't an overall limit, but a per-batch fetch limit.
            let perBatchFetchLimit = 50 // Fetch up to 50 most recent posts per batch of users

            for i in stride(from: 0, to: self.followingUserIds.count, by: batchSize) {
                let end = min(i + batchSize, self.followingUserIds.count)
                let userIdBatch = Array(self.followingUserIds[i..<end])

                guard !userIdBatch.isEmpty else { continue }

                let query = db.collection("posts")
                    .whereField("userId", in: userIdBatch)
                    .order(by: "createdAt", descending: true)
                    .limit(to: perBatchFetchLimit) // Apply a per-batch limit here

                let batchSnapshot = try await query.getDocuments()
                let batchPosts = try await processPosts(from: batchSnapshot, existingIds: &processedPostIDs)
                allFetchedPosts.append(contentsOf: batchPosts)
            }

            // Sort all collected posts by creation date to get the true most recent
            allFetchedPosts.sort { $0.createdAt > $1.createdAt }

            // Now apply the overall desired size for the initial feed load
            let overallInitialLoadSize = 20 // Display 20 posts for the initial feed
            self.posts = Array(allFetchedPosts.prefix(overallInitialLoadSize))
            
            // lastDocument logic for pagination will be based on the timestamp of the oldest loaded post,
            // so we don't need to store a specific DocumentSnapshot here for the new fetchMorePosts logic.
            self.lastDocument = nil

        } catch {
            // Consider more specific error handling or re-throwing

            throw error
        }
    }
    
    // Helper for processing posts and avoiding duplicates
    private func processPosts(from snapshot: QuerySnapshot, existingIds: inout Set<String>) async throws -> [Post] {
        var posts: [Post] = []
        for document in snapshot.documents {
            let postId = document.documentID // Assign directly, documentID is non-optional
            if !existingIds.contains(postId) {
                do {
                    var post = try document.data(as: Post.self)
                    post.id = postId // Assign the non-optional postId
                    // Check likes status for the current user
                    if let userId = Auth.auth().currentUser?.uid {
                        let likeDoc = try? await db.collection("posts")
                            .document(postId)
                            .collection("likes")
                            .document(userId)
                            .getDocument()
                        if let likeDoc = likeDoc, likeDoc.exists {
                            post.isLiked = true
                        }
                    }
                    posts.append(post)
                    existingIds.insert(postId)
                } catch {

                }
            }
        }
        return posts
    }
    
    func fetchMorePosts() async throws {
        // Use the timestamp of the oldest post currently loaded for pagination
        guard let oldestPost = self.posts.last else {
            // No posts loaded yet. Cannot paginate.

            return
        }
        let oldestPostTimestamp = oldestPost.createdAt // createdAt is non-optional

        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        // Ensure we have following user IDs
        if self.followingUserIds.isEmpty {
            self.followingUserIds = try await fetchFollowingUsers()
        }
        
        guard !self.followingUserIds.isEmpty else {

            return
        }

        var newlyFetchedPosts: [Post] = []
        let batchSize = 10
        var processedPostIDs = Set<String>(self.posts.compactMap { $0.id }) // Exclude already loaded posts

        // Define a larger limit for fetching posts per user batch during pagination.
        let perBatchFetchLimitForMore = 30 // Fetch up to 30 older posts per batch of users

        for i in stride(from: 0, to: self.followingUserIds.count, by: batchSize) {
            let end = min(i + batchSize, self.followingUserIds.count)
            let userIdBatch = Array(self.followingUserIds[i..<end])

            guard !userIdBatch.isEmpty else { continue }

            // Query for posts older than the current oldest post
            let query = db.collection("posts")
                .whereField("userId", in: userIdBatch)
                .whereField("createdAt", isLessThan: oldestPostTimestamp) // Fetch posts older than the oldest one we have
                .order(by: "createdAt", descending: true) // Still order by most recent among the older ones
                .limit(to: perBatchFetchLimitForMore) // Apply a per-batch limit here

            let batchSnapshot = try await query.getDocuments()
            let batchPosts = try await processPosts(from: batchSnapshot, existingIds: &processedPostIDs)
            newlyFetchedPosts.append(contentsOf: batchPosts)
        }

        // Sort all newly fetched older posts to maintain order
        newlyFetchedPosts.sort { $0.createdAt > $1.createdAt }
        
        // Append a reasonable number of these new posts to the main posts array
        let paginationPageSize = 10 // Add 10 more posts when paginating
        if !newlyFetchedPosts.isEmpty {
            self.posts.append(contentsOf: Array(newlyFetchedPosts.prefix(paginationPageSize)))
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
        }
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
