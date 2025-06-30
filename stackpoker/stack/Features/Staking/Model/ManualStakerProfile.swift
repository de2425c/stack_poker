import Foundation
import FirebaseFirestore

struct ManualStakerProfile: Codable, Identifiable {
    @DocumentID var id: String?
    let createdByUserId: String
    var name: String
    var contactInfo: String? // Optional phone, email, or other contact method
    var notes: String? // Optional notes about the staker
    let createdAt: Date
    var lastUpdatedAt: Date
    
    // Custom decoder to handle contactInfo being stored as either String or Number
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.createdByUserId = try container.decode(String.self, forKey: .createdByUserId)
        self.name = try container.decode(String.self, forKey: .name)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
        
        // Handle notes
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        
        // Handle contactInfo - could be String or Number
        if let contactString = try? container.decodeIfPresent(String.self, forKey: .contactInfo) {
            self.contactInfo = contactString
        } else if let contactNumber = try? container.decodeIfPresent(Int64.self, forKey: .contactInfo) {
            self.contactInfo = String(contactNumber)
        } else if let contactDouble = try? container.decodeIfPresent(Double.self, forKey: .contactInfo) {
            self.contactInfo = String(Int64(contactDouble))
        } else {
            self.contactInfo = nil
        }
    }
    
    // Computed property for display name
    var displayName: String {
        return name
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdByUserId
        case name
        case contactInfo
        case notes
        case createdAt
        case lastUpdatedAt
    }
    
    init(
        id: String? = nil,
        createdByUserId: String,
        name: String,
        contactInfo: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.createdByUserId = createdByUserId
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contactInfo = contactInfo?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
} 