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
    let location: String?
    let tournamentType: String?
    let series: String?
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = data["userId"] as? String ?? ""
        self.gameType = data["gameType"] as? String ?? ""
        self.gameName = data["gameName"] as? String ?? ""
        self.stakes = data["stakes"] as? String ?? ""
        
        // More detailed date logging
        if let startDateTimestamp = data["startDate"] as? Timestamp {
            self.startDate = startDateTimestamp.dateValue()

        } else {

            self.startDate = Date()
        }
        
        if let startTimeTimestamp = data["startTime"] as? Timestamp {
            self.startTime = startTimeTimestamp.dateValue()

        } else {

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

        } else {
            self.createdAt = Date()
        }
        
        self.notes = data["notes"] as? [String]
        self.liveSessionUUID = data["liveSessionUUID"] as? String
        
        // Populate new tournament-specific fields
        self.location = data["location"] as? String
        self.tournamentType = data["tournamentType"] as? String
        self.series = data["series"] as? String
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
               lhs.liveSessionUUID == rhs.liveSessionUUID &&
               lhs.location == rhs.location &&
               lhs.tournamentType == rhs.tournamentType &&
               lhs.series == rhs.series
    }
}

// Model to track active live session

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession = LiveSessionData()
    @Published var showLiveSessionBar = false
    
    // Computed property to get the most recent session
    var mostRecentSession: Session? {
        return sessions.first // sessions is already sorted by date descending
    }
    
    // Enhanced live session data
    @Published var enhancedLiveSession = LiveSessionData_Enhanced(basicSession: LiveSessionData())
    
    private let db = Firestore.firestore()
    private let userId: String
    private var timer: Timer?
    
    init(userId: String) {
        self.userId = userId
        print("🔄 SESSION STORE: Initializing for user \(userId)")
        
        // Initialize with clean defaults
        self.liveSession = LiveSessionData()
        self.enhancedLiveSession = LiveSessionData_Enhanced(basicSession: self.liveSession)
        self.showLiveSessionBar = false
        
        // Load any existing session state
        loadLiveSessionState()
        
        // Fetch historical sessions
        fetchSessions()
        
        // Validate the loaded state
        if !validateSessionState() {
            print("⚠️ SESSION STORE: Initial state validation failed")
        }
        
        print("🔄 SESSION STORE: Initialization complete - isActive: \(liveSession.isActive), showBar: \(showLiveSessionBar)")
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
    
    // Update a note at a specific index
    func updateNote(at index: Int, with newText: String) {
        guard enhancedLiveSession.notes.indices.contains(index) else {

            return
        }
        enhancedLiveSession.notes[index] = newText
        saveEnhancedLiveSessionState()
    }
    
    // MARK: - Session Database Operations
    
    func fetchSessions() {

        db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .order(by: "startDate", descending: true)
            .order(by: "startTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {

                    return
                }
                
                guard let documents = snapshot?.documents else {

                    return
                }
                

                
                self?.sessions = documents.map { document in
                    let data = document.data()




                    return Session(id: document.documentID, data: data)
                }
                

                self?.sessions.forEach { session in




                }
            }
    }
    
    func addSession(_ sessionData: [String: Any], completion: @escaping (Error?) -> Void) {
        db.collection("sessions").addDocument(data: sessionData, completion: completion)
    }
    
    func deleteSession(_ sessionId: String, completion: @escaping (Error?) -> Void) {
        db.collection("sessions").document(sessionId).delete(completion: completion)
    }
    
    // Method to update session details in Firestore
    func updateSessionDetails(sessionId: String, updatedData: [String: Any], completion: @escaping (Error?) -> Void) {
        db.collection("sessions").document(sessionId).updateData(updatedData) { error in
            if let error = error {

                completion(error)
            } else {

                // Refresh the local sessions array to reflect changes
                self.fetchSessions() 
                completion(nil)
            }
        }
    }
    
    // New method to get a session by its ID from the fetched list
    func getSessionById(_ id: String) -> Session? {
        return sessions.first(where: { $0.id == id })
    }
    
    // MARK: - Live Session Management
    
    func startLiveSession(gameName: String, stakes: String, buyIn: Double, isTournament: Bool = false, tournamentDetails: (name: String, type: String, baseBuyIn: Double)? = nil) {
        stopLiveSessionTimer() // Ensure any existing timer is stopped
        liveSession = LiveSessionData(
            isActive: true,
            startTime: Date(),
            elapsedTime: 0,
            gameName: isTournament ? (tournamentDetails?.name ?? gameName) : gameName,
            stakes: isTournament ? (tournamentDetails?.type ?? stakes) : stakes,
            buyIn: isTournament ? (tournamentDetails?.baseBuyIn ?? buyIn) : buyIn,
            lastPausedAt: nil,
            lastActiveAt: Date(),
            isTournament: isTournament,
            tournamentName: tournamentDetails?.name,
            tournamentType: tournamentDetails?.type,
            baseTournamentBuyIn: tournamentDetails?.baseBuyIn
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
    
    // Modify endLiveSessionAsync to return the new session ID or nil
    func endLiveSessionAndGetId(cashout: Double) async -> String? {
        stopLiveSessionTimer()
        
        let currentLiveSessionId = liveSession.id

        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": liveSession.isTournament ? SessionLogType.tournament.rawValue : SessionLogType.cashGame.rawValue,
            "gameName": liveSession.gameName,
            "stakes": liveSession.stakes,
            "startDate": Timestamp(date: liveSession.startTime),
            "startTime": Timestamp(date: liveSession.startTime),
            "endTime": Timestamp(date: Date()), // Current time for end time
            "hoursPlayed": liveSession.elapsedTime / 3600,
            "buyIn": liveSession.buyIn, // This now includes all rebuys for tournaments too
            "cashout": cashout,
            "profit": cashout - liveSession.buyIn, // liveSession.buyIn is total for both types
            "createdAt": FieldValue.serverTimestamp(), // Firestore server timestamp for creation
            "notes": enhancedLiveSession.notes, // Include notes
            "liveSessionUUID": currentLiveSessionId, // Link to the live session instance
            "location": liveSession.isTournament ? (liveSession.tournamentName) : nil, // Assuming tournament name can be used as a proxy for location if not separately stored for live
            "tournamentType": liveSession.isTournament ? liveSession.tournamentType : nil,
        ]
        
        do {
            let docRef = try await db.collection("sessions").addDocument(data: sessionData)
            // After successful save, properly end and clear the live session state
            endAndClearLiveSession()
            return docRef.documentID // Return the new document ID
        } catch {

            return nil // Return nil if saving failed
        }
    }
    
    // Mark session as ended and then clear it
    func endAndClearLiveSession() {
        stopLiveSessionTimer()
        
        // SCORCHED EARTH: Mark session as ended before clearing
        liveSession.isEnded = true
        liveSession.isActive = false
        liveSession.lastActiveAt = nil
        liveSession.lastPausedAt = Date()
        saveLiveSessionState() // Save the ended state
        
        // SCORCHED EARTH: Complete state clearing with multiple safety checks
        scorachedEarthSessionClear()
    }
    
    // SCORCHED EARTH: Complete session clearing with all safety mechanisms
    func scorachedEarthSessionClear() {
        print("🔥 SCORCHED EARTH: Starting complete session clearing")
        
        // Stop all timers immediately
        stopLiveSessionTimer()
        
        // Reset all session data to clean state
        liveSession = LiveSessionData()
        enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        showLiveSessionBar = false
        
        // Clear ALL possible UserDefaults keys (current and legacy)
        let possibleKeys = [
            "LiveSession_\(userId)",
            "EnhancedLiveSession_\(userId)",
            "liveSession_\(userId)",
            "enhancedLiveSession_\(userId)",
            "LiveSessionData_\(userId)",
            "SessionStore_\(userId)",
            "ActiveSession_\(userId)"
        ]
        
        for key in possibleKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Force synchronize UserDefaults
        UserDefaults.standard.synchronize()
        
        // Triple-check that nothing is left
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for key in possibleKeys {
                if UserDefaults.standard.object(forKey: key) != nil {
                    print("⚠️ SCORCHED EARTH: Found lingering data for key: \(key)")
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            UserDefaults.standard.synchronize()
            
            // Final verification
            self.verifySessionCleared()
        }
        
        print("🔥 SCORCHED EARTH: Session clearing complete")
    }
    
    // SCORCHED EARTH: Verify session is completely cleared
    func verifySessionCleared() {
        let isCleared = liveSession.buyIn == 0 && 
                       !liveSession.isActive && 
                       liveSession.isEnded == false && // Default state
                       !showLiveSessionBar &&
                       enhancedLiveSession.chipUpdates.isEmpty &&
                       enhancedLiveSession.notes.isEmpty &&
                       enhancedLiveSession.handHistories.isEmpty
        
        if isCleared {
            print("✅ SCORCHED EARTH: Session successfully cleared")
        } else {
            print("❌ SCORCHED EARTH: Session NOT fully cleared - forcing reset")
            forceResetSession()
        }
    }
    
    // SCORCHED EARTH: Force reset if normal clearing failed
    func forceResetSession() {
        liveSession = LiveSessionData()
        enhancedLiveSession = LiveSessionData_Enhanced(basicSession: LiveSessionData())
        showLiveSessionBar = false
        timer?.invalidate()
        timer = nil
        
        // Nuclear option: clear ALL UserDefaults for this user
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
        
        print("💥 SCORCHED EARTH: Force reset complete")
    }
    
    // Force clear any stuck session data (useful for debugging or recovery)
    func forceClearAllSessionData() {
        print("🔥 FORCE CLEAR: Starting emergency session clearing")
        scorachedEarthSessionClear()
    }
    
    // SCORCHED EARTH: Enhanced session validation
    func validateSessionState() -> Bool {
        // Check if session should exist but doesn't make sense
        if liveSession.buyIn > 0 && liveSession.isEnded {
            print("⚠️ VALIDATION: Found ended session with buy-in - clearing")
            scorachedEarthSessionClear()
            return false
        }
        
        // Check for impossible states
        if liveSession.isActive && liveSession.buyIn == 0 {
            print("⚠️ VALIDATION: Found active session with no buy-in - clearing")
            scorachedEarthSessionClear()
            return false
        }
        
        // Check for stale sessions (more than 24 hours old)
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        if liveSession.startTime < dayAgo && !liveSession.isEnded {
            print("⚠️ VALIDATION: Found stale session - clearing")
            scorachedEarthSessionClear()
            return false
        }
        
        return true
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
    
    func saveLiveSessionState() {
        if let encoded = try? JSONEncoder().encode(liveSession) {
            UserDefaults.standard.set(encoded, forKey: "LiveSession_\(userId)")
        }
    }
    
    private func loadLiveSessionState() {
        if let savedData = UserDefaults.standard.data(forKey: "LiveSession_\(userId)"),
           let loadedSession = try? JSONDecoder().decode(LiveSessionData.self, from: savedData) {
            
            // SCORCHED EARTH: Enhanced validation before restoring
            print("🔍 LOADING: Found saved session data")
            
            // If isEnded is true, it's definitively ended. Clear it and return.
            if loadedSession.isEnded {
                print("🗑️ LOADING: Session marked as ended - clearing")
                scorachedEarthSessionClear()
                return
            }

            // SCORCHED EARTH: Check for corrupted or invalid session data
            if loadedSession.buyIn < 0 || loadedSession.elapsedTime < 0 {
                print("⚠️ LOADING: Found corrupted session data - clearing")
                scorachedEarthSessionClear()
                return
            }

            let isPotentiallyRestorable = loadedSession.isActive || loadedSession.lastPausedAt != nil
            let hasValidBuyIn = loadedSession.buyIn > 0

            // SCORCHED EARTH: Enhanced staleness check
            let lastActivityTime = loadedSession.lastActiveAt ?? loadedSession.lastPausedAt ?? loadedSession.startTime
            let timeSinceLastActivity = Date().timeIntervalSince(lastActivityTime)
            let isAbandoned = timeSinceLastActivity > (48 * 60 * 60) // Increased to 48 hours for more lenient restoration

            // SCORCHED EARTH: More aggressive validation
            let isCorrupted = loadedSession.startTime > Date() || // Future start time
                             loadedSession.elapsedTime > (7 * 24 * 60 * 60) || // More than 7 days
                             (loadedSession.isActive && loadedSession.lastActiveAt == nil) // Active but no lastActiveAt

            if isCorrupted {
                print("💥 LOADING: Detected corrupted session - clearing")
                scorachedEarthSessionClear()
                return
            }

            if hasValidBuyIn && isPotentiallyRestorable && !isAbandoned {
                print("✅ LOADING: Restoring valid session")
                // This session looks like it should be restored.
                var sessionToRestore = loadedSession
                if sessionToRestore.isActive, let lastActive = sessionToRestore.lastActiveAt {
                    // If it was active, calculate time passed since last active and add to elapsed.
                    let additionalTime = Date().timeIntervalSince(lastActive)
                    sessionToRestore.elapsedTime += additionalTime
                    sessionToRestore.lastActiveAt = Date() // Update last active to now
                }
                // If it was paused, it's loaded as is.
                
                self.liveSession = sessionToRestore
                
                if self.liveSession.isActive {
                    startLiveSessionTimer()
                }
                self.showLiveSessionBar = true
                loadEnhancedLiveSessionState() // Also load its associated enhanced data
                
                // SCORCHED EARTH: Validate the restored session
                if !validateSessionState() {
                    print("❌ LOADING: Restored session failed validation")
                    return
                }
            } else {
                print("🗑️ LOADING: Session doesn't meet restoration criteria - clearing")
                scorachedEarthSessionClear()
            }
        } else {
            print("📭 LOADING: No saved session data found")
            // No saved data, or decoding failed. Ensure a clean state for a new session.
            self.liveSession = LiveSessionData()
            self.enhancedLiveSession = LiveSessionData_Enhanced(basicSession: self.liveSession)
            self.showLiveSessionBar = false
        }
    }
    
    // SCORCHED EARTH: Add backward compatibility method
    func clearLiveSession() {
        scorachedEarthSessionClear()
    }
    
    // SCORCHED EARTH: Emergency session reset function for UI access
    func emergencySessionReset() {
        print("🚨 EMERGENCY RESET: User triggered emergency session reset")
        
        // Stop all timers
        timer?.invalidate()
        timer = nil
        
        // Clear all session data
        liveSession = LiveSessionData()
        enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        showLiveSessionBar = false
        
        // Clear all possible UserDefaults keys for this user
        let allPossibleKeys = [
            "LiveSession_\(userId)",
            "LiveSessionEnhanced_\(userId)",
            "SessionState_\(userId)",
            "ActiveSession_\(userId)",
            "CurrentSession_\(userId)"
        ]
        
        for key in allPossibleKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Force synchronize UserDefaults
        UserDefaults.standard.synchronize()
        
        // Re-verify everything is clear
        if UserDefaults.standard.data(forKey: "LiveSession_\(userId)") != nil {
            print("⚠️ EMERGENCY: UserDefaults still contains session data after clear!")
        }
        
        print("✅ EMERGENCY RESET: Complete")
    }
    
    deinit {
        stopLiveSessionTimer()
    }
} 