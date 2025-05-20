import Foundation
import FirebaseFirestore
import SwiftUI

// Provide an alias so existing references remain valid within the module
typealias LiveSessionData_Enhanced = LiveSessionData.Enhanced

struct Session: Identifiable, Equatable {
    let id: String
    let userId: String
    let gameType: String
    let gameName: String
    let stakes: String
    let startDate: Date
    let startTime: Date
    let endTime: Date
    let hoursPlayed: Double
    let buyIn: Double
    let cashout: Double
    let profit: Double
    let createdAt: Date
    let notes: [String]?
    let liveSessionUUID: String?
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = data["userId"] as? String ?? ""
        self.gameType = data["gameType"] as? String ?? ""
        self.gameName = data["gameName"] as? String ?? ""
        self.stakes = data["stakes"] as? String ?? ""
        
        // More detailed date logging
        if let startDateTimestamp = data["startDate"] as? Timestamp {
            self.startDate = startDateTimestamp.dateValue()
            print("📅 Session \(id) startDate: \(startDateTimestamp.dateValue())")
        } else {
            print("⚠️ No startDate timestamp for session \(id)")
            self.startDate = Date()
        }
        
        if let startTimeTimestamp = data["startTime"] as? Timestamp {
            self.startTime = startTimeTimestamp.dateValue()
            print("🕒 Session \(id) startTime: \(startTimeTimestamp.dateValue())")
        } else {
            print("⚠️ No startTime timestamp for session \(id)")
            self.startTime = Date()
        }
        
        if let endTimeTimestamp = data["endTime"] as? Timestamp {
            self.endTime = endTimeTimestamp.dateValue()
        } else {
            self.endTime = Date()
        }
        
        self.hoursPlayed = data["hoursPlayed"] as? Double ?? 0
        self.buyIn = data["buyIn"] as? Double ?? 0
        self.cashout = data["cashout"] as? Double ?? 0
        self.profit = data["profit"] as? Double ?? 0
        
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdAtTimestamp.dateValue()
            print("📝 Session \(id) createdAt: \(createdAtTimestamp.dateValue())")
        } else {
            self.createdAt = Date()
        }
        
        self.notes = data["notes"] as? [String]
        self.liveSessionUUID = data["liveSessionUUID"] as? String
    }
    
    static func == (lhs: Session, rhs: Session) -> Bool {
        return lhs.id == rhs.id &&
               lhs.userId == rhs.userId &&
               lhs.gameType == rhs.gameType &&
               lhs.gameName == rhs.gameName &&
               lhs.stakes == rhs.stakes &&
               lhs.startDate == rhs.startDate &&
               lhs.startTime == rhs.startTime &&
               lhs.endTime == rhs.endTime &&
               lhs.hoursPlayed == rhs.hoursPlayed &&
               lhs.buyIn == rhs.buyIn &&
               lhs.cashout == rhs.cashout &&
               lhs.profit == rhs.profit &&
               lhs.createdAt == rhs.createdAt &&
               lhs.notes == rhs.notes &&
               lhs.liveSessionUUID == rhs.liveSessionUUID
    }
}

