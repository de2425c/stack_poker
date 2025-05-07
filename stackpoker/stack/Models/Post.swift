import Foundation
import FirebaseFirestore

struct Post: Identifiable, Codable {
    @DocumentID var id: String?
    let content: String
    let userId: String
    let username: String
    let displayName: String?
    let createdAt: Date
    var likes: Int
    var comments: Int
    var isLiked: Bool = false
    let profileImage: String?
    let imageURLs: [String]?
    let postType: PostType
    let handHistory: ParsedHandHistory?
    
    enum PostType: String, Codable {
        case text
        case hand
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case userId
        case username
        case displayName
        case createdAt
        case likes
        case comments
        case profileImage
        case imageURLs
        case postType
        case handHistory
    }
    
    init(id: String, userId: String, content: String, createdAt: Date, username: String, displayName: String? = nil, profileImage: String? = nil, imageURLs: [String]? = nil, likes: Int = 0, comments: Int = 0, postType: PostType = .text, handHistory: ParsedHandHistory? = nil) {
        self.id = id
        self.userId = userId
        self.content = content
        self.createdAt = createdAt
        self.username = username
        self.displayName = displayName
        self.profileImage = profileImage
        self.imageURLs = imageURLs
        self.likes = likes
        self.comments = comments
        self.postType = postType
        self.handHistory = handHistory
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        comments = try container.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        profileImage = try container.decodeIfPresent(String.self, forKey: .profileImage)
        imageURLs = try container.decodeIfPresent([String].self, forKey: .imageURLs)
        
        // Handle postType with a default value of .text if not present
        if let postTypeString = try container.decodeIfPresent(String.self, forKey: .postType),
           let postType = PostType(rawValue: postTypeString) {
            self.postType = postType
        } else {
            self.postType = .text
        }
        
        // Handle handHistory - try to decode as ParsedHandHistory directly
        self.handHistory = try? container.decodeIfPresent(ParsedHandHistory.self, forKey: .handHistory)
    }
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let userId = data["userId"] as? String,
              let content = data["content"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let username = data["username"] as? String else {
            return nil
        }
        
        self.id = document.documentID
        self.userId = userId
        self.content = content
        self.createdAt = createdAt
        self.username = username
        self.displayName = data["displayName"] as? String
        self.profileImage = data["profileImage"] as? String
        self.imageURLs = data["imageURLs"] as? [String]
        self.likes = (data["likes"] as? Int) ?? 0
        self.comments = (data["comments"] as? Int) ?? 0
        
        // Handle postType with a default value of .text if not present
        if let postTypeString = data["postType"] as? String,
           let postType = PostType(rawValue: postTypeString) {
            self.postType = postType
        } else {
            self.postType = .text
        }
        
        // Decode hand history if present
        if let handDict = data["handHistory"] as? [String: Any],
           let handData = try? JSONSerialization.data(withJSONObject: handDict),
           let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: handData) {
            self.handHistory = hand
        } else {
            self.handHistory = nil
        }
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "content": content,
            "createdAt": Timestamp(date: createdAt),
            "username": username,
            "profileImage": profileImage as Any,
            "imageURLs": imageURLs as Any,
            "likes": likes,
            "comments": comments,
            "postType": postType.rawValue
        ]
        
        // Add displayName if present
        if let displayName = displayName {
            dict["displayName"] = displayName
        }
        
        // Encode hand history if present
        if let hand = handHistory,
           let handData = try? JSONEncoder().encode(hand),
           let handDict = try? JSONSerialization.jsonObject(with: handData) as? [String: Any] {
            dict["handHistory"] = handDict
        }
        
        return dict
    }
} 