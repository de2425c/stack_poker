import Foundation
import FirebaseFirestore

// Poker game variants
enum PokerVariant: String, Codable, CaseIterable {
    case nlh = "NLH"
    case plo = "PLO"
    case bigO = "Big O"
    case shortDeck = "Short Deck"
    
    var displayName: String {
        return self.rawValue
    }
}

// Tournament game types
enum TournamentGameType: String, Codable, CaseIterable {
    case nlh = "NLH"
    case plo = "PLO"
    
    var displayName: String {
        return self.rawValue
    }
}

// Tournament formats
enum TournamentFormat: String, Codable, CaseIterable {
    case standard = "Standard"
    case pko = "PKO"
    case bounty = "Bounty"
    case mysteryBounty = "Mystery Bounty"
    case satellite = "Satellite"
    
    var displayName: String {
        return self.rawValue
    }
}

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
    let ante: Double? // Optional ante amount
    let location: String? // Optional location
    let gameType: PokerVariant // Added game type
    let createdAt: Date
    
    var stakes: String {
        var stakes = "$\(Int(smallBlind))/$\(Int(bigBlind))"
        
        if let straddle = straddle, straddle > 0 {
            stakes += "/$\(Int(straddle))"
        }
        
        if let ante = ante, ante > 0 {
            // Format ante to remove unnecessary decimal places
            let anteString = ante.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(ante)) : String(ante)
            stakes += " (\(anteString))"
        }
        
        return stakes
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "name": name,
            "smallBlind": smallBlind,
            "bigBlind": bigBlind,
            "gameType": gameType.rawValue,
            "createdAt": createdAt
        ]
        
        if let straddle = straddle {
            dict["straddle"] = straddle
        }
        
        if let ante = ante {
            dict["ante"] = ante
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
         ante: Double? = nil,
         location: String? = nil,
         gameType: PokerVariant = .nlh,
         createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.name = name
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.straddle = straddle
        self.ante = ante
        self.location = location
        self.gameType = gameType
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
        let ante = dictionary["ante"] as? Double
        let location = dictionary["location"] as? String
        let gameTypeString = dictionary["gameType"] as? String ?? "NLH"
        let gameType = PokerVariant(rawValue: gameTypeString) ?? .nlh
        let createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        
        self.id = id
        self.userId = userId
        self.name = name
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.straddle = straddle
        self.ante = ante
        self.location = location
        self.gameType = gameType
        self.createdAt = createdAt
    }
} 