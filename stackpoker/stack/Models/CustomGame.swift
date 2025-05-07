import Foundation
import FirebaseFirestore

struct CustomGame: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String
    let stakes: String
    let createdAt: Date
    
    var dictionary: [String: Any] {
        return [
            "id": id,
            "userId": userId,
            "name": name,
            "stakes": stakes,
            "createdAt": createdAt
        ]
    }
    
    init(id: String = UUID().uuidString, userId: String, name: String, stakes: String, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.name = name
        self.stakes = stakes
        self.createdAt = createdAt
    }
    
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let userId = dictionary["userId"] as? String,
              let name = dictionary["name"] as? String,
              let stakes = dictionary["stakes"] as? String,
              let createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = id
        self.userId = userId
        self.name = name
        self.stakes = stakes
        self.createdAt = createdAt
    }
} 