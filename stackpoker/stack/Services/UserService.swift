import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine

@MainActor
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
        // Clear the current profile
        self.currentUserProfile = nil
        
        // Clear all loaded users data
        self.loadedUsers.removeAll()
        
        // Clear any other cached data that might be stored
        // (Add additional cache clearing here if needed)
    }

    // Helper method to get follower counts
    private func getFollowerCounts(for userId: String) async throws -> (followers: Int, following: Int) {
        // Use the centralized userFollows collection instead of subcollections
        async let followersCount = db.collection("userFollows")
            .whereField("followeeId", isEqualTo: userId)
            .count
            .getAggregation(source: .server)
            
        async let followingCount = db.collection("userFollows")
            .whereField("followerId", isEqualTo: userId)
            .count
            .getAggregation(source: .server)
            
        let (followers, following) = try await (followersCount, followingCount)
        return (followers.count.intValue, following.count.intValue)
    }
    
    func fetchUserProfile() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {

            throw UserServiceError.notAuthenticated
        }
        

        
        do {
            let document = try await db.collection("users")
                .document(userId)
                .getDocument()
            

            
            if !document.exists {

                throw UserServiceError.profileNotFound
            }
            
            guard let data = document.data() else {

                throw UserServiceError.invalidData
            }
            
            // Get follower counts
            let (followersCount, followingCount) = try await getFollowerCounts(for: userId)
            

            let avatarURL = data["avatarURL"] as? String

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

            throw error
        }
    }
    
    func createUserProfile(userData: [String: Any]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {

            throw UserServiceError.notAuthenticated
        }
        

        
        // Extract username for availability check
        guard let username = userData["username"] as? String, !username.isEmpty else {

            throw NSError(domain: "UserServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Username is required"])
        }
        
        // Check if username is already taken
        do {
            let querySnapshot = try await db.collection("users")
                .whereField("username", isEqualTo: username)
                .getDocuments()
            
            if !querySnapshot.documents.isEmpty {

                throw UserServiceError.usernameAlreadyExists
            }
            
            // Create a mutable copy of userData and add required fields
            var profileData = userData
            profileData["id"] = userId
            profileData["createdAt"] = Timestamp(date: Date())
            
            let docRef = db.collection("users").document(userId)
            try await docRef.setData(profileData)
            

            
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

                    }
                    
                    // Add the new token
                    existingTokens.append(token)
                    try await userRef.updateData(["fcmTokens": existingTokens])

                } else {
                    // If token exists, refresh its position to be the most recent
                    if let index = existingTokens.firstIndex(of: token), index < existingTokens.count - 1 {
                        existingTokens.remove(at: index)
                        existingTokens.append(token)
                        try await userRef.updateData(["fcmTokens": existingTokens])

                    } else {

                    }
                }
            } else {
                // Document doesn't exist, create it with the FCM token

                try await userRef.setData(["fcmTokens": [token]], merge: true)

            }
        } catch {

            throw error
        }
    }
    
    // Add a function to handle token invalidation
    func invalidateFCMToken(userId: String, token: String) async {

        let userRef = db.collection("users").document(userId)
        
        do {
            let document = try await userRef.getDocument()
            
            if document.exists, var existingTokens = document.data()?["fcmTokens"] as? [String], !existingTokens.isEmpty {
                let initialCount = existingTokens.count
                
                // Remove the specific token
                existingTokens.removeAll(where: { $0 == token })
                
                if existingTokens.count < initialCount {
                    try await userRef.updateData(["fcmTokens": existingTokens])

                } else {

                }
            } else {

            }
        } catch {

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


        do {
            let document = try await db.collection("users")
                .document(id)
                .getDocument()

            if !document.exists {

                // You might want to handle this case, e.g., by setting nil or a specific error state
                // For now, it just won't add to loadedUsers
                return
            }

            guard let data = document.data() else {

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
            
            // Update the published dictionary on the main thread - No longer needed due to @MainActor
            self.loadedUsers[id] = userProfile

        } catch {

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
            print("Cannot follow yourself")
            return
        }

        // Check if already following to prevent duplicate follow documents
        let alreadyFollowing = await isUserFollowing(targetUserId: userIdToFollow, currentUserId: currentUserId)
        guard !alreadyFollowing else {
            print("Already following this user")
            return
        }

        let followData = UserFollow(followerId: currentUserId, followeeId: userIdToFollow, createdAt: Date())
        
        do {
            // Store only in the centralized userFollows collection
            try await db.collection(userFollowsCollection).addDocument(from: followData)
            
            print("Successfully followed user")

            // Removed optimistic refresh of loadedUsers/currentUserProfile counts to avoid
            // triggering large-scale view updates (can be refreshed explicitly where needed).

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
                print("Not currently following this user")
                return
            }

            // Delete from userFollows collection only
            for document in snapshot.documents {
                try await db.collection(userFollowsCollection).document(document.documentID).delete()
            }
            
            print("Successfully unfollowed user")

            // Removed optimistic local count updates – rely on explicit refreshes instead.

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

            return false
        }
    }

    func fetchFollowerIds(for userId: String) async -> [String] {
        let query = db.collection(userFollowsCollection).whereField("followeeId", isEqualTo: userId)
        do {
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { $0.data()["followerId"] as? String }
        } catch {

            return []
        }
    }

    func fetchFollowingIds(for userId: String) async -> [String] {
        let query = db.collection(userFollowsCollection).whereField("followerId", isEqualTo: userId)
        do {
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { $0.data()["followeeId"] as? String }
        } catch {

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
                    self.loadedUsers[document.documentID] = userProfile // Cache it
                }
            } catch {

            }
        }
        return profiles
    }

    // The existing getFollowerCounts might be deprecated or adapted
    // For now, the new follow system relies on querying `userFollows`.
    // If UserProfile.followersCount/followingCount are kept as denormalized counters,
    // they should ideally be updated by Cloud Functions. 
    // The `fetchUser` method will continue to use `getFollowerCounts` to populate these if they exist.

    // MARK: - User Search
    func searchUsersByUsernamePrefix(usernamePrefix: String, limit: Int = 10) async throws -> [UserProfile] {
        guard !usernamePrefix.isEmpty else { return [] }
        
        let lowercasedPrefix = usernamePrefix.lowercased()
        
        // Firestore query for "starts with" (case-insensitive requires storing a lowercase version of username or handling differently)
        // For a simpler MVP, this will be case-sensitive matching the stored username.
        // To make it truly case-insensitive with this query, you'd need to store a lowercase version of the username.
        // For now, we proceed with case-sensitive prefix search on the `username` field.
        let endPrefix = lowercasedPrefix + "\u{f8ff}" // \u{f8ff} is a very high code point character

        let query = db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: lowercasedPrefix)
            .whereField("username", isLessThan: endPrefix)
            .limit(to: limit)

        do {
            let snapshot = try await query.getDocuments()
            var profiles: [UserProfile] = []
            for document in snapshot.documents {
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
                // No longer need DispatchQueue.main.async as class is @MainActor
                self.loadedUsers[document.documentID] = userProfile // Cache it
            }
            return profiles
        } catch {

            throw error
        }
    }
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
