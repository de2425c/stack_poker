import Foundation
import FirebaseFirestore

struct HandTrainingData: Codable, Identifiable {
    let id: String?  // Firestore document ID
    let originalText: String  // Original hand history text
    let parsedJSON: [String: Any]  // The parsed JSON output
    let isVerified: Bool  // Whether it has been verified by a user
    let userEdited: Bool  // Whether a user edited the parsing
    let timestamp: Date
    let userId: String  // User who verified it
    
    // Optional fields for metrics
    let parsingAccuracy: Double?  // User rating of parsing accuracy (0-100%)
    let notes: String?  // User notes about the parsing
    
    enum CodingKeys: String, CodingKey {
        case id, originalText, parsedJSON, isVerified, userEdited, timestamp, userId, parsingAccuracy, notes
    }
    
    init(id: String?, originalText: String, parsedJSON: [String: Any], isVerified: Bool, userEdited: Bool, timestamp: Date, userId: String, parsingAccuracy: Double?, notes: String?) {
        self.id = id
        self.originalText = originalText
        self.parsedJSON = parsedJSON
        self.isVerified = isVerified
        self.userEdited = userEdited
        self.timestamp = timestamp
        self.userId = userId
        self.parsingAccuracy = parsingAccuracy
        self.notes = notes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        originalText = try container.decode(String.self, forKey: .originalText)
        userId = try container.decode(String.self, forKey: .userId)
        isVerified = try container.decode(Bool.self, forKey: .isVerified)
        userEdited = try container.decode(Bool.self, forKey: .userEdited)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        parsingAccuracy = try container.decodeIfPresent(Double.self, forKey: .parsingAccuracy)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        
        // Handle the dictionary type
        if let jsonData = try container.decodeIfPresent(Data.self, forKey: .parsedJSON),
           let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            parsedJSON = jsonDict
        } else {
            parsedJSON = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(originalText, forKey: .originalText)
        try container.encode(userId, forKey: .userId)
        try container.encode(isVerified, forKey: .isVerified)
        try container.encode(userEdited, forKey: .userEdited)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(parsingAccuracy, forKey: .parsingAccuracy)
        try container.encodeIfPresent(notes, forKey: .notes)
        
        // Convert dictionary to Data
        let jsonData = try JSONSerialization.data(withJSONObject: parsedJSON)
        try container.encode(jsonData, forKey: .parsedJSON)
    }
} 