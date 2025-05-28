import Foundation
import FirebaseFirestore

class FollowService {
    private let db = Firestore.firestore()
    
    func followUser(currentUserId: String, targetUserId: String) async throws {
        // Check if already following to prevent duplicates
        let alreadyFollowing = try await checkIfFollowing(currentUserId: currentUserId, targetUserId: targetUserId)
        guard !alreadyFollowing else {
            return
        }
        
        // Use only the centralized userFollows collection
        let userFollowsRef = db.collection("userFollows").document()
        try await userFollowsRef.setData([
            "followerId": currentUserId,
            "followeeId": targetUserId,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }
    
    func unfollowUser(currentUserId: String, targetUserId: String) async throws {
        // Find and remove documents from userFollows collection
        let userFollowsQuery = db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followeeId", isEqualTo: targetUserId)
        
        let snapshot = try await userFollowsQuery.getDocuments()
        for document in snapshot.documents {
            try await db.collection("userFollows").document(document.documentID).delete()
        }
    }
    
    func checkIfFollowing(currentUserId: String, targetUserId: String) async throws -> Bool {
        let query = db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followeeId", isEqualTo: targetUserId)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        return !snapshot.documents.isEmpty
    }
} 