import Foundation
import FirebaseFirestore
import SwiftUI
import FirebaseStorage

// Helper extension for string checks
extension String? {
    var isNilOrEmpty: Bool {
        return self?.isEmpty != false
    }
}

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
    let pokerVariant: String? // Poker variant for cash games
    let tournamentGameType: String? // Tournament game type
    let tournamentFormat: String? // Tournament format
    
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
        
        // Populate new poker variant field
        self.pokerVariant = data["pokerVariant"] as? String
        
        // Populate new tournament fields
        self.tournamentGameType = data["tournamentGameType"] as? String
        self.tournamentFormat = data["tournamentFormat"] as? String
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
               lhs.series == rhs.series &&
               lhs.pokerVariant == rhs.pokerVariant &&
               lhs.tournamentGameType == rhs.tournamentGameType &&
               lhs.tournamentFormat == rhs.tournamentFormat
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
    
    // Challenge service for updating challenges when sessions are completed
    private var challengeService: ChallengeService?
    
    // Maximum length (in seconds) that a live session is allowed to run (120 hours).
    private let maximumSessionDuration: TimeInterval = 120 * 60 * 60
    
    init(userId: String) {
        self.userId = userId
        print("🔄 SESSION STORE: Initializing for user \(userId)")

        guard !userId.isEmpty else {
            print("SessionStore: userId is empty, skipping load/fetch during account creation")
            // Initialize with clean defaults even if userId is empty, then return.
            self.liveSession = LiveSessionData()
            self.enhancedLiveSession = LiveSessionData_Enhanced(basicSession: self.liveSession)
            self.showLiveSessionBar = false
            return
        }
        
        // Initialize with clean defaults
        self.liveSession = LiveSessionData()
        self.enhancedLiveSession = LiveSessionData_Enhanced(basicSession: self.liveSession)
        self.showLiveSessionBar = false
        
        // Initialize challenge service asynchronously on main actor
        Task { @MainActor in
            self.challengeService = ChallengeService(userId: userId)
        }
        
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
    
    // Method to set challenge service (for dependency injection if needed)
    func setChallengeService(_ service: ChallengeService) {
        self.challengeService = service
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
    
    // MARK: - Duplicate Session Management
    
    /// Removes duplicate sessions based on identical buyIn, cashout, and startDate
    /// Returns the number of duplicate sessions that were deleted
    func removeDuplicateSessions(completion: @escaping (Result<Int, Error>) -> Void) {
        print("🔍 Starting duplicate session removal process...")
        
        // Group sessions by duplicate criteria
        var sessionGroups: [String: [Session]] = [:]
        
        for session in sessions {
            // Create a key based on buyIn, cashout, and startDate (rounded to nearest minute for date comparison)
            let calendar = Calendar.current
            let roundedStartDate = calendar.dateInterval(of: .minute, for: session.startDate)?.start ?? session.startDate
            let key = "\(session.buyIn)|\(session.cashout)|\(roundedStartDate.timeIntervalSince1970)"
            
            if sessionGroups[key] == nil {
                sessionGroups[key] = []
            }
            sessionGroups[key]?.append(session)
        }
        
        // Find groups with duplicates
        let duplicateGroups = sessionGroups.filter { $0.value.count > 1 }
        
        if duplicateGroups.isEmpty {
            print("✅ No duplicate sessions found")
            completion(.success(0))
            return
        }
        
        print("⚠️ Found \(duplicateGroups.count) groups with duplicates")
        
        // Collect sessions to delete (keep the one with earliest createdAt, delete the rest)
        var sessionsToDelete: [Session] = []
        
        for (key, duplicateSessions) in duplicateGroups {
            print("📊 Group key: \(key) has \(duplicateSessions.count) duplicates")
            
            // Sort by createdAt to keep the earliest one
            let sortedSessions = duplicateSessions.sorted { $0.createdAt < $1.createdAt }
            let sessionToKeep = sortedSessions.first!
            let sessionsToRemove = Array(sortedSessions.dropFirst())
            
            print("✅ Keeping session ID: \(sessionToKeep.id) (created: \(sessionToKeep.createdAt))")
            for sessionToRemove in sessionsToRemove {
                print("🗑️ Will delete session ID: \(sessionToRemove.id) (created: \(sessionToRemove.createdAt))")
                sessionsToDelete.append(sessionToRemove)
            }
        }
        
        let totalToDelete = sessionsToDelete.count
        print("🗑️ Total sessions to delete: \(totalToDelete)")
        
        if totalToDelete == 0 {
            completion(.success(0))
            return
        }
        
        // Delete sessions in batches
        let dispatchGroup = DispatchGroup()
        var deletedCount = 0
        var errors: [Error] = []
        
        for session in sessionsToDelete {
            dispatchGroup.enter()
            
            deleteSession(session.id) { error in
                if let error = error {
                    print("❌ Failed to delete session \(session.id): \(error.localizedDescription)")
                    errors.append(error)
                } else {
                    print("✅ Successfully deleted duplicate session \(session.id)")
                    deletedCount += 1
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if !errors.isEmpty {
                print("⚠️ Completed with \(deletedCount) deletions and \(errors.count) errors")
                completion(.failure(errors.first!))
            } else {
                print("✅ Successfully deleted \(deletedCount) duplicate sessions")
                // Refresh the sessions list after deletion
                self.fetchSessions()
                completion(.success(deletedCount))
            }
        }
    }
    
    // MARK: - Live Session Management
    
    func startLiveSession(gameName: String, stakes: String, buyIn: Double, isTournament: Bool = false, tournamentDetails: (name: String, type: String, baseBuyIn: Double)? = nil, pokerVariant: String? = nil, tournamentGameType: TournamentGameType? = nil, tournamentFormat: TournamentFormat? = nil, casino: String? = nil) {
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
            baseTournamentBuyIn: tournamentDetails?.baseBuyIn,
            tournamentGameType: tournamentGameType,
            tournamentFormat: tournamentFormat,
            casino: casino,
            pokerVariant: pokerVariant
            
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
            "tournamentGameType": liveSession.isTournament ? liveSession.tournamentGameType?.rawValue : nil,
            "tournamentFormat": liveSession.isTournament ? liveSession.tournamentFormat?.rawValue : nil,
            "pokerVariant": !liveSession.isTournament ? liveSession.pokerVariant : nil, // Only save poker variant for cash games
        ]
        
        do {
            let docRef = try await db.collection("sessions").addDocument(data: sessionData)
            
            // Create a Session object from the saved data for challenge updates
            let session = Session(id: docRef.documentID, data: sessionData)
            
            // Update session challenges if challenge service is available
            if let challengeService = challengeService {
                await challengeService.updateSessionChallengesFromSession(session)
            }
            
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
        
        // Use the emergency reset for maximum reliability - prevents any stuck sessions
        emergencySessionReset()
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
        
        // Check for stale sessions that have exceeded the maximum allowed duration
        let maxDurationAgo = Date().addingTimeInterval(-maximumSessionDuration)
        if liveSession.startTime < maxDurationAgo && !liveSession.isEnded {
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
            let isAbandoned = timeSinceLastActivity > maximumSessionDuration // 120-hour abandonment window

            // SCORCHED EARTH: More aggressive validation
            let isCorrupted = loadedSession.startTime > Date() || // Future start time
                             loadedSession.elapsedTime > maximumSessionDuration || // Exceeds maximum duration
                             (loadedSession.isActive && loadedSession.lastActiveAt == nil) // Active but no lastActiveAt

            if isCorrupted {
                print("💥 LOADING: Detected corrupted session - clearing")
                scorachedEarthSessionClear()
                return
            }

            // NEW CHECK: Look inside the persisted *enhanced* session for a final cashout entry.
            if let enhancedData = UserDefaults.standard.data(forKey: "EnhancedLiveSession_\(userId)"),
               let enhancedSession = try? JSONDecoder().decode(LiveSessionData_Enhanced.self, from: enhancedData) {
                let hasFinalCashout = enhancedSession.chipUpdates.contains { update in
                    update.note?.contains("Final cashout amount") == true
                }
                if hasFinalCashout {
                    print("🗑️ LOADING: Found 'Final cashout amount' in enhanced session – treating as ended and clearing")
                    scorachedEarthSessionClear()
                    return
                }
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
    
    // MARK: - Pokerbase CSV Import
    /// Imports sessions from a Pokerbase-formatted CSV file and saves the raw file to Firebase Storage for record-keeping.
    /// - Parameters:
    ///   - fileURL: Local URL to the CSV file selected by the user.
    ///   - completion: Completion handler returning the number of sessions imported on success, or an error.
    func importSessionsFromPokerbaseCSV(fileURL: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Ensure we can access the file (needed for Files-app / iCloud picks)
            let needsSecurity = fileURL.startAccessingSecurityScopedResource()
            defer {
                if needsSecurity { fileURL.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: fileURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file as UTF-8"])) )
                    }
                    return
                }

                // Split into non-empty rows
                let rows = content.components(separatedBy: CharacterSet.newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard rows.count > 1 else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -2, userInfo: [NSLocalizedDescriptionKey: "CSV appears to have no data rows"])) )
                    }
                    return
                }

                // Determine header columns (robust approach – trim BOM, spaces, quotes, case-insensitive)
                func columnsFromLine(_ line: String) -> [String] {
                    // Replace likely alternate delimiters with commas
                    let replaced = line.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "'", with: ",")
                    return replaced.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
                }

                let rawHeaders = columnsFromLine(rows[0])
                let headers = rawHeaders.map { raw -> String in
                    var cleaned = String(raw)
                    cleaned = cleaned.replacingOccurrences(of: "\u{FEFF}", with: "") // Remove BOM if present
                    cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " \"'\t\r\n")).lowercased()
                    return cleaned
                }

                func index(where predicate: (String) -> Bool) -> Int? {
                    return headers.firstIndex(where: predicate)
                }

                // Accept several possible header variants
                guard let startIdx = index(where: { $0.starts(with: "start") }),
                      let endIdx = index(where: { $0.starts(with: "end") }),
                      let locationIdx = index(where: { $0.contains("location") }),
                      let profitIdx = index(where: { $0.contains("profit") || $0.contains("result") || $0.contains("net") }) else {
                     DispatchQueue.main.async {
                         completion(.failure(NSError(domain: "CSV", code: -3, userInfo: [NSLocalizedDescriptionKey: "CSV is missing required columns (start, end, location, profit/result/net). Found headers: \(headers)"])) )
                     }
                     return
                }

                // Helper to parse numeric strings like "$1,234.56" or "-100"
                func parseDouble(_ str: String) -> Double? {
                    let cleaned = str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
                    return Double(cleaned)
                }

                let isoFormatter = ISO8601DateFormatter()
                var importedCount = 0
                let group = DispatchGroup()

                for row in rows.dropFirst() {
                    let columns = columnsFromLine(row).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard columns.count >= headers.count else { continue }

                    // Date parsing (ISO 8601 with timezone)
                    guard let startDate = isoFormatter.date(from: columns[startIdx]),
                          let endDate = isoFormatter.date(from: columns[endIdx]) else { continue }

                    guard let profitVal = parseDouble(columns[profitIdx]) else { continue }

                    let hours = endDate.timeIntervalSince(startDate) / 3600.0

                    let sessionData: [String: Any] = [
                        "userId": self.userId,
                        "gameType": SessionLogType.cashGame.rawValue,
                        "gameName": columns[locationIdx],
                        "stakes": "", // Not provided in CSV
                        "startDate": Timestamp(date: startDate),
                        "startTime": Timestamp(date: startDate),
                        "endTime": Timestamp(date: endDate),
                        "hoursPlayed": hours,
                        "buyIn": 0,
                        "cashout": profitVal,
                        "profit": profitVal,
                        "createdAt": FieldValue.serverTimestamp(),
                        "location": columns[locationIdx]
                    ]

                    group.enter()
                    self.addSession(sessionData) { error in
                        if error == nil {
                            importedCount += 1
                            print("✅ Row \(importedCount): Session added successfully")
                        } else {
                            print("❌ Row \(importedCount): Failed to add session - \(error?.localizedDescription ?? "Unknown error")")
                        }
                        group.leave()
                    }
                }

                group.wait()

                // After importing, refresh local sessions and upload the CSV file for archival.
                self.fetchSessions()

                let storageRef = Storage.storage().reference().child("pokerbaseImports/\(self.userId)/\(UUID().uuidString).csv")
                storageRef.putData(data, metadata: nil) { _, _ in }

                // Remove duplicates after import
                self.removeDuplicateSessions { duplicateResult in
                    switch duplicateResult {
                    case .success(let duplicatesRemoved):
                        print("✅ Pokerbase import: Removed \(duplicatesRemoved) duplicate sessions")
                    case .failure(let error):
                        print("⚠️ Pokerbase import: Failed to remove duplicates - \(error.localizedDescription)")
                    }
                }

                DispatchQueue.main.async {
                    completion(.success(importedCount))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Poker Analytics 6 Import (tab- or comma-separated)
    /// Imports sessions from a Poker Analytics 6 export. Only essential columns are used.
    /// Expected headers (case-insensitive): "Start Date", "End Date", "Buyin", "Cashed Out", "Net", "Location", "Blinds", "Type".
    /// - Note: Delimiter may be tab or comma. The importer auto-detects.
    func importSessionsFromPokerAnalyticsCSV(fileURL: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let needsSecurity = fileURL.startAccessingSecurityScopedResource()
            defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: fileURL)
                guard let rawContent = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file as UTF-8"])) )
                    }
                    return
                }

                // Normalize newlines, split rows
                let rows = rawContent.replacingOccurrences(of: "\r", with: "").split(separator: "\n").map { String($0) }
                guard rows.count > 1 else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -2, userInfo: [NSLocalizedDescriptionKey: "CSV appears empty"])) )
                    }
                    return
                }

                // Delimiter detection – tab preferred, else comma.
                let delimiter: Character = rows[0].contains("\t") ? "\t" : ","

                func split(_ line: String) -> [String] {
                    return line.split(separator: delimiter, omittingEmptySubsequences: false).map {
                        var s = String($0)
                        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
                        return s
                    }
                }

                let headerRaw = split(rows[0])
                let headers = headerRaw.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'" )).lowercased() }

                // Normalized headers: remove all non-letters for flexible matching
                let normalized: [String] = headers.map { $0.replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression) }

                func idx(_ variants: [String]) -> Int? {
                    for variant in variants {
                        if let i = normalized.firstIndex(of: variant) { return i }
                    }
                    return nil
                }

                guard let startIdx = idx(["startdate", "start"]),
                      let endIdx = idx(["enddate", "end"]),
                      let buyInIdx = idx(["buyin", "buy"]),
                      let cashedIdx = idx(["cashedout", "cashout", "cashouttotal", "winning"]),
                      let netIdx = idx(["net", "result", "profit"]),
                      let locationIdx = idx(["location", "venue"]) else {
                     DispatchQueue.main.async {
                         completion(.failure(NSError(domain: "CSV", code: -3, userInfo: [NSLocalizedDescriptionKey: "CSV missing required columns. Found headers: \(headerRaw)"])) )
                     }
                     return
                }

                let blindsIdx = idx(["blinds", "stakes"])
                let typeIdx = idx(["type", "gametype"])

                // Date formatter for Poker Analytics (MM/dd/yyyy HH:mm:ss)
                let df = DateFormatter()
                df.dateFormat = "MM/dd/yyyy HH:mm:ss"
                df.timeZone = TimeZone.current

                // Currency / number parsing helper
                func num(_ str: String) -> Double? {
                    let cleaned = str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
                    return Double(cleaned)
                }

                var imported = 0
                let group = DispatchGroup()

                for row in rows.dropFirst() where !row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let cols = split(row)
                    guard cols.count >= headers.count else { continue }

                    guard let sDate = df.date(from: cols[startIdx]),
                          let eDate = df.date(from: cols[endIdx]) else { continue }

                    let buyIn = num(cols[buyInIdx]) ?? 0
                    let cashOut = num(cols[cashedIdx]) ?? 0
                    let netProvided = num(cols[netIdx])
                    let profit = netProvided ?? (cashOut - buyIn)

                    let location = cols[locationIdx]
                    let stakes = blindsIdx != nil ? cols[blindsIdx!] : ""
                    let typeStr = typeIdx != nil ? cols[typeIdx!].lowercased() : "cash game"

                    let isTournament = typeStr.contains("tournament")

                    let hours = eDate.timeIntervalSince(sDate) / 3600.0

                    let sessionData: [String: Any] = [
                        "userId": self.userId,
                        "gameType": isTournament ? SessionLogType.tournament.rawValue : SessionLogType.cashGame.rawValue,
                        "gameName": location,
                        "stakes": stakes,
                        "startDate": Timestamp(date: sDate),
                        "startTime": Timestamp(date: sDate),
                        "endTime": Timestamp(date: eDate),
                        "hoursPlayed": hours,
                        "buyIn": buyIn,
                        "cashout": cashOut,
                        "profit": profit,
                        "createdAt": FieldValue.serverTimestamp(),
                        "location": location,
                        "tournamentType": isTournament ? stakes : nil
                    ]

                    group.enter()
                    self.addSession(sessionData) { error in
                        if error == nil { imported += 1 }
                        group.leave()
                    }
                }

                group.wait()
                self.fetchSessions()

                // Archive raw file
                let storageRef = Storage.storage().reference().child("pokerAnalyticsImports/\(self.userId)/\(UUID().uuidString).csv")
                storageRef.putData(data, metadata: nil) { _, _ in }

                // Remove duplicates after import
                self.removeDuplicateSessions { duplicateResult in
                    switch duplicateResult {
                    case .success(let duplicatesRemoved):
                        print("✅ Poker Analytics import: Removed \(duplicatesRemoved) duplicate sessions")
                    case .failure(let error):
                        print("⚠️ Poker Analytics import: Failed to remove duplicates - \(error.localizedDescription)")
                    }
                }

                DispatchQueue.main.async {
                    completion(.success(imported))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Poker Bankroll Tracker (PBT) Import
    /// Imports sessions from Poker Bankroll Tracker export format.
    /// Expected format: CSV with headers like id,starttime,endtime,variant,game,limit,location,type,buyin,cashout,netprofit...
    func importSessionsFromPBTCSV(fileURL: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let needsSecurity = fileURL.startAccessingSecurityScopedResource()
            defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: fileURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file as UTF-8"])) )
                    }
                    return
                }

                var lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                
                // Skip PBT header if present
                if let firstLine = lines.first, firstLine.contains("---PBT Bankroll Export---") {
                    lines.removeFirst()
                }
                
                guard lines.count > 1 else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -2, userInfo: [NSLocalizedDescriptionKey: "CSV appears to have no data rows"])) )
                    }
                    return
                }

                func parseCSVLine(_ line: String) -> [String] {
                    var result: [String] = []
                    var current = ""
                    var inQuotes = false
                    
                    for char in line {
                        if char == "\"" {
                            inQuotes.toggle()
                        } else if char == "," && !inQuotes {
                            result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                            current = ""
                        } else {
                            current.append(char)
                        }
                    }
                    result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    return result
                }

                let headerRow = parseCSVLine(lines[0])
                let headers = headerRow.map { $0.lowercased() }
                
                func idx(_ name: String) -> Int? {
                    return headers.firstIndex(of: name.lowercased())
                }

                guard let startIdx = idx("starttime"),
                      let endIdx = idx("endtime"),
                      let variantIdx = idx("variant"),
                      let gameIdx = idx("game"),
                      let locationIdx = idx("location"),
                      let buyinIdx = idx("buyin"),
                      let cashoutIdx = idx("cashout"),
                      let netprofitIdx = idx("netprofit") else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -3, userInfo: [NSLocalizedDescriptionKey: "CSV missing required PBT columns. Found headers: \(headers)"])) )
                    }
                    return
                }

                let limitIdx = idx("limit")
                let typeIdx = idx("type")
                let smallBlindIdx = idx("smallblind")
                let bigBlindIdx = idx("bigblind")
                let mttNameIdx = idx("mttname")
                let sessionNoteIdx = idx("sessionnote")

                // Date formatter for PBT format: "2025-05-30 12:24:00"
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                df.timeZone = TimeZone.current

                func num(_ str: String) -> Double? {
                    let cleaned = str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
                    return cleaned.isEmpty ? nil : Double(cleaned)
                }

                var imported = 0
                let group = DispatchGroup()

                for line in lines.dropFirst() {
                    let cols = parseCSVLine(line)
                    guard cols.count >= headers.count else { continue }

                    guard let startDate = df.date(from: cols[startIdx]),
                          let endDate = df.date(from: cols[endIdx]) else { continue }

                    let variant = cols[variantIdx].lowercased()
                    let isTournament = variant.contains("tournament")
                    let gameType = isTournament ? SessionLogType.tournament.rawValue : SessionLogType.cashGame.rawValue
                    
                    let game = cols[gameIdx]
                    let location = cols[locationIdx]
                    let type = typeIdx != nil ? cols[typeIdx!] : ""
                    
                    // Build stakes string from limit or blinds
                    var stakes = ""
                    if let limitIdx = limitIdx, !cols[limitIdx].isEmpty {
                        stakes = cols[limitIdx]
                    } else if let sbIdx = smallBlindIdx, let bbIdx = bigBlindIdx {
                        let sb = cols[sbIdx]
                        let bb = cols[bbIdx]
                        if !sb.isEmpty || !bb.isEmpty {
                            stakes = "\(sb)/\(bb)"
                        }
                    }
                    
                    let buyIn = num(cols[buyinIdx]) ?? 0
                    let cashOut = num(cols[cashoutIdx]) ?? 0
                    let netProfit = num(cols[netprofitIdx]) ?? (cashOut - buyIn)
                    
                    let hours = endDate.timeIntervalSince(startDate) / 3600.0
                    
                    // Combine game name with type for better context
                    let gameName = type.isEmpty ? game : "\(game) (\(type))"
                    let tournamentName = isTournament && mttNameIdx != nil ? cols[mttNameIdx!] : nil
                    let sessionNote = sessionNoteIdx != nil ? cols[sessionNoteIdx!] : nil
                    
                    var notes: [String] = []
                    if let note = sessionNote, !note.isEmpty {
                        notes.append(note)
                    }

                    let sessionData: [String: Any] = [
                        "userId": self.userId,
                        "gameType": gameType,
                        "gameName": !tournamentName.isNilOrEmpty ? tournamentName! : gameName,
                        "stakes": stakes,
                        "startDate": Timestamp(date: startDate),
                        "startTime": Timestamp(date: startDate),
                        "endTime": Timestamp(date: endDate),
                        "hoursPlayed": hours,
                        "buyIn": buyIn,
                        "cashout": cashOut,
                        "profit": netProfit,
                        "createdAt": FieldValue.serverTimestamp(),
                        "location": location,
                        "tournamentType": isTournament ? stakes : nil,
                        "notes": notes.isEmpty ? nil : notes
                    ]

                    group.enter()
                    self.addSession(sessionData) { error in
                        if error == nil {
                            imported += 1
                            print("✅ Row \(imported): Session added successfully")
                        } else {
                            print("❌ Row \(imported): Failed to add session - \(error?.localizedDescription ?? "Unknown error")")
                        }
                        group.leave()
                    }
                }

                group.wait()
                self.fetchSessions()

                let storageRef = Storage.storage().reference().child("pbtImports/\(self.userId)/\(UUID().uuidString).csv")
                storageRef.putData(data, metadata: nil) { _, _ in }

                // Remove duplicates after import
                self.removeDuplicateSessions { duplicateResult in
                    switch duplicateResult {
                    case .success(let duplicatesRemoved):
                        print("✅ PBT import: Removed \(duplicatesRemoved) duplicate sessions")
                    case .failure(let error):
                        print("⚠️ PBT import: Failed to remove duplicates - \(error.localizedDescription)")
                    }
                }

                DispatchQueue.main.async {
                    completion(.success(imported))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Regroup Import
    /// Imports sessions from Regroup export format.
    /// Flexible import that looks for core columns: date, buyin, cashout, location, hours, format
    func importSessionsFromRegroupCSV(fileURL: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let needsSecurity = fileURL.startAccessingSecurityScopedResource()
            defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: fileURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file as UTF-8"])) )
                    }
                    return
                }

                let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                
                print("📊 Regroup Import: Found \(lines.count) lines in CSV")
                
                guard lines.count > 1 else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -2, userInfo: [NSLocalizedDescriptionKey: "CSV appears to have no data rows"])) )
                    }
                    return
                }

                // Simple CSV parsing
                func parseCSVLine(_ line: String) -> [String] {
                    return line.split(separator: ",", omittingEmptySubsequences: false).map { 
                        String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                let headerRow = parseCSVLine(lines[0])
                let headers = headerRow.map { $0.lowercased() }
                
                print("📊 Regroup Import: Headers found: \(headers)")
                
                // Find the columns we care about (flexible matching)
                func findColumn(_ names: [String]) -> Int? {
                    for name in names {
                        if let index = headers.firstIndex(where: { $0.contains(name.lowercased()) }) {
                            return index
                        }
                    }
                    return nil
                }

                // Look for these core columns - only date and location are truly required
                guard let dateIdx = findColumn(["date"]) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "CSV", code: -3, userInfo: [NSLocalizedDescriptionKey: "CSV missing date column. Found: \(headers)"])) )
                    }
                    return
                }

                // Optional but important columns
                let buyinIdx = findColumn(["buyin", "buy"])
                let cashoutIdx = findColumn(["cashout", "cash"])
                let locationIdx = findColumn(["location", "venue"])
                let hoursIdx = findColumn(["hours", "time"])
                let formatIdx = findColumn(["format", "type"])
                let expensesIdx = findColumn(["expenses", "expense"])

                // Multiple date formatters to handle different formats
                let formatters: [DateFormatter] = {
                    let iso8601WithFraction = DateFormatter()
                    iso8601WithFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                    iso8601WithFraction.locale = Locale(identifier: "en_US_POSIX")
                    iso8601WithFraction.timeZone = TimeZone(secondsFromGMT: 0)
                    
                    let iso8601NoFraction = DateFormatter()
                    iso8601NoFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                    iso8601NoFraction.locale = Locale(identifier: "en_US_POSIX")
                    iso8601NoFraction.timeZone = TimeZone(secondsFromGMT: 0)
                    
                    let iso8601WithFractionNoZ = DateFormatter()
                    iso8601WithFractionNoZ.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                    iso8601WithFractionNoZ.locale = Locale(identifier: "en_US_POSIX")
                    iso8601WithFractionNoZ.timeZone = TimeZone(secondsFromGMT: 0)
                    
                    let simple = DateFormatter()
                    simple.dateFormat = "yyyy-MM-dd"
                    simple.locale = Locale(identifier: "en_US_POSIX")
                    
                    return [iso8601WithFraction, iso8601NoFraction, iso8601WithFractionNoZ, simple]
                }()

                // Helper to parse dollar values (already in dollars, not cents)
                func parseDollars(_ str: String) -> Double? {
                    guard !str.isEmpty, let dollars = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
                    return dollars
                }

                // Helper to safely get column value
                func safeCol(_ index: Int?, from cols: [String]) -> String {
                    guard let idx = index, idx < cols.count else { return "" }
                    return cols[idx]
                }

                var imported = 0
                let group = DispatchGroup()

                print("📊 Regroup Import: Processing \(lines.count - 1) data rows")

                for (index, line) in lines.dropFirst().enumerated() {
                    let cols = parseCSVLine(line)
                    
                    // Only skip if we don't have the date column
                    guard cols.count > dateIdx else {
                        print("⚠️ Row \(index + 1): Skipping - no date column")
                        continue
                    }
                    
                    // Parse date with multiple formatters
                    let dateString = cols[dateIdx]
                    var sessionDate: Date?
                    
                    for formatter in formatters {
                        if let date = formatter.date(from: dateString) {
                            sessionDate = date
                            break
                        }
                    }
                    
                    guard let date = sessionDate else {
                        print("⚠️ Row \(index + 1): Skipping - bad date format: '\(dateString)'")
                        continue
                    }

                    // Get values with safe defaults
                    let buyIn = buyinIdx != nil ? (parseDollars(safeCol(buyinIdx, from: cols)) ?? 0) : 0
                    let cashOut = cashoutIdx != nil ? (parseDollars(safeCol(cashoutIdx, from: cols)) ?? 0) : 0
                    let location = locationIdx != nil ? safeCol(locationIdx, from: cols) : "Unknown"
                    let hoursPlayed = hoursIdx != nil ? (Double(safeCol(hoursIdx, from: cols)) ?? 0) : 0
                    let expenses = expensesIdx != nil ? (parseDollars(safeCol(expensesIdx, from: cols)) ?? 0) : 0
                    
                    // Determine game type from format/type column
                    let format = formatIdx != nil ? safeCol(formatIdx, from: cols).uppercased() : ""
                    let isTournament = format.contains("TOURNAMENT") || format.contains("MTT") || format == "TOURNAMENT"
                    let gameType = isTournament ? SessionLogType.tournament.rawValue : SessionLogType.cashGame.rawValue
                    
                    let profit = cashOut - buyIn - expenses
                    let endTime = date.addingTimeInterval(hoursPlayed * 3600)
                    
                    // Create stakes string
                    let stakes = isTournament ? (buyIn > 0 ? "$\(Int(buyIn)) Tournament" : "Tournament") : ""

                    let sessionData: [String: Any] = [
                        "userId": self.userId,
                        "gameType": gameType,
                        "gameName": location,
                        "stakes": stakes,
                        "startDate": Timestamp(date: date),
                        "startTime": Timestamp(date: date),
                        "endTime": Timestamp(date: endTime),
                        "hoursPlayed": hoursPlayed,
                        "buyIn": buyIn + expenses,
                        "cashout": cashOut,
                        "profit": profit,
                        "createdAt": FieldValue.serverTimestamp(),
                        "location": location
                    ]

                    print("📊 Row \(index + 1): \(isTournament ? "Tournament" : "Cash") at \(location) - $\(buyIn) → $\(cashOut) = $\(profit)")

                    group.enter()
                    self.addSession(sessionData) { error in
                        if error == nil {
                            imported += 1
                        } else {
                            print("❌ Row \(index + 1): Failed - \(error?.localizedDescription ?? "Unknown")")
                        }
                        group.leave()
                    }
                }

                group.wait()
                
                print("📊 Regroup Import: Complete! Successfully imported \(imported) sessions.")
                
                self.fetchSessions()

                // Archive the file
                let storageRef = Storage.storage().reference().child("regroupImports/\(self.userId)/\(UUID().uuidString).csv")
                storageRef.putData(data, metadata: nil) { _, _ in }

                DispatchQueue.main.async {
                    completion(.success(imported))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    deinit {
        stopLiveSessionTimer()
    }
} 
