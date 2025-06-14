import Foundation
import FirebaseFirestore

// MARK: - User Event Models

struct UserEvent: Identifiable, Codable {
    let id: String
    let title: String
    let description: String?
    let eventType: EventType
    let creatorId: String
    let creatorName: String
    let startDate: Date
    let endDate: Date?
    let timezone: String
    let location: String?
    let maxParticipants: Int?
    let currentParticipants: Int
    let waitlistEnabled: Bool
    let status: EventStatus
    let groupId: String? // Optional - for group events
    let isPublic: Bool
    let isBanked: Bool
    let rsvpDeadline: Date?
    let reminderSettings: ReminderSettings?
    var linkedGameId: String? // If converted to actual game
    let imageURL: String? // Optional event image
    let createdAt: Date
    let updatedAt: Date
    
    enum EventType: String, Codable, CaseIterable {
        case homeGame = "homeGame"
        case tournament = "tournament"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .homeGame: return "Home Game"
            case .tournament: return "Tournament"
            case .other: return "Other"
            }
        }
        
        var icon: String {
            switch self {
            case .homeGame: return "house.fill"
            case .tournament: return "trophy.fill"
            case .other: return "calendar"
            }
        }
    }
    
    enum EventStatus: String, Codable {
        case upcoming = "upcoming"
        case active = "active"
        case completed = "completed"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .upcoming: return "Upcoming"
            case .active: return "Active"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
    }
    
    struct ReminderSettings: Codable {
        let enabled: Bool
        let reminderTimes: [Int] // Minutes before event (e.g., [60, 1440] for 1 hour and 1 day)
        
        static let defaultReminders = ReminderSettings(enabled: true, reminderTimes: [60, 1440])
    }
    
    init(id: String, title: String, description: String?, eventType: EventType, creatorId: String, creatorName: String, startDate: Date, endDate: Date?, timezone: String, location: String?, maxParticipants: Int?, waitlistEnabled: Bool, groupId: String?, isPublic: Bool, rsvpDeadline: Date?, reminderSettings: ReminderSettings?, imageURL: String? = nil, isBanked: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.eventType = eventType
        self.creatorId = creatorId
        self.creatorName = creatorName
        self.startDate = startDate
        self.endDate = endDate
        self.timezone = timezone
        self.location = location
        self.maxParticipants = maxParticipants
        self.currentParticipants = 0
        self.waitlistEnabled = waitlistEnabled
        self.status = .upcoming
        self.groupId = groupId
        self.isPublic = isPublic
        self.isBanked = isBanked
        self.rsvpDeadline = rsvpDeadline
        self.reminderSettings = reminderSettings
        self.imageURL = imageURL
        self.linkedGameId = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    init(dictionary: [String: Any], id: String) throws {
        self.id = id
        
        guard let title = dictionary["title"] as? String,
              let eventTypeRaw = dictionary["eventType"] as? String,
              let eventType = EventType(rawValue: eventTypeRaw),
              let creatorId = dictionary["creatorId"] as? String,
              let creatorName = dictionary["creatorName"] as? String,
              let startDateTimestamp = dictionary["startDate"] as? Timestamp,
              let timezone = dictionary["timezone"] as? String,
              let isPublic = dictionary["isPublic"] as? Bool,
              let waitlistEnabled = dictionary["waitlistEnabled"] as? Bool,
              let statusRaw = dictionary["status"] as? String,
              let status = EventStatus(rawValue: statusRaw),
              let createdAtTimestamp = dictionary["createdAt"] as? Timestamp,
              let updatedAtTimestamp = dictionary["updatedAt"] as? Timestamp else {
            throw NSError(domain: "UserEvent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        
        self.title = title
        self.description = dictionary["description"] as? String
        self.eventType = eventType
        self.creatorId = creatorId
        self.creatorName = creatorName
        self.startDate = startDateTimestamp.dateValue()
        self.endDate = (dictionary["endDate"] as? Timestamp)?.dateValue()
        self.timezone = timezone
        self.location = dictionary["location"] as? String
        self.maxParticipants = dictionary["maxParticipants"] as? Int
        self.currentParticipants = dictionary["currentParticipants"] as? Int ?? 0
        self.waitlistEnabled = waitlistEnabled
        self.status = status
        self.groupId = dictionary["groupId"] as? String
        self.isPublic = isPublic
        self.isBanked = dictionary["isBanked"] as? Bool ?? false
        self.rsvpDeadline = (dictionary["rsvpDeadline"] as? Timestamp)?.dateValue()
        self.linkedGameId = dictionary["linkedGameId"] as? String
        self.imageURL = dictionary["imageURL"] as? String
        self.createdAt = createdAtTimestamp.dateValue()
        self.updatedAt = updatedAtTimestamp.dateValue()
        
        // Parse reminder settings
        if let reminderData = dictionary["reminderSettings"] as? [String: Any] {
            let enabled = reminderData["enabled"] as? Bool ?? true
            let reminderTimes = reminderData["reminderTimes"] as? [Int] ?? [60, 1440]
            self.reminderSettings = ReminderSettings(enabled: enabled, reminderTimes: reminderTimes)
        } else {
            self.reminderSettings = ReminderSettings.defaultReminders
        }
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "eventType": eventType.rawValue,
            "creatorId": creatorId,
            "creatorName": creatorName,
            "startDate": Timestamp(date: startDate),
            "timezone": timezone,
            "currentParticipants": currentParticipants,
            "waitlistEnabled": waitlistEnabled,
            "status": status.rawValue,
            "isPublic": isPublic,
            "isBanked": isBanked,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let description = description { dict["description"] = description }
        if let endDate = endDate { dict["endDate"] = Timestamp(date: endDate) }
        if let location = location { dict["location"] = location }
        if let maxParticipants = maxParticipants { dict["maxParticipants"] = maxParticipants }
        if let groupId = groupId { dict["groupId"] = groupId }
        if let rsvpDeadline = rsvpDeadline { dict["rsvpDeadline"] = Timestamp(date: rsvpDeadline) }
        if let linkedGameId = linkedGameId { dict["linkedGameId"] = linkedGameId }
        if let imageURL = imageURL { dict["imageURL"] = imageURL }
        
        if let reminderSettings = reminderSettings {
            dict["reminderSettings"] = [
                "enabled": reminderSettings.enabled,
                "reminderTimes": reminderSettings.reminderTimes
            ]
        }
        
        return dict
    }
    
    // MARK: - Status Calculation
    
    /// Calculate the current status of the event based on current time
    var currentStatus: EventStatus {
        let now = Date()

        // If manually set, it's fixed
        if status == .cancelled || status == .completed {
            return status
        }

        // Before start time, it's upcoming
        if now < startDate {
            return .upcoming
        }

        // After start date
        // If it has an end date and it has passed
        if let endDate = endDate, now >= endDate {
            // if not banked, it's completed. If banked, it stays active until manually completed.
            return isBanked ? .active : .completed
        }

        // Otherwise (no end date, or end date not passed), it's active.
        return .active
    }
    
    /// Check if the event status needs to be updated in the database
    var needsStatusUpdate: Bool {
        return status != currentStatus
    }
}

// MARK: - Event RSVP Model

struct EventRSVP: Identifiable, Codable {
    let id: String
    let eventId: String
    let userId: String
    let userDisplayName: String
    var status: RSVPStatus
    let rsvpDate: Date
    let notes: String?
    var waitlistPosition: Int?
    
    enum RSVPStatus: String, Codable, CaseIterable {
        case going = "going"
        case maybe = "maybe"
        case declined = "declined"
        case waitlisted = "waitlisted"
        
        var displayName: String {
            switch self {
            case .going: return "Going"
            case .maybe: return "Maybe"
            case .declined: return "Declined"
            case .waitlisted: return "Waitlisted"
            }
        }
        
        var icon: String {
            switch self {
            case .going: return "checkmark.circle.fill"
            case .maybe: return "questionmark.circle.fill"
            case .declined: return "xmark.circle.fill"
            case .waitlisted: return "clock.circle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .going: return "green"
            case .maybe: return "orange"
            case .declined: return "red"
            case .waitlisted: return "blue"
            }
        }
    }
    
    init(eventId: String, userId: String, userDisplayName: String, status: RSVPStatus, notes: String? = nil) {
        self.id = "\(eventId)_\(userId)"
        self.eventId = eventId
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.status = status
        self.rsvpDate = Date()
        self.notes = notes
        self.waitlistPosition = nil
    }
    
    init(dictionary: [String: Any], id: String) throws {
        guard let eventId = dictionary["eventId"] as? String,
              let userId = dictionary["userId"] as? String,
              let userDisplayName = dictionary["userDisplayName"] as? String,
              let statusRaw = dictionary["status"] as? String,
              let status = RSVPStatus(rawValue: statusRaw),
              let rsvpDateTimestamp = dictionary["rsvpDate"] as? Timestamp else {
            throw NSError(domain: "EventRSVP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        
        self.id = id
        self.eventId = eventId
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.status = status
        self.rsvpDate = rsvpDateTimestamp.dateValue()
        self.notes = dictionary["notes"] as? String
        self.waitlistPosition = dictionary["waitlistPosition"] as? Int
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventId": eventId,
            "userId": userId,
            "userDisplayName": userDisplayName,
            "status": status.rawValue,
            "rsvpDate": Timestamp(date: rsvpDate)
        ]
        
        if let notes = notes { dict["notes"] = notes }
        if let waitlistPosition = waitlistPosition { dict["waitlistPosition"] = waitlistPosition }
        
        return dict
    }
}

// MARK: - Event Invite Model

struct EventInvite: Identifiable, Codable {
    let id: String
    let eventId: String
    let inviterId: String
    let inviterName: String
    let inviteeId: String
    let inviteMethod: InviteMethod
    var status: InviteStatus
    let sentAt: Date
    var respondedAt: Date?
    
    enum InviteMethod: String, Codable {
        case group = "group"
        case direct = "direct"
        case link = "link"
        
        var displayName: String {
            switch self {
            case .group: return "Group Invite"
            case .direct: return "Direct Invite"
            case .link: return "Link Invite"
            }
        }
    }
    
    enum InviteStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .accepted: return "Accepted"
            case .declined: return "Declined"
            }
        }
    }
    
    init(eventId: String, inviterId: String, inviterName: String, inviteeId: String, inviteMethod: InviteMethod) {
        self.id = UUID().uuidString
        self.eventId = eventId
        self.inviterId = inviterId
        self.inviterName = inviterName
        self.inviteeId = inviteeId
        self.inviteMethod = inviteMethod
        self.status = .pending
        self.sentAt = Date()
        self.respondedAt = nil
    }
    
    init(dictionary: [String: Any], id: String) throws {
        guard let eventId = dictionary["eventId"] as? String,
              let inviterId = dictionary["inviterId"] as? String,
              let inviterName = dictionary["inviterName"] as? String,
              let inviteeId = dictionary["inviteeId"] as? String,
              let inviteMethodRaw = dictionary["inviteMethod"] as? String,
              let inviteMethod = InviteMethod(rawValue: inviteMethodRaw),
              let statusRaw = dictionary["status"] as? String,
              let status = InviteStatus(rawValue: statusRaw),
              let sentAtTimestamp = dictionary["sentAt"] as? Timestamp else {
            throw NSError(domain: "EventInvite", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        
        self.id = id
        self.eventId = eventId
        self.inviterId = inviterId
        self.inviterName = inviterName
        self.inviteeId = inviteeId
        self.inviteMethod = inviteMethod
        self.status = status
        self.sentAt = sentAtTimestamp.dateValue()
        self.respondedAt = (dictionary["respondedAt"] as? Timestamp)?.dateValue()
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventId": eventId,
            "inviterId": inviterId,
            "inviterName": inviterName,
            "inviteeId": inviteeId,
            "inviteMethod": inviteMethod.rawValue,
            "status": status.rawValue,
            "sentAt": Timestamp(date: sentAt)
        ]
        
        if let respondedAt = respondedAt {
            dict["respondedAt"] = Timestamp(date: respondedAt)
        }
        
        return dict
    }
}

// MARK: - Public Event RSVP Model

struct PublicEventRSVP: Identifiable, Codable {
    let id: String
    let publicEventId: String
    let userId: String
    let userDisplayName: String
    var status: RSVPStatus
    let rsvpDate: Date
    let eventName: String
    let eventDate: Date
    
    enum RSVPStatus: String, Codable, CaseIterable {
        case going = "going"
        case maybe = "maybe"
        case declined = "declined"
        
        var displayName: String {
            switch self {
            case .going: return "Going"
            case .maybe: return "Maybe"
            case .declined: return "Declined"
            }
        }
        
        var icon: String {
            switch self {
            case .going: return "checkmark.circle.fill"
            case .maybe: return "questionmark.circle.fill"
            case .declined: return "xmark.circle.fill"
            }
        }
    }
    
    init(publicEventId: String, userId: String, userDisplayName: String, status: RSVPStatus, eventName: String, eventDate: Date) {
        self.id = "\(publicEventId)_\(userId)"
        self.publicEventId = publicEventId
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.status = status
        self.rsvpDate = Date()
        self.eventName = eventName
        self.eventDate = eventDate
    }
    
    init(dictionary: [String: Any], id: String) throws {
        guard let publicEventId = dictionary["publicEventId"] as? String,
              let userId = dictionary["userId"] as? String,
              let userDisplayName = dictionary["userDisplayName"] as? String,
              let statusRaw = dictionary["status"] as? String,
              let status = RSVPStatus(rawValue: statusRaw),
              let rsvpDateTimestamp = dictionary["rsvpDate"] as? Timestamp,
              let eventName = dictionary["eventName"] as? String,
              let eventDateTimestamp = dictionary["eventDate"] as? Timestamp else {
            throw NSError(domain: "PublicEventRSVP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        
        self.id = id
        self.publicEventId = publicEventId
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.status = status
        self.rsvpDate = rsvpDateTimestamp.dateValue()
        self.eventName = eventName
        self.eventDate = eventDateTimestamp.dateValue()
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "publicEventId": publicEventId,
            "userId": userId,
            "userDisplayName": userDisplayName,
            "status": status.rawValue,
            "rsvpDate": Timestamp(date: rsvpDate),
            "eventName": eventName,
            "eventDate": Timestamp(date: eventDate)
        ]
    }
} 