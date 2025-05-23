import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine

class UserService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var currentUserProfile: UserProfile?
    @Published var loadedUsers: [String: UserProfile] = [:]
    
    private let userFollowsCollection = "userFollows"

    init() {
        // Set up a notification observer for sign out events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearUserData),
            name: NSNotification.Name("UserWillSignOut"),
            object: nil
        )
    }
    
    deinit {
        // Remove observer when this service is deallocated
        NotificationCenter.default.removeObserver(self)
    }
    
    // Method to completely clear all user data from memory
    @objc func clearUserData() {
        print("🧹 Clearing all cached user data")
        DispatchQueue.main.async {
            // Clear the current profile
            self.currentUserProfile = nil
            
            // Clear all loaded users data
            self.loadedUsers.removeAll()
            
            // Clear any other cached data that might be stored
            // (Add additional cache clearing here if needed)
        }
    }

    // Helper method to get follower counts
    private func getFollowerCounts(for userId: String) async throws -> (followers: Int, following: Int) {
        async let followersCount = db.collection("users")
            .document(userId)
            .collection("followers")
            .count
            .getAggregation(source: .server)
            
        async let followingCount = db.collection("users")
            .document(userId)
            .collection("following")
            .count
            .getAggregation(source: .server)
            
        let (followers, following) = try await (followersCount, followingCount)
        return (followers.count.intValue, following.count.intValue)
    }
    
    func fetchUserProfile() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⛔️ fetchUserProfile: No authenticated user")
            throw UserServiceError.notAuthenticated
        }
        
        print("🔍 Fetching profile for user: \(userId)")
        
        do {
            let document = try await db.collection("users")
                .document(userId)
                .getDocument()
            
            print("📄 Document exists: \(document.exists)")
            
            if !document.exists {
                print("⚠️ No profile document found")
                throw UserServiceError.profileNotFound
            }
            
            guard let data = document.data() else {
                print("⚠️ Document exists but no data")
                throw UserServiceError.invalidData
            }
            
            // Get follower counts
            let (followersCount, followingCount) = try await getFollowerCounts(for: userId)
            
            print("✅ Successfully fetched profile data")
            let avatarURL = data["avatarURL"] as? String
            print("[DEBUG] Profile avatarURL from Firestore: \(avatarURL ?? "nil")")
            await MainActor.run {
                self.currentUserProfile = UserProfile(
                    id: userId,
                    username: data["username"] as? String ?? "",
                    displayName: data["displayName"] as? String,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    favoriteGames: data["favoriteGames"] as? [String],
                    bio: data["bio"] as? String,
                    avatarURL: avatarURL,
                    location: data["location"] as? String,
                    favoriteGame: data["favoriteGame"] as? String,
                    followersCount: followersCount,
                    followingCount: followingCount
                )
            }
        } catch {
            print("❌ Error fetching profile: \(error)")
            throw error
        }
    }
    
    func createUserProfile(userData: [String: Any]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⛔️ createUserProfile: No authenticated user")
            throw UserServiceError.notAuthenticated
        }
        
        print("📝 Creating profile for user: \(userId) with data")
        
        // Extract username for availability check
        guard let username = userData["username"] as? String, !username.isEmpty else {
            print("⚠️ Username is required")
            throw NSError(domain: "UserServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Username is required"])
        }
        
        // Check if username is already taken
        do {
            let querySnapshot = try await db.collection("users")
                .whereField("username", isEqualTo: username)
                .getDocuments()
            
            if !querySnapshot.documents.isEmpty {
                print("⚠️ Username already exists")
                throw UserServiceError.usernameAlreadyExists
            }
            
            // Create a mutable copy of userData and add required fields
            var profileData = userData
            profileData["id"] = userId
            profileData["createdAt"] = Timestamp(date: Date())
            
            let docRef = db.collection("users").document(userId)
            try await docRef.setData(profileData)
            
            print("✅ Successfully created profile with complete data")
            
            // Create a profile object from the data
            let displayName = userData["displayName"] as? String
            let bio = userData["bio"] as? String
            let location = userData["location"] as? String
            let avatarURL = userData["avatarURL"] as? String
            let favoriteGame = userData["favoriteGame"] as? String
            let favoriteGames = userData["favoriteGames"] as? [String]
            
            let newProfile = UserProfile(
                id: userId,
                username: username,
                displayName: displayName,
                createdAt: Date(),
                favoriteGames: favoriteGames,
                bio: bio,
                avatarURL: avatarURL,
                location: location,
                favoriteGame: favoriteGame,
                followersCount: 0,
                followingCount: 0
            )
            
            await MainActor.run {
                self.currentUserProfile = newProfile
            }
            
        } catch let firestoreError as NSError {
            print("❌ Firestore error: \(firestoreError.localizedDescription)")
            print("❌ Error code: \(firestoreError.code)")
            print("❌ Error domain: \(firestoreError.domain)")
            throw UserServiceError.from(firestoreError)
        }
    }
    
    func updateUserProfile(_ updates: [String: Any]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw UserServiceError.notAuthenticated
        }
        
        try await db.collection("users").document(userId).updateData(updates)
        try await fetchUserProfile() // Refresh the local profile
    }

    // Function to update or set the FCM token for a user
    func updateFCMToken(userId: String, token: String) async throws {
        print("🔄 Attempting to update FCM token for user: \(userId) with token: \(token)")
        let userRef = db.collection("users").document(userId)
        do {
            // Check if the document exists
            let document = try await userRef.getDocument()
            
            if document.exists {
                // Get existing tokens, or initialize if not present
                var existingTokens = document.data()?["fcmTokens"] as? [String] ?? []
                
                // Check if token already exists to avoid duplication
                if !existingTokens.contains(token) {
                    // If we have too many tokens (device changed multiple times),
                    // keep only the most recent ones (e.g., last 5)
                    let maxTokens = 5
                    if existingTokens.count >= maxTokens {
                        existingTokens = Array(existingTokens.suffix(maxTokens - 1))
                        print("ℹ️ Trimming old FCM tokens for user: \(userId). Keeping most recent \(maxTokens - 1) tokens.")
                    }
                    
                    // Add the new token
                    existingTokens.append(token)
                    try await userRef.updateData(["fcmTokens": existingTokens])
                    print("✅ FCM token appended for user: \(userId)")
                } else {
                    // If token exists, refresh its position to be the most recent
                    if let index = existingTokens.firstIndex(of: token), index < existingTokens.count - 1 {
                        existingTokens.remove(at: index)
                        existingTokens.append(token)
                        try await userRef.updateData(["fcmTokens": existingTokens])
                        print("ℹ️ FCM token refreshed position for user: \(userId)")
                    } else {
                        print("ℹ️ FCM token already exists and is most recent for user: \(userId)")
                    }
                }
            } else {
                // Document doesn't exist, create it with the FCM token
                print("⚠️ User document \(userId) does not exist. Creating with FCM token.")
                try await userRef.setData(["fcmTokens": [token]], merge: true)
                print("✅ FCM token set for new/non-existent user document: \(userId)")
            }
        } catch {
            print("❌ Error updating FCM token for user \(userId): \(error.localizedDescription)")
            throw error
        }
    }
    
    // Add a function to handle token invalidation
    func invalidateFCMToken(userId: String, token: String) async {
        print("🔄 Attempting to remove invalid FCM token for user: \(userId)")
        let userRef = db.collection("users").document(userId)
        
        do {
            let document = try await userRef.getDocument()
            
            if document.exists, var existingTokens = document.data()?["fcmTokens"] as? [String], !existingTokens.isEmpty {
                let initialCount = existingTokens.count
                
                // Remove the specific token
                existingTokens.removeAll(where: { $0 == token })
                
                if existingTokens.count < initialCount {
                    try await userRef.updateData(["fcmTokens": existingTokens])
                    print("✅ Removed invalid FCM token for user: \(userId)")
                } else {
                    print("ℹ️ FCM token was not found in user's tokens array: \(userId)")
                }
            } else {
                print("ℹ️ No FCM tokens found for user: \(userId) or document doesn't exist")
            }
        } catch {
            print("❌ Error removing invalid FCM token for user \(userId): \(error.localizedDescription)")
        }
    }
    
    func uploadProfileImage(_ image: UIImage, userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let storageRef = Storage.storage().reference().child("profile_images/\(userId).jpg")
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert image."])) )
            return
        }
        storageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                if let urlString = url?.absoluteString {
                    // Ensure we're using HTTPS
                    let httpsUrlString = urlString.replacingOccurrences(of: "http://", with: "https://")
                    print("[DEBUG] Firebase Storage download URL: \(httpsUrlString)")
                    completion(.success(httpsUrlString))
                } else {
                    completion(.failure(NSError(domain: "URLError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No URL returned."])) )
                }
            }
        }
    }
    
    func fetchUser(id: String) async {
        // Optional: Prevent re-fetching if data for this user ID is already loaded
        // and you don't need to refresh it every time.
        // if loadedUsers[id] != nil {
        //     print("User \(id) already loaded.")
        //     return
        // }
        print("🔍 Fetching profile for user: \(id) for loadedUsers dictionary")

        do {
            let document = try await db.collection("users")
                .document(id)
                .getDocument()

            if !document.exists {
                print("⚠️ No profile document found for user ID: \(id)")
                // You might want to handle this case, e.g., by setting nil or a specific error state
                // For now, it just won't add to loadedUsers
                return
            }

            guard let data = document.data() else {
                print("⚠️ Document exists for user ID \(id) but no data")
                return
            }

            // Get follower counts for the specific user
            let (followersCount, followingCount) = try await getFollowerCounts(for: id)
            
            let avatarURL = data["avatarURL"] as? String
            let userProfile = UserProfile(
                id: id,
                username: data["username"] as? String ?? "",
                displayName: data["displayName"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                favoriteGames: data["favoriteGames"] as? [String],
                bio: data["bio"] as? String,
                avatarURL: avatarURL,
                location: data["location"] as? String,
                favoriteGame: data["favoriteGame"] as? String,
                followersCount: followersCount,
                followingCount: followingCount
            )
            
            // Update the published dictionary on the main thread
            DispatchQueue.main.async {
                self.loadedUsers[id] = userProfile
                print("✅ Successfully fetched and stored user profile: \(userProfile.username) in loadedUsers")
            }

        } catch {
            print("❌ Error fetching profile for user ID \(id): \(error)")
            // Optionally, handle the error, e.g., by setting nil for this ID in loadedUsers
        }
    }

    // MARK: - New Follow/Unfollow Logic

    func followUser(userIdToFollow: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw UserServiceError.notAuthenticated
        }
        
        // Prevent following oneself
        guard currentUserId != userIdToFollow else {
            print("User cannot follow themselves.")
            return // Or throw an error
        }

        // Check if already following to prevent duplicate follow documents
        let alreadyFollowing = await isUserFollowing(targetUserId: userIdToFollow, currentUserId: currentUserId)
        guard !alreadyFollowing else {
            print("User \(currentUserId) is already following \(userIdToFollow).")
            return
        }

        let followData = UserFollow(followerId: currentUserId, followeeId: userIdToFollow, createdAt: Date())
        
        do {
            // Use addDocument(from:) for Encodable types
            try await db.collection(userFollowsCollection).addDocument(from: followData)
            print("User \(currentUserId) successfully followed \(userIdToFollow).")

            // Optimistically update local counts and refresh profiles
            DispatchQueue.main.async {
                if var followedUser = self.loadedUsers[userIdToFollow] {
                    followedUser.followersCount += 1
                    self.loadedUsers[userIdToFollow] = followedUser
                }
                if var currentUser = self.loadedUsers[currentUserId] {
                    currentUser.followingCount += 1
                    self.loadedUsers[currentUserId] = currentUser
                }
                if self.currentUserProfile?.id == currentUserId {
                    self.currentUserProfile?.followingCount += 1
                }
            }
            // Consider re-fetching profiles for robustness or relying on Cloud Functions for counters
            // await fetchUser(id: userIdToFollow)
            // await fetchUser(id: currentUserId) 
        } catch {
            print("Error following user: \(error)")
            throw error
        }
    }

    func unfollowUser(userIdToUnfollow: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw UserServiceError.notAuthenticated
        }

        let query = db.collection(userFollowsCollection)
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followeeId", isEqualTo: userIdToUnfollow)

        do {
            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else {
                print("User \(currentUserId) is not following \(userIdToUnfollow), cannot unfollow.")
                return // Or throw an error indicating not currently following
            }

            for document in snapshot.documents {
                try await db.collection(userFollowsCollection).document(document.documentID).delete()
            }
            print("User \(currentUserId) successfully unfollowed \(userIdToUnfollow).")

            // Optimistically update local counts and refresh profiles
            DispatchQueue.main.async {
                if var unfollowedUser = self.loadedUsers[userIdToUnfollow] {
                    unfollowedUser.followersCount = max(0, unfollowedUser.followersCount - 1)
                    self.loadedUsers[userIdToUnfollow] = unfollowedUser
                }
                if var currentUser = self.loadedUsers[currentUserId] {
                    currentUser.followingCount = max(0, currentUser.followingCount - 1)
                    self.loadedUsers[currentUserId] = currentUser
                }
                if self.currentUserProfile?.id == currentUserId {
                    self.currentUserProfile?.followingCount = max(0, (self.currentUserProfile?.followingCount ?? 0) - 1)
                }
            }
            // Consider re-fetching profiles or relying on Cloud Functions for counters
            // await fetchUser(id: userIdToUnfollow)
            // await fetchUser(id: currentUserId)
        } catch {
            print("Error unfollowing user: \(error)")
            throw error
        }
    }

    func isUserFollowing(targetUserId: String, currentUserId: String?) async -> Bool {
        guard let currentUserId = currentUserId else {
            return false
        }
        if targetUserId == currentUserId { return false } // Cannot follow oneself

        let query = db.collection(userFollowsCollection)
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followeeId", isEqualTo: targetUserId)
            .limit(to: 1)
        
        do {
            let snapshot = try await query.getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            print("Error checking follow status: \(error)")
            return false
        }
    }

    func fetchFollowerIds(for userId: String) async -> [String] {
        let query = db.collection(userFollowsCollection).whereField("followeeId", isEqualTo: userId)
        do {
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { $0.data()["followerId"] as? String }
        } catch {
            print("Error fetching follower IDs: \(error)")
            return []
        }
    }

    func fetchFollowingIds(for userId: String) async -> [String] {
        let query = db.collection(userFollowsCollection).whereField("followerId", isEqualTo: userId)
        do {
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { $0.data()["followeeId"] as? String }
        } catch {
            print("Error fetching following IDs: \(error)")
            return []
        }
    }
    
    // Method to fetch UserProfile objects based on a list of IDs
    func fetchUserProfiles(byIds userIds: [String]) async -> [UserProfile] {
        var profiles: [UserProfile] = []
        guard !userIds.isEmpty else { return profiles }

        // Fetch profiles in batches of 10 (Firestore 'in' query limit)
        let chunks = userIds.chunked(into: 10)
        for chunk in chunks {
            if chunk.isEmpty { continue }
            let query = db.collection("users").whereField(FieldPath.documentID(), in: chunk)
            do {
                let snapshot = try await query.getDocuments()
                for document in snapshot.documents {
                    // Use the existing fetchUser logic or UserProfile initializer
                    // For simplicity, re-using parts of fetchUser logic here:
                    let data = document.data()
                    let (followersCount, followingCount) = (try? await getFollowerCounts(for: document.documentID)) ?? (0,0)
                    let userProfile = UserProfile(
                        id: document.documentID,
                        username: data["username"] as? String ?? "",
                        displayName: data["displayName"] as? String,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        favoriteGames: data["favoriteGames"] as? [String],
                        bio: data["bio"] as? String,
                        avatarURL: data["avatarURL"] as? String,
                        location: data["location"] as? String,
                        favoriteGame: data["favoriteGame"] as? String,
                        followersCount: followersCount,
                        followingCount: followingCount
                    )
                    profiles.append(userProfile)
                    DispatchQueue.main.async {
                        self.loadedUsers[document.documentID] = userProfile // Cache it
                    }
                }
            } catch {
                print("Error fetching user profiles by IDs chunk: \(error)")
            }
        }
        return profiles
    }

    // The existing getFollowerCounts might be deprecated or adapted
    // For now, the new follow system relies on querying `userFollows`.
    // If UserProfile.followersCount/followingCount are kept as denormalized counters,
    // they should ideally be updated by Cloud Functions. 
    // The `fetchUser` method will continue to use `getFollowerCounts` to populate these if they exist.

}

