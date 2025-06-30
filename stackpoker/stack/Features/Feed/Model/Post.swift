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
    let sessionId: String?
    let location: String?
    var isNote: Bool = false
    
    enum PostType: String, Codable {
        case text
        case location
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
        case sessionId
        case location
        case isNote
    }
    
    init(id: String, userId: String, content: String, createdAt: Date, username: String, displayName: String? = nil, profileImage: String? = nil, imageURLs: [String]? = nil, likes: Int = 0, comments: Int = 0, postType: PostType = .text, sessionId: String? = nil, location: String? = nil, isNote: Bool = false) {
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
        self.sessionId = sessionId
        self.location = location
        self.isNote = isNote
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
        isNote = try container.decodeIfPresent(Bool.self, forKey: .isNote) ?? false
        
        // Handle postType with a default value of .text if not present
        if let postTypeString = try container.decodeIfPresent(String.self, forKey: .postType),
           let postType = PostType(rawValue: postTypeString) {
            self.postType = postType
        } else {
            self.postType = .text
        }
        
        // Handle sessionId
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        location = try container.decodeIfPresent(String.self, forKey: .location)
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
        self.isNote = (data["isNote"] as? Bool) ?? false
        
        // Handle postType with a default value of .text if not present
        if let postTypeString = data["postType"] as? String,
           let postType = PostType(rawValue: postTypeString) {
            self.postType = postType
        } else {
            self.postType = .text
        }
        
        // Decode sessionId
        sessionId = data["sessionId"] as? String
        location = data["location"] as? String
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
            "postType": postType.rawValue,
            "isNote": isNote
        ]
        
        // Add displayName if present
        if let displayName = displayName {
            dict["displayName"] = displayName
        }
        
        // Add sessionId if present
        if let sessionId = sessionId {
            dict["sessionId"] = sessionId
        }
        
        // Add location if present
        if let location = location {
            dict["location"] = location
        }
        
        return dict
    }
} 