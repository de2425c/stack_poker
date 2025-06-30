import Foundation
import FirebaseFirestore

struct UserFollow: Codable, Identifiable {
    @DocumentID var id: String? // Firestore document ID
    let followerId: String      // ID of the user who is following
    let followeeId: String      // ID of the user who is being followed
    let createdAt: Date
    var postNotifications: Bool // Whether the follower wants post notifications from this user

    enum CodingKeys: String, CodingKey {
        case id
        case followerId
        case followeeId
        case createdAt
        case postNotifications
    }

    init(id: String? = nil, followerId: String, followeeId: String, createdAt: Date = Date(), postNotifications: Bool = false) {
        self.id = id
        self.followerId = followerId
        self.followeeId = followeeId
        self.createdAt = createdAt
        self.postNotifications = postNotifications
    }
} 