// Helper extension for chunking arrays (used in fetchUserProfiles)
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

enum UserServiceError: Error, CustomStringConvertible {
    case notAuthenticated
    case profileNotFound
    case invalidData
    case usernameAlreadyExists
    case permissionDenied
    case serverError
    case unknown
    
    var description: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .profileNotFound:
            return "Profile not found"
        case .invalidData:
            return "Invalid data"
        case .usernameAlreadyExists:
            return "Username already exists"
        case .permissionDenied:
            return "Permission denied"
        case .serverError:
            return "Server error"
        case .unknown:
            return "Unknown error"
        }
    }
    
    var message: String {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to perform this action"
        case .profileNotFound:
            return "User profile not found"
        case .invalidData:
            return "Invalid profile data"
        case .usernameAlreadyExists:
            return "This username is already taken"
        case .permissionDenied:
            return "You don't have permission to access this data"
        case .serverError:
            return "A server error occurred"
        case .unknown:
            return "An unknown error occurred"
        }
    }
    
    static func from(_ error: NSError) -> UserServiceError {
        if error.domain == FirestoreErrorDomain {
            switch error.code {
            case 7: // Permission Denied
                return .permissionDenied
            case 13: // Internal Error
                return .serverError
            default:
                return .unknown
            }
        }
        return .unknown
    }
} 
