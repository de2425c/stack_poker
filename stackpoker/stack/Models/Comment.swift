import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable {
    @DocumentID var id: String?
    let postId: String
    let userId: String
    let username: String
    let profileImage: String?
    let content: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId
        case userId
        case username
        case profileImage
        case content
        case createdAt
    }
    
    init(id: String? = nil, postId: String, userId: String, username: String, profileImage: String?, content: String, createdAt: Date = Date()) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.username = username
        self.profileImage = profileImage
        self.content = content
        self.createdAt = createdAt
    }
} 