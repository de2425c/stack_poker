import Foundation
import FirebaseFirestore

// Structure to hold chip stack updates
struct ChipStackUpdate: Identifiable, Codable {
    let id: String
    let amount: Double
    let note: String?
    let timestamp: Date
    let isPostedToFeed: Bool
    
    init(id: String = UUID().uuidString, amount: Double, note: String? = nil, timestamp: Date = Date(), isPostedToFeed: Bool = false) {
        self.id = id
        self.amount = amount
        self.note = note
        self.timestamp = timestamp
        self.isPostedToFeed = isPostedToFeed
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "amount": amount,
            "timestamp": timestamp,
            "isPostedToFeed": isPostedToFeed
        ]
        
        if let note = note, !note.isEmpty {
            dict["note"] = note
        }
        
        return dict
    }
    
    static func from(dictionary: [String: Any]) -> ChipStackUpdate? {
        guard let id = dictionary["id"] as? String,
              let amount = dictionary["amount"] as? Double else {
            return nil
        }
        
        let note = dictionary["note"] as? String
        let isPostedToFeed = dictionary["isPostedToFeed"] as? Bool ?? false
        let timestamp = (dictionary["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        
        return ChipStackUpdate(id: id, amount: amount, note: note, timestamp: timestamp, isPostedToFeed: isPostedToFeed)
    }
}

// Structure to hold hand history entries
struct HandHistoryEntry: Identifiable, Codable {
    let id: String
    let content: String
    let timestamp: Date
    
    init(id: String = UUID().uuidString, content: String, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
    
    var dictionary: [String: Any] {
        return [
            "id": id,
            "content": content,
            "timestamp": timestamp
        ]
    }
    
    static func from(dictionary: [String: Any]) -> HandHistoryEntry? {
        guard let id = dictionary["id"] as? String,
              let content = dictionary["content"] as? String else {
            return nil
        }
        
        let timestamp = (dictionary["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        
        return HandHistoryEntry(id: id, content: content, timestamp: timestamp)
    }
}

// MARK: - Live Session Core Model
struct LiveSessionData: Codable {
    /// Unique identifier for the live session – used for tagging related data (e.g. hands).
    var id: String = UUID().uuidString

    /// Indicates if the timer is currently running ( `true` = live / `false` = paused )
    var isActive: Bool = false

    /// When the session was started
    var startTime: Date = Date()

    /// Total number of seconds that have elapsed (excluding paused time)
    var elapsedTime: TimeInterval = 0

    /// Venue / game name (e.g. "Wynn")
    var gameName: String = ""

    /// Stakes string displayed to the user (e.g. "$2/$5")
    var stakes: String = ""

    /// Initial buy-in amount
    var buyIn: Double = 0

    /// Timestamp when the session was last paused ( `nil` if never paused )
    var lastPausedAt: Date? = nil

    /// Timestamp when the session was last resumed ( `nil` if currently paused )
    var lastActiveAt: Date? = nil

    /// Explicitly set to `true` once the session is ended and results saved
    var isEnded: Bool = false

    // MARK: - Tournament Specific Data (for live session persistence)
    var isTournament: Bool = false
    var tournamentName: String? = nil // Name of the tournament
    var tournamentType: String? = nil // e.g., NLH, PLO (used as stakes for tournaments)
    var baseTournamentBuyIn: Double? = nil // Initial buy-in for the tournament (excluding rebuys)
    var tournamentGameType: TournamentGameType? = nil // Tournament game type (NLH, PLO, Other)
    var tournamentFormat: TournamentFormat? = nil // Tournament format (Standard, PKO, etc.)
    var casino: String? = nil // Casino where the tournament is held
    
    // MARK: - Cash Game Specific Data
    var pokerVariant: String? = nil // Poker variant for cash games (e.g., "No Limit Hold'em", "Pot Limit Omaha")
    
    // MARK: - Multi-Day Session Support
    var currentDay: Int = 1 // Current day of multi-day session (1, 2, 3, etc.)
    var pausedForNextDay: Bool = false // Special pause flag for multi-day sessions
    var pausedForNextDayDate: Date? = nil // Date when the session was paused for next day
    
    // MARK: - Public Session Support
    var isPublicSession: Bool = false // Whether this session is being shared publicly
    var publicSessionId: String? = nil // Firestore document ID for the public session
}

// Extended LiveSessionData to include updates and hand histories
extension LiveSessionData {
    struct Enhanced: Codable {
        var basicSession: LiveSessionData
        var chipUpdates: [ChipStackUpdate]
        var handHistories: [HandHistoryEntry]
        var notes: [String]
        
        init(basicSession: LiveSessionData) {
            self.basicSession = basicSession
            self.chipUpdates = []
            self.handHistories = []
            self.notes = []
        }
        
        // Get the latest chip amount (or buy-in if no updates)
        var currentChipAmount: Double {
            let lastAmount = chipUpdates.last?.amount ?? basicSession.buyIn
            // Protect against invalid values that could cause crashes
            if lastAmount.isNaN || lastAmount.isInfinite || lastAmount < 0 {
                return basicSession.buyIn // Fall back to buy-in if invalid
            }
            return lastAmount
        }
        
        // Calculate profit/loss based on latest chip amount
        var currentProfit: Double {
            return currentChipAmount - basicSession.buyIn
        }
        
        // Get all chip amounts for graph (starting with buy-in)
        var allChipAmounts: [Double] {
            var amounts = [basicSession.buyIn]
            amounts.append(contentsOf: chipUpdates.map { $0.amount })
            return amounts
        }
        
        // Add a new chip stack update
        mutating func addChipUpdate(amount: Double, note: String?) {
            // Define maximum safe chip amount (1 trillion)
            let maxChipAmount: Double = 1_000_000_000_000
            
            // Protect against invalid values and maximum limit
            guard !amount.isNaN && !amount.isInfinite && amount >= 0 && amount <= maxChipAmount else {
                if amount > maxChipAmount {
                    print("Warning: Attempted to add chip amount exceeding maximum limit: \(amount)")
                } else {
                    print("Warning: Attempted to add invalid chip amount: \(amount)")
                }
                return
            }
            let update = ChipStackUpdate(amount: amount, note: note)
            chipUpdates.append(update)
        }
        
        // Add a new hand history
        mutating func addHandHistory(content: String) {
            let entry = HandHistoryEntry(content: content)
            handHistories.append(entry)
        }
        
        // Add a simple note
        mutating func addNote(note: String) {
            notes.append(note)
        }
        
        // Mark a chip update as posted to feed
        mutating func markUpdateAsPosted(id: String) {
            if let index = chipUpdates.firstIndex(where: { $0.id == id }) {
                let update = chipUpdates[index]
                let newUpdate = ChipStackUpdate(
                    id: update.id,
                    amount: update.amount,
                    note: update.note,
                    timestamp: update.timestamp,
                    isPostedToFeed: true
                )
                chipUpdates[index] = newUpdate
            }
        }
    }
}

// MARK: - Session Log Type (Cash or Tournament)
enum SessionLogType: String, CaseIterable, Identifiable {
    case cashGame = "CASH GAME"
    case tournament = "TOURNAMENT"
    var id: String { self.rawValue }
}

// MARK: - Tournament Log Model
struct TournamentLog: Identifiable, Codable {
    @DocumentID var id: String? // Firestore document ID
    let userId: String
    let tournamentName: String
    let tournamentType: String   // e.g., "MTT", "SNG", "PKO", "Custom"
    let location: String?        // New field for tournament location
    let buyIn: Double            // Cost per single entry - NOW TOTAL BUY-IN
    var totalInvestment: Double { // Calculated property - NOW SIMPLY BUY-IN
        return buyIn
    }
    let cashout: Double
    var profit: Double { // Calculated property
        return cashout - totalInvestment
    }
    let startDate: Date          // Date of the tournament
    let startTime: Date          // Actual start time on that date
    let endTime: Date            // Actual end time, could be next day relative to startDate + startTime
    let hoursPlayed: Double
    let notes: String?
    let createdAt: Timestamp     // Firestore server timestamp for record creation

    // Staking related fields are not directly part of this model.
    // A separate 'Stake' object will reference this TournamentLog's ID if staking is involved.
} 
