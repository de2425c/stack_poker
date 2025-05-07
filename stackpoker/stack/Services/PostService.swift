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
        var userIds = [currentUserId]
        
        let snapshot = try await db.collection("users").document(currentUserId).collection("following").getDocuments()
        
        for document in snapshot.documents {
            userIds.append(document.documentID)
        }
        
        return userIds
    }
    
    func fetchPosts() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let followingUserIds = try await fetchFollowingUsers()
            
            // Always fetch posts regardless of how many users are being followed
            
            // Due to Firebase's limit on whereIn queries (max 10 items), we need to batch the requests
            let batchSize = 10
            var allPosts: [Post] = []
            
            // Process user IDs in batches of 10
            for i in stride(from: 0, to: followingUserIds.count, by: batchSize) {
                let end = min(i + batchSize, followingUserIds.count)
                let batch = Array(followingUserIds[i..<end])
                
                
                let query = db.collection("posts")
                    .whereField("userId", in: batch)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 20)
                
                let batchSnapshot = try await query.getDocuments()
                
                let batchPosts = try await processPosts(from: batchSnapshot)
                allPosts.append(contentsOf: batchPosts)
            }
            
            // Sort all posts by creation date
            allPosts.sort { $0.createdAt > $1.createdAt }
            
            // Limit to the most recent 20 posts total across all batches
            if allPosts.count > 20 {
                allPosts = Array(allPosts.prefix(20))
            }
            
            self.posts = allPosts
            self.lastDocument = nil  // Reset for pagination
            
        } catch {
            throw error
        }
    }
    
    func fetchMorePosts() async throws {
        guard let lastDocument = lastDocument, !isLoading else { return }
        
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Make sure we have following user IDs
        if followingUserIds.isEmpty {
            followingUserIds = try await fetchFollowingUsers()
        }
        
        guard !followingUserIds.isEmpty else { return }
        
        // Use a whereIn query to fetch posts from only these users
        let batchSize = 10
        var allPosts: [Post] = []
        var newLastDoc: DocumentSnapshot?
        
        // Process users in batches of 10 (Firebase limit for whereIn)
        for i in stride(from: 0, to: followingUserIds.count, by: batchSize) {
            let end = min(i + batchSize, followingUserIds.count)
            let userIdBatch = Array(followingUserIds[i..<end])
            
            let query = db.collection("posts")
                .whereField("userId", in: userIdBatch)
                .order(by: "createdAt", descending: true)
                .limit(to: postsPerPage)
                .start(afterDocument: lastDocument)
            
            let snapshot = try await query.getDocuments()
            
            // Keep track of the last document from all batches for pagination
            if newLastDoc == nil && !snapshot.documents.isEmpty {
                newLastDoc = snapshot.documents.last
            }
            
            let batchPosts = try snapshot.documents.compactMap { document in
                var post = try document.data(as: Post.self)
                post.id = document.documentID
                return post
            }
            
            allPosts.append(contentsOf: batchPosts)
        }
        
        // Sort all posts by created date (most recent first)
        allPosts.sort { $0.createdAt > $1.createdAt }
        
        // Limit to the next page
        if allPosts.count > postsPerPage {
            allPosts = Array(allPosts.prefix(postsPerPage))
        }
        
        // Check likes status for the current user
        if let userId = Auth.auth().currentUser?.uid {
            for i in 0..<allPosts.count {
                if let postId = allPosts[i].id {
                    let likeDoc = try? await db.collection("posts")
                        .document(postId)
                        .collection("likes")
                        .document(userId)
                        .getDocument()
                    
                    if let likeDoc = likeDoc, likeDoc.exists {
                        allPosts[i].isLiked = true
                    }
                }
            }
        }
        
        if let newLastDoc = newLastDoc {
            self.lastDocument = newLastDoc
        }
        
        await MainActor.run {
            posts.append(contentsOf: allPosts)
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
    
    func createPost(content: String, userId: String, username: String, displayName: String? = nil, profileImage: String?, images: [UIImage]? = nil) async throws {
        let documentRef = db.collection("posts").document()
        
        var imageURLs: [String]? = nil
        if let images = images {
            imageURLs = try await withThrowingTaskGroup(of: String.self) { group in
                for image in images {
                    group.addTask {
                        try await self.uploadImage(image)
                    }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
        }
        
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
            postType: .text
        )
        
        try await documentRef.setData(from: post)
        
        await MainActor.run {
            posts.insert(post, at: 0)
        }
    }
    
    func createHandPost(content: String, userId: String, username: String, displayName: String? = nil, profileImage: String?, hand: ParsedHandHistory) async throws {
        let documentRef = db.collection("posts").document()
        
        let post = Post(
            id: documentRef.documentID,
            userId: userId,
            content: content,
            createdAt: Date(),
            username: username,
            displayName: displayName,
            profileImage: profileImage,
            imageURLs: nil,
            likes: 0,
            comments: 0,
            postType: .hand,
            handHistory: hand
        )
        
        try await documentRef.setData(from: post)
        
        await MainActor.run {
            posts.insert(post, at: 0)
        }
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
    
    private func processPosts(from snapshot: QuerySnapshot) async throws -> [Post] {
        var posts = try snapshot.documents.compactMap { document in
            var post = try document.data(as: Post.self)
            post.id = document.documentID
            return post
        }
        
        // Check likes status for the current user
        if let userId = Auth.auth().currentUser?.uid {
            for i in 0..<posts.count {
                if let postId = posts[i].id {
                    let likeDoc = try? await db.collection("posts")
                        .document(postId)
                        .collection("likes")
                        .document(userId)
                        .getDocument()
                    
                    if let likeDoc = likeDoc, likeDoc.exists {
                        posts[i].isLiked = true
                    }
                }
            }
        }
        
        return posts
    }
} 
