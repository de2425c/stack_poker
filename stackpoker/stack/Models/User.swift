import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    let id: String              // Firebase Auth UID
    var username: String
    var displayName: String?
    var createdAt: Date
    
    // Optional fields for more detailed profile
    var favoriteGames: [String]?    // e.g., ["No Limit Hold'em", "PLO"]
    var bio: String?
    var avatarURL: String?
    var location: String?
    var favoriteGame: String?
    
    // Social fields
    var followersCount: Int
    var followingCount: Int
    var isFollowing: Bool? // Client-side only, not stored in Firestore
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case createdAt
        case favoriteGames
        case bio
        case avatarURL
        case location
        case favoriteGame
        case followersCount
        case followingCount
    }
    
    init(id: String, username: String, displayName: String?, createdAt: Date, favoriteGames: [String]? = nil, bio: String? = nil, avatarURL: String? = nil, location: String? = nil, favoriteGame: String? = nil, followersCount: Int = 0, followingCount: Int = 0, isFollowing: Bool? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.createdAt = createdAt
        self.favoriteGames = favoriteGames
        self.bio = bio
        self.avatarURL = avatarURL
        self.location = location
        self.favoriteGame = favoriteGame
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
    }
    
    init(dictionary: [String: Any], id: String) throws {
        self.id = id
        guard let username = dictionary["username"] as? String else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing username"])
        }
        self.username = username
        self.displayName = dictionary["displayName"] as? String
        self.createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.favoriteGames = dictionary["favoriteGames"] as? [String]
        self.bio = dictionary["bio"] as? String
        self.avatarURL = dictionary["avatarURL"] as? String
        self.location = dictionary["location"] as? String
        self.favoriteGame = dictionary["favoriteGame"] as? String
        self.followersCount = dictionary["followersCount"] as? Int ?? 0
        self.followingCount = dictionary["followingCount"] as? Int ?? 0
        self.isFollowing = nil // This is set client-side
    }
} 

extension Encodable {
    var dictionary: [String: Any]? {
        do {
            let data = try JSONEncoder().encode(self)
            let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            return dict
        } catch {
            print("Error converting to dictionary:", error)
            return nil
        }
    }
}