// Model to track active live session

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession = LiveSessionData()
    @Published var showLiveSessionBar = false
    
    // Enhanced live session data
    @Published var enhancedLiveSession = LiveSessionData_Enhanced(basicSession: LiveSessionData())
    
    private let db = Firestore.firestore()
    private let userId: String
    private var timer: Timer?
    
    init(userId: String) {
        print("📱 SessionStore initialized with userId: \(userId)")
        self.userId = userId
        fetchSessions()
        loadLiveSessionState()
    }
    
    // MARK: - Enhanced Session Methods
    
    // Update chip stack and add optional note
    func updateChipStack(amount: Double, note: String? = nil) {
        enhancedLiveSession.chipUpdates.append(
            ChipStackUpdate(amount: amount, note: note)
        )
        
        // Save the enhanced state
        saveEnhancedLiveSessionState()
    }
    
    // Add hand history entry
    func addHandHistory(content: String) {
        enhancedLiveSession.handHistories.append(
            HandHistoryEntry(content: content)
        )
        
        // Save the enhanced state
        saveEnhancedLiveSessionState()
    }
    
    // Add a simple note
    func addNote(note: String) {
        enhancedLiveSession.notes.append(note)
        
        // Save the enhanced state
        saveEnhancedLiveSessionState()
    }
    
    // Mark update as posted to feed
    func markUpdateAsPosted(id: String) {
        if let index = enhancedLiveSession.chipUpdates.firstIndex(where: { $0.id == id }) {
            var updatedChipUpdates = enhancedLiveSession.chipUpdates
            
            // Create a new update with isPostedToFeed = true
            let update = updatedChipUpdates[index]
            let newUpdate = ChipStackUpdate(
                id: update.id,
                amount: update.amount,
                note: update.note,
                timestamp: update.timestamp,
                isPostedToFeed: true
            )
            
            // Replace the old update with the new one
            updatedChipUpdates[index] = newUpdate
            enhancedLiveSession.chipUpdates = updatedChipUpdates
        }
        
        // Save the enhanced state
        saveEnhancedLiveSessionState()
    }
    
    // MARK: - Session Database Operations
    
    func fetchSessions() {
        print("🔍 Fetching sessions for user: \(userId)")
        db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .order(by: "startDate", descending: true)
            .order(by: "startTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching sessions: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ No documents found in snapshot")
                    return
                }
                
                print("📄 Received \(documents.count) session documents")
                
                self?.sessions = documents.map { document in
                    let data = document.data()
                    print("\n🔍 Processing session: \(document.documentID)")
                    print("Raw startDate: \(String(describing: data["startDate"]))")
                    print("Raw startTime: \(String(describing: data["startTime"]))")
                    print("Profit: \(data["profit"] as? Double ?? 0)")
                    return Session(id: document.documentID, data: data)
                }
                
                print("\n✅ Final sessions array:")
                self?.sessions.forEach { session in
                    print("ID: \(session.id)")
                    print("Date: \(session.startDate)")
                    print("Profit: \(session.profit)")
                    print("---")
                }
            }
    }
    
    func addSession(_ sessionData: [String: Any], completion: @escaping (Error?) -> Void) {
        db.collection("sessions").addDocument(data: sessionData, completion: completion)
    }
    
    func deleteSession(_ sessionId: String, completion: @escaping (Error?) -> Void) {
        db.collection("sessions").document(sessionId).delete(completion: completion)
    }
    
    // MARK: - Live Session Management
    
    func startLiveSession(gameName: String, stakes: String, buyIn: Double) {
        stopLiveSessionTimer() // Ensure any existing timer is stopped
        liveSession = LiveSessionData(
            isActive: true,
            startTime: Date(),
            elapsedTime: 0,
            gameName: gameName,
            stakes: stakes,
            buyIn: buyIn,
            lastPausedAt: nil,
            lastActiveAt: Date()
        )
        
        // Initialize enhanced session data
        enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        
        startLiveSessionTimer()
        showLiveSessionBar = true
        saveLiveSessionState()
        saveEnhancedLiveSessionState()
    }
    
    func pauseLiveSession() {
        var session = liveSession
        session.isActive = false
        session.lastPausedAt = Date()
        if let lastActive = session.lastActiveAt {
            session.elapsedTime += Date().timeIntervalSince(lastActive)
        }
        session.lastActiveAt = nil
        liveSession = session // triggers SwiftUI update
        stopLiveSessionTimer()
        saveLiveSessionState()
    }
    
    func resumeLiveSession() {
        var session = liveSession
        session.isActive = true
        session.lastActiveAt = Date() // set to now
        liveSession = session // triggers SwiftUI update
        startLiveSessionTimer()
        saveLiveSessionState()
    }
    
    func updateLiveSessionBuyIn(amount: Double) {
        liveSession.buyIn += amount
        saveLiveSessionState()
    }
    
    func setTotalBuyIn(amount: Double) {
        liveSession.buyIn = amount
        saveLiveSessionState()
    }
    
    func endLiveSession(cashout: Double, completion: @escaping (Error?) -> Void) {
        stopLiveSessionTimer()
        
        let currentLiveSessionId = liveSession.id

        // Create a copy of the current session data for saving
        var sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "CASH GAME",
            "gameName": liveSession.gameName,
            "stakes": liveSession.stakes,
            "startDate": Timestamp(date: liveSession.startTime),
            "startTime": Timestamp(date: liveSession.startTime),
            "endTime": Timestamp(date: Date()),
            "hoursPlayed": liveSession.elapsedTime / 3600, // Convert to hours
            "buyIn": liveSession.buyIn,
            "cashout": cashout,
            "profit": cashout - liveSession.buyIn,
            "createdAt": FieldValue.serverTimestamp(),
            "notes": enhancedLiveSession.notes,
            "liveSessionUUID": currentLiveSessionId
        ]
        
        addSession(sessionData) { error in
            if error == nil {
                // Important: Only clear session AFTER successful save
                self.clearLiveSession()
            }
            completion(error)
        }
    }
    
    func endLiveSessionAsync(cashout: Double) async -> Error? {
        stopLiveSessionTimer()
        
        let currentLiveSessionId = liveSession.id

        // Create a copy of the current session data for saving
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "CASH GAME",
            "gameName": liveSession.gameName,
            "stakes": liveSession.stakes,
            "startDate": Timestamp(date: liveSession.startTime),
            "startTime": Timestamp(date: liveSession.startTime),
            "endTime": Timestamp(date: Date()),
            "hoursPlayed": liveSession.elapsedTime / 3600, // Convert to hours
            "buyIn": liveSession.buyIn,
            "cashout": cashout,
            "profit": cashout - liveSession.buyIn,
            "createdAt": FieldValue.serverTimestamp(),
            "notes": enhancedLiveSession.notes,
            "liveSessionUUID": currentLiveSessionId
        ]
        
        do {
            // Create a new document reference
            let docRef = db.collection("sessions").document()
            
            // Save the session data
            try await docRef.setData(sessionData)
            
            // IMPORTANT: Explicitly clear the session state after saving
            clearLiveSession()
            
            return nil
        } catch let error {
            print("Error saving session: \(error.localizedDescription)")
            return error
        }
    }
    
    func clearLiveSession() {
        stopLiveSessionTimer()
        
        // Reset everything immediately
        liveSession = LiveSessionData()
        enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        showLiveSessionBar = false
        
        // Remove from UserDefaults
        removeLiveSessionState()
        removeEnhancedLiveSessionState()
    }
    
    // MARK: - Timer Management
    
    private func startLiveSessionTimer() {
        stopLiveSessionTimer() // Ensure no duplicate timers
        var session = liveSession
        if session.isActive {
            session.lastActiveAt = Date()
            liveSession = session
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.liveSession.isActive, let lastActive = self.liveSession.lastActiveAt {
                let now = Date()
                let elapsed = now.timeIntervalSince(lastActive)
                self.liveSession.elapsedTime += elapsed
                self.liveSession.lastActiveAt = now
            }
            if Int(self.liveSession.elapsedTime) % 60 == 0 {
                self.saveLiveSessionState()
            }
        }
    }
    
    func stopLiveSessionTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - State Persistence for Enhanced Session
    
    private func saveEnhancedLiveSessionState() {
        if let encoded = try? JSONEncoder().encode(enhancedLiveSession) {
            UserDefaults.standard.set(encoded, forKey: "EnhancedLiveSession_\(userId)")
        }
    }
    
    private func loadEnhancedLiveSessionState() {
        if let savedData = UserDefaults.standard.data(forKey: "EnhancedLiveSession_\(userId)"),
           let loadedSession = try? JSONDecoder().decode(LiveSessionData_Enhanced.self, from: savedData) {
            enhancedLiveSession = loadedSession
        } else {
            // If no enhanced data, initialize with current basic session
            enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        }
    }
    
    private func removeEnhancedLiveSessionState() {
        UserDefaults.standard.removeObject(forKey: "EnhancedLiveSession_\(userId)")
    }
    
    // MARK: - State Persistence
    
    private func saveLiveSessionState() {
        if let encoded = try? JSONEncoder().encode(liveSession) {
            UserDefaults.standard.set(encoded, forKey: "LiveSession_\(userId)")
        }
    }
    
    private func loadLiveSessionState() {
        if let savedData = UserDefaults.standard.data(forKey: "LiveSession_\(userId)"),
           let loadedSession = try? JSONDecoder().decode(LiveSessionData.self, from: savedData) {
            
            // Only restore if session is actually in progress (active or paused, not ended)
            if loadedSession.isActive || loadedSession.lastPausedAt != nil {
                if loadedSession.isActive, let lastActive = loadedSession.lastActiveAt {
                    let additionalTime = Date().timeIntervalSince(lastActive)
                    var updatedSession = loadedSession
                    updatedSession.elapsedTime += additionalTime
                    updatedSession.lastActiveAt = Date()
                    liveSession = updatedSession
                } else {
                    liveSession = loadedSession
                }
                
                if loadedSession.isActive {
                    startLiveSessionTimer()
                }
                showLiveSessionBar = true
                
                // Load enhanced state if available
                loadEnhancedLiveSessionState()
            } else {
                // If not active or paused, clear any lingering state
                clearLiveSession()
            }
        }
    }
    
    private func removeLiveSessionState() {
        UserDefaults.standard.removeObject(forKey: "LiveSession_\(userId)")
    }
    
    deinit {
        stopLiveSessionTimer()
    }
} 