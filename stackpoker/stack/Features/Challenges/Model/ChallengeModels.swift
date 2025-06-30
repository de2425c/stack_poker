import Foundation
import FirebaseFirestore

// MARK: - Challenge Types
enum ChallengeType: String, CaseIterable, Codable {
    case bankroll = "bankroll"
    case hands = "hands"
    case session = "session"
    
    var displayName: String {
        switch self {
        case .bankroll: return "Bankroll"
        case .hands: return "Hands"
        case .session: return "Session"
        }
    }
    
    var icon: String {
        switch self {
        case .bankroll: return "dollarsign.circle.fill"
        case .hands: return "suit.spade.fill"
        case .session: return "clock.fill"
        }
    }
    
    var color: String {
        switch self {
        case .bankroll: return "green"
        case .hands: return "purple"
        case .session: return "orange"
        }
    }
}

// MARK: - Challenge Status
enum ChallengeStatus: String, Codable {
    case active = "active"
    case completed = "completed"
    case failed = "failed"
    case abandoned = "abandoned"
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .abandoned: return "Abandoned"
        }
    }
}

// MARK: - Base Challenge Model
struct Challenge: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let type: ChallengeType
    let title: String
    let description: String
    let targetValue: Double
    var currentValue: Double
    let startDate: Date
    let endDate: Date?
    var status: ChallengeStatus
    let isPublic: Bool
    let createdAt: Date
    var completedAt: Date?
    var lastUpdated: Date
    
    // Type-specific configuration
    let startingBankroll: Double? // For bankroll challenges
    let targetHandCount: Int? // For hands challenges
    let targetSessions: Int? // For session challenges
    let targetHours: Double? // For session challenges - total hours
    let durationInDays: Int? // For time-based challenges
    
    // NEW: Enhanced Session Challenge Fields
    let targetSessionCount: Int? // Number of sessions required
    let minHoursPerSession: Double? // Minimum hours per session
    let maxSessionsPerDay: Int? // Optional: limit sessions per day
    var currentSessionCount: Int // Number of sessions completed
    var totalHoursPlayed: Double // Total hours across all sessions
    var validSessionsCount: Int // Sessions that meet minimum hour requirement
    var countedSessionIds: [String] = [] // Sessions already counted towards this challenge
    
    init(id: String? = nil,
         userId: String,
         type: ChallengeType,
         title: String,
         description: String,
         targetValue: Double,
         currentValue: Double = 0,
         startDate: Date = Date(),
         endDate: Date? = nil,
         status: ChallengeStatus = .active,
         isPublic: Bool = true,
         createdAt: Date = Date(),
         completedAt: Date? = nil,
         lastUpdated: Date = Date(),
         startingBankroll: Double? = nil,
         targetHandCount: Int? = nil,
         targetSessions: Int? = nil,
         targetHours: Double? = nil,
         durationInDays: Int? = nil,
         targetSessionCount: Int? = nil,
         minHoursPerSession: Double? = nil,
         maxSessionsPerDay: Int? = nil,
         currentSessionCount: Int = 0,
         totalHoursPlayed: Double = 0,
         validSessionsCount: Int = 0) {
        
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.description = description
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastUpdated = lastUpdated
        self.startingBankroll = startingBankroll
        self.targetHandCount = targetHandCount
        self.targetSessions = targetSessions
        self.targetHours = targetHours
        self.durationInDays = durationInDays
        self.targetSessionCount = targetSessionCount
        self.minHoursPerSession = minHoursPerSession
        self.maxSessionsPerDay = maxSessionsPerDay
        self.currentSessionCount = currentSessionCount
        self.totalHoursPlayed = totalHoursPlayed
        self.validSessionsCount = validSessionsCount
    }
    
    // MARK: - Session Challenge Computed Properties
    
    /// For session challenges, determines if the challenge is completed
    var isSessionChallengeCompleted: Bool {
        guard type == .session else { return false }
        
        if let targetCount = targetSessionCount {
            // Count-based challenge: need specific number of valid sessions
            return validSessionsCount >= targetCount
        } else if let targetHours = targetHours {
            // Hours-based challenge: need total hours
            return totalHoursPlayed >= targetHours
        }
        
        return false
    }
    
    /// Progress percentage for session challenges
    var sessionChallengeProgress: Double {
        guard type == .session else { return 0 }
        
        if let targetCount = targetSessionCount {
            // Progress based on session count
            return min(Double(validSessionsCount) / Double(targetCount) * 100, 100)
        } else if let targetHours = targetHours {
            // Progress based on hours
            return min(totalHoursPlayed / targetHours * 100, 100)
        }
        
        return 0
    }
    
    /// Remaining sessions needed
    var remainingSessions: Int {
        guard type == .session, let targetCount = targetSessionCount else { return 0 }
        return max(targetCount - validSessionsCount, 0)
    }
    
    /// Remaining hours needed
    var remainingHours: Double {
        guard type == .session else { return 0 }
        
        if let targetHours = targetHours {
            return max(targetHours - totalHoursPlayed, 0)
        }
        
        return 0
    }
    
    /// Average hours per session
    var averageHoursPerSession: Double {
        guard currentSessionCount > 0 else { return 0 }
        return totalHoursPlayed / Double(currentSessionCount)
    }
    
    /// Check if a session qualifies for this challenge
    func sessionQualifies(hoursPlayed: Double) -> Bool {
        guard type == .session else { return false }
        
        if let minHours = minHoursPerSession {
            return hoursPlayed >= minHours
        }
        
        return true // If no minimum set, all sessions qualify
    }
    
    // Computed properties
    var progressPercentage: Double {
        if type == .session {
            return sessionChallengeProgress
        }
        
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue * 100, 0), 100)
    }
    
    var isCompleted: Bool {
        if type == .session {
            return isSessionChallengeCompleted
        }
        
        return status == .completed || currentValue >= targetValue
    }
    
    var remainingValue: Double {
        if type == .session {
            return remainingHours
        }
        
        return max(targetValue - currentValue, 0)
    }
    
    var daysRemaining: Int? {
        guard let endDate = endDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: endDate).day
        return max(days ?? 0, 0)
    }
    
    // Firestore dictionary representation
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "type": type.rawValue,
            "title": title,
            "description": description,
            "targetValue": targetValue,
            "currentValue": currentValue,
            "startDate": Timestamp(date: startDate),
            "status": status.rawValue,
            "isPublic": isPublic,
            "createdAt": Timestamp(date: createdAt),
            "lastUpdated": Timestamp(date: lastUpdated),
            "currentSessionCount": currentSessionCount,
            "totalHoursPlayed": totalHoursPlayed,
            "validSessionsCount": validSessionsCount
        ]
        
        if let endDate = endDate {
            dict["endDate"] = Timestamp(date: endDate)
        }
        
        if let completedAt = completedAt {
            dict["completedAt"] = Timestamp(date: completedAt)
        }
        
        // Type-specific fields
        if let startingBankroll = startingBankroll {
            dict["startingBankroll"] = startingBankroll
        }
        
        if let targetHandCount = targetHandCount {
            dict["targetHandCount"] = targetHandCount
        }
        
        if let targetSessions = targetSessions {
            dict["targetSessions"] = targetSessions
        }
        
        if let targetHours = targetHours {
            dict["targetHours"] = targetHours
        }
        
        if let durationInDays = durationInDays {
            dict["durationInDays"] = durationInDays
        }
        
        // NEW: Session challenge specific fields
        if let targetSessionCount = targetSessionCount {
            dict["targetSessionCount"] = targetSessionCount
        }
        
        if let minHoursPerSession = minHoursPerSession {
            dict["minHoursPerSession"] = minHoursPerSession
        }
        
        if let maxSessionsPerDay = maxSessionsPerDay {
            dict["maxSessionsPerDay"] = maxSessionsPerDay
        }
        
        if !countedSessionIds.isEmpty {
            dict["countedSessionIds"] = countedSessionIds
        }
        
        return dict
    }
    
    // Initialize from Firestore document
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let userId = data["userId"] as? String,
              let typeString = data["type"] as? String,
              let type = ChallengeType(rawValue: typeString),
              let title = data["title"] as? String,
              let description = data["description"] as? String,
              let targetValue = data["targetValue"] as? Double,
              let currentValue = data["currentValue"] as? Double,
              let startDateTimestamp = data["startDate"] as? Timestamp,
              let statusString = data["status"] as? String,
              let status = ChallengeStatus(rawValue: statusString),
              let isPublic = data["isPublic"] as? Bool,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let lastUpdatedTimestamp = data["lastUpdated"] as? Timestamp else {
            return nil
        }
        
        self.id = document.documentID
        self.userId = userId
        self.type = type
        self.title = title
        self.description = description
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.startDate = startDateTimestamp.dateValue()
        self.endDate = (data["endDate"] as? Timestamp)?.dateValue()
        self.status = status
        self.isPublic = isPublic
        self.createdAt = createdAtTimestamp.dateValue()
        self.completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        self.lastUpdated = lastUpdatedTimestamp.dateValue()
        
        // Type-specific fields
        self.startingBankroll = data["startingBankroll"] as? Double
        self.targetHandCount = data["targetHandCount"] as? Int
        self.targetSessions = data["targetSessions"] as? Int
        self.targetHours = data["targetHours"] as? Double
        self.durationInDays = data["durationInDays"] as? Int
        
        // NEW: Session challenge specific fields
        self.targetSessionCount = data["targetSessionCount"] as? Int
        self.minHoursPerSession = data["minHoursPerSession"] as? Double
        self.maxSessionsPerDay = data["maxSessionsPerDay"] as? Int
        self.currentSessionCount = data["currentSessionCount"] as? Int ?? 0
        self.totalHoursPlayed = data["totalHoursPlayed"] as? Double ?? 0
        self.validSessionsCount = data["validSessionsCount"] as? Int ?? 0
        self.countedSessionIds = data["countedSessionIds"] as? [String] ?? []
    }
}

// MARK: - Challenge Progress Tracking
struct ChallengeProgress: Identifiable, Codable {
    let id: String
    let challengeId: String
    let userId: String
    let progressValue: Double
    let timestamp: Date
    let triggerEvent: String // "session_completed", "hand_logged", etc.
    let relatedEntityId: String? // session ID, hand ID, etc.
    let notes: String?
    
    init(id: String = UUID().uuidString,
         challengeId: String,
         userId: String,
         progressValue: Double,
         timestamp: Date = Date(),
         triggerEvent: String,
         relatedEntityId: String? = nil,
         notes: String? = nil) {
        
        self.id = id
        self.challengeId = challengeId
        self.userId = userId
        self.progressValue = progressValue
        self.timestamp = timestamp
        self.triggerEvent = triggerEvent
        self.relatedEntityId = relatedEntityId
        self.notes = notes
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "challengeId": challengeId,
            "userId": userId,
            "progressValue": progressValue,
            "timestamp": Timestamp(date: timestamp),
            "triggerEvent": triggerEvent
        ]
        
        if let relatedEntityId = relatedEntityId {
            dict["relatedEntityId"] = relatedEntityId
        }
        
        if let notes = notes {
            dict["notes"] = notes
        }
        
        return dict
    }
} 