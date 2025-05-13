import Foundation
import FirebaseFirestore

struct UserFollow: Codable, Identifiable {
    @DocumentID var id: String? // Firestore document ID
    let followerId: String      // ID of the user who is following
    let followeeId: String      // ID of the user who is being followed
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case followerId
        case followeeId
        case createdAt
    }

    init(id: String? = nil, followerId: String, followeeId: String, createdAt: Date = Date()) {
        self.id = id
        self.followerId = followerId
        self.followeeId = followeeId
        self.createdAt = createdAt
    }
} 