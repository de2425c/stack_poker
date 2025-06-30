import Foundation
import FirebaseFirestore

struct PublicLiveSession: Identifiable, Codable {
    let id: String
    let userId: String
    let userName: String
    let userProfileImageURL: String
    let sessionType: String // "cashGame" or "tournament"
    let gameName: String
    let stakes: String
    let casino: String
    let buyIn: Double
    let startingChips: Double? // For tournaments, the starting chip amount
    let startTime: Date
    let endTime: Date?
    let isActive: Bool
    let currentStack: Double
    let profit: Double
    let duration: TimeInterval
    let lastUpdated: Date
    let createdAt: Date
    
    // Computed properties
    var isLive: Bool {
        return isActive && endTime == nil
    }
    
    var formattedDuration: String {
        // For live sessions, calculate duration from start time to now
        // For finished sessions, use the stored duration
        let actualDuration: TimeInterval
        if isLive {
            actualDuration = Date().timeIntervalSince(startTime)
        } else {
            actualDuration = duration
        }
        
        let hours = Int(actualDuration) / 3600
        let minutes = (Int(actualDuration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var profitColor: UIColor {
        if profit > 0 {
            return UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)
        } else if profit < 0 {
            return UIColor.systemRed
        } else {
            return UIColor.systemGray
        }
    }
    
    var formattedProfit: String {
        let sign = profit >= 0 ? "+" : ""
        return "\(sign)$\(Int(profit))"
    }
    
    init(id: String, document: [String: Any]) {
        self.id = id
        self.userId = document["userId"] as? String ?? ""
        self.userName = document["userName"] as? String ?? "Unknown"
        self.userProfileImageURL = document["userProfileImageURL"] as? String ?? ""
        self.sessionType = document["sessionType"] as? String ?? "cashGame"
        self.gameName = document["gameName"] as? String ?? ""
        self.stakes = document["stakes"] as? String ?? ""
        self.casino = document["casino"] as? String ?? ""
        self.buyIn = document["buyIn"] as? Double ?? 0
        self.startingChips = document["startingChips"] as? Double
        
        // Handle Firestore Timestamps
        if let timestamp = document["startTime"] as? Timestamp {
            self.startTime = timestamp.dateValue()
        } else {
            self.startTime = Date()
        }
        
        if let timestamp = document["endTime"] as? Timestamp {
            self.endTime = timestamp.dateValue()
        } else {
            self.endTime = nil
        }
        
        self.isActive = document["isActive"] as? Bool ?? true
        self.currentStack = document["currentStack"] as? Double ?? 0
        self.profit = document["profit"] as? Double ?? 0
        self.duration = document["duration"] as? TimeInterval ?? 0
        
        if let timestamp = document["lastUpdated"] as? Timestamp {
            self.lastUpdated = timestamp.dateValue()
        } else {
            self.lastUpdated = Date()
        }
        
        if let timestamp = document["createdAt"] as? Timestamp {
            self.createdAt = timestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
    }
} 