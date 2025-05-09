import Foundation
import FirebaseFirestore

// Game type (Cash Game or Tournament)
enum PokerGameType: String, Codable, CaseIterable {
    case cash = "Cash Game"
    case tournament = "Tournament"
}

// For Cash Game settings
struct CashGame: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String // Optional custom name or location
    let smallBlind: Double
    let bigBlind: Double
    let straddle: Double? // Optional straddle amount
    let location: String? // Optional location
    let createdAt: Date
    
    var stakes: String {
        if let straddle = straddle, straddle > 0 {
            return "$\(Int(smallBlind))/$\(Int(bigBlind))/$\(Int(straddle))"
        } else {
            return "$\(Int(smallBlind))/$\(Int(bigBlind))"
        }
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "name": name,
            "smallBlind": smallBlind,
            "bigBlind": bigBlind,
            "createdAt": createdAt
        ]
        
        if let straddle = straddle {
            dict["straddle"] = straddle
        }
        
        if let location = location {
            dict["location"] = location
        }
        
        return dict
    }
    
    init(id: String = UUID().uuidString, 
         userId: String, 
         name: String, 
         smallBlind: Double, 
         bigBlind: Double, 
         straddle: Double? = nil,
         location: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.name = name
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.straddle = straddle
        self.location = location
        self.createdAt = createdAt
    }
    
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let userId = dictionary["userId"] as? String,
              let name = dictionary["name"] as? String,
              let smallBlind = dictionary["smallBlind"] as? Double,
              let bigBlind = dictionary["bigBlind"] as? Double else {
            return nil
        }
        
        let straddle = dictionary["straddle"] as? Double
        let location = dictionary["location"] as? String
        let createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        
        self.id = id
        self.userId = userId
        self.name = name
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.straddle = straddle
        self.location = location
        self.createdAt = createdAt
    }
} 