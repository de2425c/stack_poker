import Foundation
import FirebaseFirestore

// MARK: - Bankroll Transaction
struct BankrollTransaction: Identifiable, Codable {
    let id: String
    let amount: Double // Positive for add, negative for subtract
    let note: String?
    let timestamp: Date
    
    init(id: String = UUID().uuidString, amount: Double, note: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.amount = amount
        self.note = note
        self.timestamp = timestamp
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "amount": amount,
            "timestamp": timestamp
        ]
        
        if let note = note, !note.isEmpty {
            dict["note"] = note
        }
        
        return dict
    }
    
    static func from(dictionary: [String: Any]) -> BankrollTransaction? {
        guard let id = dictionary["id"] as? String,
              let amount = dictionary["amount"] as? Double else {
            return nil
        }
        
        let note = dictionary["note"] as? String
        let timestamp = (dictionary["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        
        return BankrollTransaction(id: id, amount: amount, note: note, timestamp: timestamp)
    }
}

// MARK: - Bankroll Summary
struct BankrollSummary: Codable {
    let currentTotal: Double
    let lastUpdated: Date
    
    init(currentTotal: Double = 0.0, lastUpdated: Date = Date()) {
        self.currentTotal = currentTotal
        self.lastUpdated = lastUpdated
    }
    
    var dictionary: [String: Any] {
        return [
            "currentTotal": currentTotal,
            "lastUpdated": lastUpdated
        ]
    }
    
    static func from(dictionary: [String: Any]) -> BankrollSummary? {
        let currentTotal = dictionary["currentTotal"] as? Double ?? 0.0
        let lastUpdated = (dictionary["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
        
        return BankrollSummary(currentTotal: currentTotal, lastUpdated: lastUpdated)
    }
} 