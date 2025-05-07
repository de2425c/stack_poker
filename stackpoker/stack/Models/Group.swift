import Foundation
import FirebaseFirestore

struct UserGroup: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let createdAt: Date
    let ownerId: String
    var avatarURL: String?
    var memberCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createdAt
        case ownerId
        case avatarURL
        case memberCount
    }
    
    init(id: String, name: String, description: String?, createdAt: Date, ownerId: String, avatarURL: String? = nil, memberCount: Int = 1) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.ownerId = ownerId
        self.avatarURL = avatarURL
        self.memberCount = memberCount
    }
    
    init(dictionary: [String: Any], id: String) throws {
        self.id = id
        guard let name = dictionary["name"] as? String else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing name"])
        }
        self.name = name
        self.description = dictionary["description"] as? String
        self.createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        guard let ownerId = dictionary["ownerId"] as? String else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing ownerId"])
        }
        self.ownerId = ownerId
        self.avatarURL = dictionary["avatarURL"] as? String
        self.memberCount = dictionary["memberCount"] as? Int ?? 1
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: UserGroup, rhs: UserGroup) -> Bool {
        return lhs.id == rhs.id
    }
}

struct GroupMember: Identifiable, Codable {
    let id: String // userId
    let groupId: String
    let joinedAt: Date
    let role: MemberRole
    
    enum MemberRole: String, Codable {
        case owner
        case member
    }
    
    init(id: String, groupId: String, joinedAt: Date, role: MemberRole) {
        self.id = id
        self.groupId = groupId
        self.joinedAt = joinedAt
        self.role = role
    }
}

struct GroupInvite: Identifiable, Codable {
    let id: String
    let groupId: String
    let groupName: String
    let inviterId: String
    let inviterName: String
    let inviteeId: String
    let createdAt: Date
    var status: InviteStatus
    
    enum InviteStatus: String, Codable {
        case pending
        case accepted
        case declined
    }
    
    init(id: String, groupId: String, groupName: String, inviterId: String, inviterName: String, inviteeId: String, createdAt: Date, status: InviteStatus = .pending) {
        self.id = id
        self.groupId = groupId
        self.groupName = groupName
        self.inviterId = inviterId
        self.inviterName = inviterName
        self.inviteeId = inviteeId
        self.createdAt = createdAt
        self.status = status
    }
    
    init(dictionary: [String: Any], id: String) throws {
        self.id = id
        guard let groupId = dictionary["groupId"] as? String,
              let groupName = dictionary["groupName"] as? String,
              let inviterId = dictionary["inviterId"] as? String,
              let inviterName = dictionary["inviterName"] as? String,
              let inviteeId = dictionary["inviteeId"] as? String else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        self.groupId = groupId
        self.groupName = groupName
        self.inviterId = inviterId
        self.inviterName = inviterName
        self.inviteeId = inviteeId
        self.createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        if let statusString = dictionary["status"] as? String, let status = InviteStatus(rawValue: statusString) {
            self.status = status
        } else {
            self.status = .pending
        }
    }
}

// User model for the selection dropdown
struct UserListItem: Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: UserListItem, rhs: UserListItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Display name for the dropdown
    var displayText: String {
        if let displayName = displayName, !displayName.isEmpty {
            return "\(displayName) (@\(username))"
        } else {
            return "@\(username)"
        }
    }
}

// Model for displaying group member information
struct GroupMemberInfo: Identifiable {
    let id: String // userId
    let username: String
    let displayName: String?
    let avatarURL: String?
    let role: String // Using string to avoid decoding issues
    let joinedAt: Date
    
    var isOwner: Bool {
        return role == GroupMember.MemberRole.owner.rawValue
    }
    
    var displayText: String {
        if let displayName = displayName, !displayName.isEmpty {
            return displayName
        } else {
            return "@\(username)"
        }
    }
}

// Model for group chat messages
struct GroupMessage: Identifiable, Codable {
    let id: String
    let groupId: String
    let senderId: String
    let senderName: String
    let senderAvatarURL: String?
    let timestamp: Date
    let messageType: MessageType
    let text: String?
    let imageURL: String?
    let handHistoryId: String?
    let handOwnerUserId: String?
    let homeGameId: String?
    
    enum MessageType: String, Codable {
        case text
        case image
        case hand
        case homeGame
    }
    
    init(id: String, groupId: String, senderId: String, senderName: String, senderAvatarURL: String?, timestamp: Date, messageType: MessageType, text: String? = nil, imageURL: String? = nil, handHistoryId: String? = nil, handOwnerUserId: String? = nil, homeGameId: String? = nil) {
        self.id = id
        self.groupId = groupId
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.timestamp = timestamp
        self.messageType = messageType
        self.text = text
        self.imageURL = imageURL
        self.handHistoryId = handHistoryId
        self.handOwnerUserId = handOwnerUserId
        self.homeGameId = homeGameId
    }
    
    init(dictionary: [String: Any], id: String) throws {
        self.id = id
        
        guard let groupId = dictionary["groupId"] as? String,
              let senderId = dictionary["senderId"] as? String,
              let senderName = dictionary["senderName"] as? String,
              let messageTypeString = dictionary["messageType"] as? String,
              let messageType = MessageType(rawValue: messageTypeString),
              let timestamp = (dictionary["timestamp"] as? Timestamp)?.dateValue() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        
        self.groupId = groupId
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatarURL = dictionary["senderAvatarURL"] as? String
        self.timestamp = timestamp
        self.messageType = messageType
        self.text = dictionary["text"] as? String
        self.imageURL = dictionary["imageURL"] as? String
        self.handHistoryId = dictionary["handHistoryId"] as? String
        self.handOwnerUserId = dictionary["handOwnerUserId"] as? String
        self.homeGameId = dictionary["homeGameId"] as? String
    }
} 