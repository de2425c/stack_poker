import Foundation
import FirebaseFirestore

class FollowService {
    private let db = Firestore.firestore()
    
    func followUser(currentUserId: String, targetUserId: String) async throws {
        let batch = db.batch()
        
        // Add to current user's following collection
        let followingRef = db.collection("users").document(currentUserId)
            .collection("following").document(targetUserId)
        batch.setData(["timestamp": FieldValue.serverTimestamp()], forDocument: followingRef)
        
        // Add to target user's followers collection
        let followerRef = db.collection("users").document(targetUserId)
            .collection("followers").document(currentUserId)
        batch.setData(["timestamp": FieldValue.serverTimestamp()], forDocument: followerRef)
        
        // Update follower count for target user
        let targetUserRef = db.collection("users").document(targetUserId)
        batch.updateData(["followersCount": FieldValue.increment(Int64(1))], forDocument: targetUserRef)
        
        // Update following count for current user
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData(["followingCount": FieldValue.increment(Int64(1))], forDocument: currentUserRef)
        
        // NEW: Add document to the shared 'userFollows' collection
        let userFollowsRef = db.collection("userFollows").document()
        batch.setData([
            "followerId": currentUserId,
            "followeeId": targetUserId,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: userFollowsRef)
        
        try await batch.commit()
    }
    
    func unfollowUser(currentUserId: String, targetUserId: String) async throws {
        let batch = db.batch()
        
        // Remove from current user's following collection
        let followingRef = db.collection("users").document(currentUserId)
            .collection("following").document(targetUserId)
        batch.deleteDocument(followingRef)
        
        // Remove from target user's followers collection
        let followerRef = db.collection("users").document(targetUserId)
            .collection("followers").document(currentUserId)
        batch.deleteDocument(followerRef)
        
        // Update follower count for target user
        let targetUserRef = db.collection("users").document(targetUserId)
        batch.updateData(["followersCount": FieldValue.increment(Int64(-1))], forDocument: targetUserRef)
        
        // Update following count for current user
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData(["followingCount": FieldValue.increment(Int64(-1))], forDocument: currentUserRef)
        
        // NEW: Remove any documents from 'userFollows' matching this relation.
        // Can't use batch with query results easily in a single batch since we don't know the doc IDs ahead of time.
        let userFollowsQuery = db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followeeId", isEqualTo: targetUserId)
        
        let snapshot = try await userFollowsQuery.getDocuments()
        for document in snapshot.documents {
            try await db.collection("userFollows").document(document.documentID).delete()
        }
        
        try await batch.commit()
    }
    
    func checkIfFollowing(currentUserId: String, targetUserId: String) async throws -> Bool {
        let doc = try await db.collection("users").document(currentUserId)
            .collection("following").document(targetUserId)
            .getDocument()
        
        return doc.exists
    }
} 