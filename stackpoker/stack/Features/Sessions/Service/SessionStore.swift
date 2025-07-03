import Foundation
import FirebaseFirestore
import SwiftUI
import FirebaseStorage
import FirebaseAuth

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
    let adjustedProfit: Double? // NEW: Staking-adjusted profit, nil if not calculated yet
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
        self.adjustedProfit = data["adjustedProfit"] as? Double // NEW: Read adjusted profit from Firestore
        
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
               lhs.adjustedProfit == rhs.adjustedProfit && // NEW: Include in equality check
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
    
    // Helper property to get the effective profit for analytics
    var effectiveProfit: Double {
        return adjustedProfit ?? profit
    }
}

// Model to track active live session

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession = LiveSessionData()
    @Published var showLiveSessionBar = false
    @Published var isLoadingSessions = false
    
    // NEW: Storage for parked sessions (day-two paused sessions)
    @Published var parkedSessions: [String: LiveSessionData] = [:]
    
    // Computed property to get the most recent session
    var mostRecentSession: Session? {
        return sessions.first // sessions is already sorted by date descending
    }
    
    // Enhanced live session data
    @Published var enhancedLiveSession = LiveSessionData_Enhanced(basicSession: LiveSessionData())
    
    private let db = Firestore.firestore()
    private let userId: String
    private var timer: Timer?
    private var listener: ListenerRegistration?
    
    // Caching properties
    private var sessionsCache: [Session] = []
    private var lastFetchTime: Date?
    private let cacheExpirationInterval: TimeInterval = 5 * 60 // 5 minutes
    private var hasFetchedSessions = false
    
    // Challenge service for updating challenges when sessions are completed
    private var challengeService: ChallengeService?
    
    // NEW: StakeService for calculating adjusted profits
    private let stakeService = StakeService()
    
    // Maximum length (in seconds) that a live session is allowed to run (120 hours).
    private let maximumSessionDuration: TimeInterval = 120 * 60 * 60
    
    init(userId: String, bankrollStore: BankrollStore? = nil) {
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
            self.challengeService = ChallengeService(userId: userId, bankrollStore: bankrollStore)
        }
        
        // Set up stake service callback for adjusted profit recalculation
        stakeService.onStakeUpdated = { [weak self] sessionId in
            Task {
                await self?.recalculateAdjustedProfitForStakeUpdate(sessionId: sessionId)
            }
        }
        
        // Load any existing session state
        loadLiveSessionState()
        
        // Load any existing parked sessions from both local storage and Firestore
        loadParkedSessionsState()
        Task {
            await loadParkedSessionsFromFirestore()
        }
        
        // Sanitize any corrupted data that might have been loaded
        sanitizeAllSessionData()
        
        // DON'T fetch historical sessions automatically - wait for explicit request
        // fetchSessions() // REMOVED - now called only when sessions tab is opened
        
        // REMOVED: Automatic state validation on initialization
        // This was causing performance issues - validation now only runs on explicit request
        // Use validateSessionStateOnLaunch() method for launch-time validation if needed
        
        print("🔄 SESSION STORE: Initialization complete - isActive: \(liveSession.isActive), showBar: \(showLiveSessionBar)")
    }
    
    // NEW: Handle stake updates by recalculating adjusted profit
    private func recalculateAdjustedProfitForStakeUpdate(sessionId: String) async {
        do {
            try await calculateAndUpdateAdjustedProfit(for: sessionId)
            print("✅ Recalculated adjusted profit for session \(sessionId) due to stake update")
        } catch {
            print("❌ Failed to recalculate adjusted profit for session \(sessionId): \(error)")
        }
    }
    
    // MARK: - Caching Methods
    
    /// Fetches sessions with caching - only loads from Firestore if cache is expired or empty
    func fetchSessionsWithCaching(forceRefresh: Bool = false) {
        print("📱 SESSION STORE: fetchSessionsWithCaching called (forceRefresh: \(forceRefresh))")
        
        // If we have cached data and it's not expired (unless forced), use cache
        if !forceRefresh,
           !sessionsCache.isEmpty,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheExpirationInterval {
            print("📱 SESSION STORE: Using cached sessions (\(sessionsCache.count) sessions)")
            DispatchQueue.main.async {
                self.sessions = self.sessionsCache
                self.isLoadingSessions = false
            }
            return
        }
        
        // Otherwise, fetch from Firestore
        print("📱 SESSION STORE: Fetching sessions from Firestore...")
        DispatchQueue.main.async {
            self.isLoadingSessions = true
        }
        
        // Remove old listener if exists
        listener?.remove()
        
        listener = db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .order(by: "startDate", descending: true)
            .order(by: "startTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoadingSessions = false
                }
                
                if let error = error {
                    print("❌ SESSION STORE: Error fetching sessions: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("📱 SESSION STORE: No sessions found")
                    return
                }
                
                let newSessions = documents.map { document in
                    Session(id: document.documentID, data: document.data())
                }
                
                DispatchQueue.main.async {
                    self?.sessions = newSessions
                    self?.sessionsCache = newSessions
                    self?.lastFetchTime = Date()
                    self?.hasFetchedSessions = true
                    print("📱 SESSION STORE: Loaded \(newSessions.count) sessions")
                }
            }
    }
    
    /// Call this method when the sessions tab is opened
    func loadSessionsForUI() {
        if !hasFetchedSessions {
            print("📱 SESSION STORE: First time loading sessions for UI")
            fetchSessionsWithCaching(forceRefresh: false)
        } else {
            print("📱 SESSION STORE: Sessions already loaded")
        }
    }
    
    /// Legacy method for backward compatibility
    func fetchSessions() {
        fetchSessionsWithCaching(forceRefresh: false)
    }
    
    /// Force refresh sessions (for after adding/updating/deleting)
    func refreshSessions() {
        fetchSessionsWithCaching(forceRefresh: true)
    }
    
    // Method to set challenge service (for dependency injection if needed)
    func setChallengeService(_ service: ChallengeService) {
        self.challengeService = service
    }
    
    // Method to update challenge service with bankrollStore
    func updateChallengeServiceWithBankrollStore(_ bankrollStore: BankrollStore) {
        Task { @MainActor in
            self.challengeService?.setBankrollStore(bankrollStore)
        }
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
    
    func addSession(_ sessionData: [String: Any], completion: @escaping (Error?) -> Void) {
        let docRef = db.collection("sessions").document() // create reference first to use inside closure safely
        
        // Calculate adjusted profit for new session
        var sessionDataWithAdjustedProfit = sessionData
        let rawProfit = sessionData["profit"] as? Double ?? 0.0
        
        // For new sessions, adjusted profit initially equals raw profit (no stakes yet)
        sessionDataWithAdjustedProfit["adjustedProfit"] = rawProfit
        
        docRef.setData(sessionDataWithAdjustedProfit) { error in
            if let err = error {
                completion(err)
                return
            }
            // Build a Session object with the saved data and new document ID
            var mergedData = sessionDataWithAdjustedProfit
            mergedData["id"] = docRef.documentID // convenience
            let session = Session(id: docRef.documentID, data: mergedData)
            
            // Update challenges asynchronously
            Task {
                await self.challengeService?.updateChallengesFromCompletedSession(session)
                
                // If there are any stakes for this session, recalculate adjusted profit
                // This handles the case where stakes were created before the session was logged
                do {
                    let stakes = try await self.stakeService.fetchStakesForSession(docRef.documentID)
                    if !stakes.isEmpty {
                        try await self.calculateAndUpdateAdjustedProfit(for: docRef.documentID)
                    }
                } catch {
                    print("⚠️ Failed to check/update adjusted profit for new session: \(error)")
                }
            }
            DispatchQueue.main.async {
                completion(nil)
            }
        }
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
                self.refreshSessions() 
                completion(nil)
            }
        }
    }
    
    // NEW: Calculate and update adjusted profit for a specific session
    func calculateAndUpdateAdjustedProfit(for sessionId: String) async throws {
        // Fetch stakes for this session
        let stakes = try await stakeService.fetchStakesForSession(sessionId)
        let stakesWhereUserWasStaked = stakes.filter { $0.stakedPlayerUserId == userId }
        
        // Get the current session
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            throw NSError(domain: "SessionStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        
        let adjustedProfit: Double
        if stakesWhereUserWasStaked.isEmpty {
            // No staking, adjusted profit equals raw profit
            adjustedProfit = session.profit
        } else {
            // Calculate staking-adjusted profit
            let totalAmountTransferred = stakesWhereUserWasStaked.reduce(0) { $0 + $1.amountTransferredAtSettlement }
            adjustedProfit = session.profit - totalAmountTransferred
        }
        
        // Update in Firestore
        try await db.collection("sessions").document(sessionId).updateData([
            "adjustedProfit": adjustedProfit
        ])
        
        // Update local session
        await MainActor.run {
            if let index = self.sessions.firstIndex(where: { $0.id == sessionId }) {
                var updatedSessionData = [
                    "userId": session.userId,
                    "gameType": session.gameType,
                    "gameName": session.gameName,
                    "stakes": session.stakes,
                    "startDate": Timestamp(date: session.startDate),
                    "startTime": Timestamp(date: session.startTime),
                    "endTime": Timestamp(date: session.endTime),
                    "hoursPlayed": session.hoursPlayed,
                    "buyIn": session.buyIn,
                    "cashout": session.cashout,
                    "profit": session.profit,
                    "adjustedProfit": adjustedProfit,
                    "createdAt": Timestamp(date: session.createdAt)
                ] as [String: Any]
                
                // Include optional fields
                if let notes = session.notes { updatedSessionData["notes"] = notes }
                if let liveSessionUUID = session.liveSessionUUID { updatedSessionData["liveSessionUUID"] = liveSessionUUID }
                if let location = session.location { updatedSessionData["location"] = location }
                if let tournamentType = session.tournamentType { updatedSessionData["tournamentType"] = tournamentType }
                if let series = session.series { updatedSessionData["series"] = series }
                if let pokerVariant = session.pokerVariant { updatedSessionData["pokerVariant"] = pokerVariant }
                if let tournamentGameType = session.tournamentGameType { updatedSessionData["tournamentGameType"] = tournamentGameType }
                if let tournamentFormat = session.tournamentFormat { updatedSessionData["tournamentFormat"] = tournamentFormat }
                
                let updatedSession = Session(id: sessionId, data: updatedSessionData)
                self.sessions[index] = updatedSession
            }
        }
        
        print("✅ Updated adjusted profit for session \(sessionId): \(adjustedProfit)")
    }
    

    
    // NEW: Calculate and update adjusted profits for sessions that have stakes
    func ensureAllSessionsHaveAdjustedProfits() async {
        do {
            // Query all stakes where current user is the staked player
            let allUserStakes = try await stakeService.fetchStakesForUser(userId: userId, asStakedPlayer: true)
            
            // Get unique session IDs that have stakes
            let sessionIdsWithStakes = Set(allUserStakes.map { $0.sessionId })
            
            if !sessionIdsWithStakes.isEmpty {
                print("🔄 Found \(sessionIdsWithStakes.count) sessions with stakes, recalculating adjusted profits...")
                
                for sessionId in sessionIdsWithStakes {
                    do {
                        try await calculateAndUpdateAdjustedProfit(for: sessionId)
                    } catch {
                        print("❌ Failed to calculate adjusted profit for session \(sessionId): \(error)")
                    }
                }
                
                // Refresh sessions to get updated data
                refreshSessions()
                print("✅ Completed recalculating adjusted profits for sessions with stakes")
            } else {
                print("ℹ️ No sessions with stakes found, no adjustments needed")
            }
        } catch {
            print("❌ Failed to fetch stakes for adjusted profit calculation: \(error)")
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
                self.refreshSessions()
                completion(.success(deletedCount))
            }
        }
    }
    
    // MARK: - Live Session Management
    
    func startLiveSession(gameName: String, stakes: String, buyIn: Double, isTournament: Bool = false, tournamentDetails: (name: String, type: String, baseBuyIn: Double)? = nil, pokerVariant: String? = nil, tournamentGameType: TournamentGameType? = nil, tournamentFormat: TournamentFormat? = nil, casino: String? = nil) {
        stopLiveSessionTimer() // Ensure any existing timer is stopped
        
        // Create the new session data first
        let newSessionStartTime = Date()
        let newSession = LiveSessionData(
            isActive: true,
            startTime: newSessionStartTime,
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
        
        // REMOVED: Duplicate prevention checking - removed per user request
        
        liveSession = newSession
        
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
    
    // MARK: - Multi-Day Session Management
    
    func pauseForNextDay(nextDayDate: Date) {
        print("[SessionStore] Pausing session for next day: \(nextDayDate)")
        
        var session = liveSession
        session.isActive = false
        session.pausedForNextDay = true
        session.pausedForNextDayDate = nextDayDate
        session.lastPausedAt = Date()
        if let lastActive = session.lastActiveAt {
            session.elapsedTime += Date().timeIntervalSince(lastActive)
        }
        session.lastActiveAt = nil
        
        liveSession = session
        stopLiveSessionTimer()
        saveLiveSessionState()
        showLiveSessionBar = false // Hide the live session bar when paused for next day
        
        print("[SessionStore] Session paused for Day \(liveSession.currentDay + 1)")
    }
    
    func resumeFromNextDay() {
        print("[SessionStore] Resuming from next day - currentDay: \(liveSession.currentDay) -> \(liveSession.currentDay + 1)")
        
        var session = liveSession
        session.isActive = true
        session.pausedForNextDay = false
        session.pausedForNextDayDate = nil
        session.currentDay += 1
        session.lastActiveAt = Date()
        
        liveSession = session
        startLiveSessionTimer()
        saveLiveSessionState()
        showLiveSessionBar = true // Show the live session bar when resumed
        
        print("[SessionStore] Session resumed to Day \(liveSession.currentDay)")
    }
    
    // MARK: - Enhanced Multi-Day Session Management (Parked Sessions)
    
    /// Parks the current live session for day 2 and clears the active session slot
    func parkSessionForNextDay(nextDayDate: Date) {
        print("[SessionStore] Parking session for next day: \(nextDayDate)")
        
        var sessionToPark = liveSession
        sessionToPark.isActive = false
        sessionToPark.pausedForNextDay = true
        sessionToPark.pausedForNextDayDate = nextDayDate
        sessionToPark.lastPausedAt = Date()
        if let lastActive = sessionToPark.lastActiveAt {
            sessionToPark.elapsedTime += Date().timeIntervalSince(lastActive)
        }
        sessionToPark.lastActiveAt = nil
        
        // Create a unique key for the parked session
        let parkedSessionKey = "\(sessionToPark.id)_day\(sessionToPark.currentDay + 1)"
        
        // Park the session both locally and in Firestore
        parkedSessions[parkedSessionKey] = sessionToPark
        
        // Save to Firestore for better persistence
        Task {
            await saveParkedSessionToFirestore(key: parkedSessionKey, session: sessionToPark)
        }
        
        // Clear the live session to allow new sessions
        liveSession = LiveSessionData()
        enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        
        // Stop timer and save state
        stopLiveSessionTimer()
        saveParkedSessionsState() // Keep local backup
        saveLiveSessionState() // This will save the cleared session
        
        // Don't hide the bar - allow new sessions to be started
        showLiveSessionBar = false // Will be shown again when a new session starts
        
        print("[SessionStore] Session parked as '\(parkedSessionKey)' for Day \(sessionToPark.currentDay + 1)")
    }
    
    /// Restores a parked session back to active state
    func restoreParkedSession(key: String) {
        print("🅿️ [PARKED SESSION] Attempting to restore parked session with key: \(key)")

        guard let parkedSession = parkedSessions[key] else {
            print("❌ [PARKED SESSION] No parked session found for key: \(key). Aborting restore.")
            return
        }
        
        print("🅿️ [PARKED SESSION] Found parked session to restore: \(parkedSession.gameName) for Day \(parkedSession.currentDay + 1)")
        
        // If there's currently an active session, we need to handle this conflict
        if liveSession.buyIn > 0 && !liveSession.isEnded {
            print("⚠️ [PARKED SESSION] CONFLICT: Attempting to restore a session while another is active.")
            print("   - Current active session: \(liveSession.gameName) with buy-in: \(liveSession.buyIn)")
            print("   - This operation will be blocked to prevent data loss.")
            // For now, we'll prevent this. In the future, we could queue or ask user to choose
            return
        }
        
        print("🅿️ [PARKED SESSION] No active session conflict. Proceeding with restore.")

        // REMOVED: Duplicate checking for parked sessions - removed per user request

        var restoredSession = parkedSession
        restoredSession.isActive = true
        restoredSession.pausedForNextDay = false
        restoredSession.pausedForNextDayDate = nil
        restoredSession.currentDay += 1
        restoredSession.lastActiveAt = Date()
        
        // Remove from parked sessions
        parkedSessions.removeValue(forKey: key)
        print("🅿️ [PARKED SESSION] Removed session from the parkedSessions dictionary.")
        
        // Remove from Firestore as well
        Task {
            await removeParkedSessionFromFirestore(key: key)
        }
        
        // Set as live session
        liveSession = restoredSession
        print("🅿️ [PARKED SESSION] Set the restored session as the current live session.")
        
        // Try to restore enhanced session data if it exists
        // Note: Enhanced data might not be available for older parked sessions
        let enhancedKey = "EnhancedLiveSession_\(userId)_\(restoredSession.id)"
        if let savedData = UserDefaults.standard.data(forKey: enhancedKey),
           let loadedEnhancedSession = try? JSONDecoder().decode(LiveSessionData_Enhanced.self, from: savedData) {
            enhancedLiveSession = loadedEnhancedSession
            print("🅿️ [PARKED SESSION] Successfully restored enhanced session data for parked session.")
        } else {
            // Initialize with basic session if no enhanced data available
            enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
            print("🅿️ [PARKED SESSION] No enhanced data found. Initialized a new enhanced session from basic data.")
        }
        
        // Start timer and update display
        startLiveSessionTimer()
        saveParkedSessionsState() // Save the state now that one session has been removed
        saveLiveSessionState()
        showLiveSessionBar = true
        
        print("✅ [PARKED SESSION] Session for Day \(liveSession.currentDay) successfully restored and is now active.")
    }
    
    /// Gets all parked sessions with user-friendly display info
    func getParkedSessionsInfo() -> [(key: String, displayName: String, nextDayDate: Date)] {
        return parkedSessions.compactMap { (key, session) in
            guard let nextDayDate = session.pausedForNextDayDate else { return nil }
            
            let displayName: String
            if session.isTournament {
                displayName = "\(session.tournamentName ?? session.gameName) - Day \(session.currentDay + 1)"
            } else {
                displayName = "\(session.stakes) @ \(session.gameName) - Day \(session.currentDay + 1)"
            }
            
            return (key: key, displayName: displayName, nextDayDate: nextDayDate)
        }.sorted { $0.nextDayDate < $1.nextDayDate }
    }
    
    /// Removes a parked session permanently (when user decides not to continue)
    func discardParkedSession(key: String) {
        parkedSessions.removeValue(forKey: key)
        saveParkedSessionsState()
        
        // Also remove from Firestore
        Task {
            await removeParkedSessionFromFirestore(key: key)
        }
        
        print("[SessionStore] Discarded parked session: \(key)")
    }
    
    // Create a "Resume Day X" event
    func createResumeEvent(for nextDayDate: Date) async -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            print("Cannot create resume event: No authenticated user")
            return false
        }
        
        do {
            // Get user's display name
            let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
            let userData = userDoc.data()
            let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
            
            // Create the resume event
            let eventRef = db.collection("userEvents").document()
            let eventId = eventRef.documentID
            
            let title = "Continue Day \(liveSession.currentDay + 1)"
            let originalSessionTitle = liveSession.isTournament ? 
                (liveSession.tournamentName ?? liveSession.gameName) : 
                "\(liveSession.stakes) @ \(liveSession.gameName)"
            
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let subtitle = "\(originalSessionTitle) • \(formatter.string(from: nextDayDate))"
            
            let resumeEvent = [
                "id": eventId,
                "title": title,
                "description": subtitle,
                "eventType": "resumeSession",
                "creatorId": currentUser.uid,
                "creatorName": displayName,
                "startDate": Timestamp(date: nextDayDate),
                "endDate": nil as Timestamp?,
                "timezone": TimeZone.current.identifier,
                "location": nil as String?,
                "maxParticipants": nil as Int?,
                "currentParticipants": 1,
                "waitlistEnabled": false,
                "status": "upcoming",
                "groupId": nil as String?,
                "isPublic": false,
                "isBanked": false,
                "rsvpDeadline": nil as Timestamp?,
                "reminderSettings": [
                    "enabled": false,
                    "reminderTimes": [] as [Int]
                ],
                "linkedGameId": nil as String?,
                "imageURL": nil as String?,
                "associatedLiveSessionId": liveSession.id,
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ] as [String : Any]
            
            try await eventRef.setData(resumeEvent)
            
            // Auto-RSVP creator as GOING
            let rsvpId = "\(eventId)_\(currentUser.uid)"
            let rsvpData = [
                "eventId": eventId,
                "userId": currentUser.uid,
                "userDisplayName": displayName,
                "status": "going",
                "rsvpDate": Timestamp(date: Date()),
                "notes": nil as String?,
                "waitlistPosition": nil as Int?
            ] as [String : Any]
            
            try await db.collection("eventRSVPs").document(rsvpId).setData(rsvpData)
            
            print("✅ Created resume event: \(title)")
            return true
        } catch {
            print("❌ Failed to create resume event: \(error)")
            return false
        }
    }
    
    // Remove resume event (when resuming or ending session)
    func removeResumeEvent() async {
        guard !liveSession.id.isEmpty else { return }
        
        do {
            // Find the resume event for this session
            let eventQuery = try await db.collection("userEvents")
                .whereField("associatedLiveSessionId", isEqualTo: liveSession.id)
                .whereField("eventType", isEqualTo: "resumeSession")
                .getDocuments()
            
            for eventDoc in eventQuery.documents {
                let eventId = eventDoc.documentID
                
                // Delete the event
                try await db.collection("userEvents").document(eventId).delete()
                
                // Delete any RSVPs for this event
                let rsvpQuery = try await db.collection("eventRSVPs")
                    .whereField("eventId", isEqualTo: eventId)
                    .getDocuments()
                
                for rsvpDoc in rsvpQuery.documents {
                    try await rsvpDoc.reference.delete()
                }
                
                print("✅ Removed resume event: \(eventId)")
            }
        } catch {
            print("❌ Failed to remove resume event: \(error)")
        }
    }
    
    // Modify endLiveSessionAsync to return the new session ID or nil
    func endLiveSessionAndGetId(cashout: Double) async -> String? {
        stopLiveSessionTimer()
        
        let currentLiveSessionId = liveSession.id

        let rawProfit = cashout - liveSession.buyIn
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
            "profit": rawProfit, // liveSession.buyIn is total for both types
            "adjustedProfit": rawProfit, // Initially equals raw profit, will be recalculated if stakes exist
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
            
            // Check if there are stakes for this live session and recalculate adjusted profit
            do {
                // Check for stakes using both the new session ID and the live session ID
                var stakes = try await stakeService.fetchStakesForSession(docRef.documentID)
                if stakes.isEmpty {
                    stakes = try await stakeService.fetchStakesForLiveSession(currentLiveSessionId)
                }
                
                if !stakes.isEmpty {
                    print("🔄 Found \(stakes.count) stakes for session, recalculating adjusted profit...")
                    try await calculateAndUpdateAdjustedProfit(for: docRef.documentID)
                }
            } catch {
                print("⚠️ Failed to check/update adjusted profit for live session: \(error)")
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
        
        // Clean up any resume events before ending the session
        Task {
            await removeResumeEvent()
        }
        
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
        parkedSessions = [:] // Clear parked sessions
        showLiveSessionBar = false
        
        // Clear ALL possible UserDefaults keys (current and legacy)
        let possibleKeys = [
            "LiveSession_\(userId)",
            "EnhancedLiveSession_\(userId)",
            "ParkedSessions_\(userId)", // Add parked sessions key
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
    
    // SCORCHED EARTH: Enhanced session validation (synchronous - for basic checks only)
    func validateSessionState() -> Bool {
        // Check if session should exist but doesn't make sense
        if liveSession.buyIn > 0 && liveSession.isEnded {
            print("⚠️ VALIDATION: Found ended session with buy-in - clearing")
            scorachedEarthSessionClear()
            return false
        }
        
        // Check for impossible states (but allow sessions paused for next day)
        if liveSession.isActive && liveSession.buyIn == 0 && !liveSession.pausedForNextDay {
            print("⚠️ VALIDATION: Found active session with no buy-in - clearing")
            scorachedEarthSessionClear()
            return false
        }
        
        // Check for stale sessions that have exceeded the maximum allowed duration
        // But don't clear sessions that are paused for next day
        let maxDurationAgo = Date().addingTimeInterval(-maximumSessionDuration)
        if liveSession.startTime < maxDurationAgo && !liveSession.isEnded && !liveSession.pausedForNextDay {
            print("⚠️ VALIDATION: Found stale session - clearing")
            scorachedEarthSessionClear()
            return false
        }
        
        return true
    }
    
    // NEW: Basic session validation for app launch
    func validateSessionStateOnLaunch() async {
        print("🚀 LAUNCH VALIDATION: Starting basic session validation...")
        
        // Run basic synchronous validation
        if validateSessionState() {
            print("🚀 LAUNCH VALIDATION: Session validation complete")
        } else {
            print("🚀 LAUNCH VALIDATION: Basic validation failed, session cleared")
        }
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
            
            // Sanitize chip updates to remove any corrupted data
            var sanitizedSession = loadedSession
            let originalCount = sanitizedSession.chipUpdates.count
            
            // Filter out any invalid chip updates
            sanitizedSession.chipUpdates = sanitizedSession.chipUpdates.filter { update in
                let isValid = !update.amount.isNaN && !update.amount.isInfinite && update.amount >= 0
                if !isValid {
                    print("🧹 SANITIZING: Removing invalid chip update: \(update.amount)")
                }
                return isValid
            }
            
            let sanitizedCount = sanitizedSession.chipUpdates.count
            enhancedLiveSession = sanitizedSession
            
            if originalCount != sanitizedCount {
                print("🧹 SANITIZING: Removed \(originalCount - sanitizedCount) corrupted chip updates")
                // Save the sanitized data back to UserDefaults
                saveEnhancedLiveSessionState()
            }
        } else {
            // If no enhanced data, initialize with current basic session
            enhancedLiveSession = LiveSessionData_Enhanced(basicSession: liveSession)
        }
    }
    
    private func removeEnhancedLiveSessionState() {
        UserDefaults.standard.removeObject(forKey: "EnhancedLiveSession_\(userId)")
    }
    
    // MARK: - State Persistence for Parked Sessions (Database-backed)
    
    /// Save a parked session to Firestore for better persistence
    private func saveParkedSessionToFirestore(key: String, session: LiveSessionData) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let sessionData = try encoder.encode(session)
            let sessionDict = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any] ?? [:]
            
            let parkedSessionDoc = [
                "userId": userId,
                "sessionKey": key,
                "sessionData": sessionDict,
                "parkedAt": Timestamp(date: Date()),
                "nextDayDate": Timestamp(date: session.pausedForNextDayDate ?? Date())
            ] as [String: Any]
            
            try await db.collection("parkedSessions").document(key).setData(parkedSessionDoc)
            print("🅿️ [FIRESTORE] Successfully saved parked session to Firestore: \(key)")
        } catch {
            print("❌ [FIRESTORE] Failed to save parked session to Firestore: \(error)")
        }
    }
    
    /// Load all parked sessions from Firestore
    private func loadParkedSessionsFromFirestore() async {
        do {
            let snapshot = try await db.collection("parkedSessions")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            var firestoreParkedSessions: [String: LiveSessionData] = [:]
            
            for document in snapshot.documents {
                let data = document.data()
                guard let sessionKey = data["sessionKey"] as? String,
                      let sessionDataDict = data["sessionData"] as? [String: Any] else {
                    print("⚠️ [FIRESTORE] Invalid parked session data format for document: \(document.documentID)")
                    continue
                }
                
                do {
                    let sessionData = try JSONSerialization.data(withJSONObject: sessionDataDict)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let session = try decoder.decode(LiveSessionData.self, from: sessionData)
                    firestoreParkedSessions[sessionKey] = session
                    print("🅿️ [FIRESTORE] Loaded parked session: \(sessionKey)")
                } catch {
                    print("❌ [FIRESTORE] Failed to decode parked session \(sessionKey): \(error)")
                }
            }
            
            // Merge with local sessions, prioritizing Firestore data
            await MainActor.run {
                for (key, session) in firestoreParkedSessions {
                    parkedSessions[key] = session
                }
                print("🅿️ [FIRESTORE] Loaded \(firestoreParkedSessions.count) parked sessions from Firestore")
            }
            
        } catch {
            print("❌ [FIRESTORE] Failed to load parked sessions from Firestore: \(error)")
        }
    }
    
    /// Remove a parked session from Firestore
    private func removeParkedSessionFromFirestore(key: String) async {
        do {
            try await db.collection("parkedSessions").document(key).delete()
            print("🅿️ [FIRESTORE] Successfully removed parked session from Firestore: \(key)")
        } catch {
            print("❌ [FIRESTORE] Failed to remove parked session from Firestore: \(error)")
        }
    }
    
    // MARK: - State Persistence for Parked Sessions (UserDefaults backup)
    
    private func saveParkedSessionsState() {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(parkedSessions)
            UserDefaults.standard.set(encoded, forKey: "ParkedSessions_\(userId)")
            UserDefaults.standard.synchronize()
            print("🅿️ [PARKED SESSION] Saved \(parkedSessions.count) parked sessions to UserDefaults with key: ParkedSessions_\(userId)")
        } catch {
            print("❌ [PARKED SESSION] FAILED to save parked sessions state: \(error)")
        }
    }
    
    private func loadParkedSessionsState() {
        let key = "ParkedSessions_\(userId)"
        print("🅿️ [PARKED SESSION] Attempting to load parked sessions from UserDefaults with key: \(key)")
        if let savedData = UserDefaults.standard.data(forKey: key) {
             print("🅿️ [PARKED SESSION] Found data for key. Size: \(savedData.count) bytes.")
            do {
                let loadedParkedSessions = try JSONDecoder().decode([String: LiveSessionData].self, from: savedData)
                parkedSessions = loadedParkedSessions
                print("✅ [PARKED SESSION] Successfully decoded and loaded \(parkedSessions.count) parked sessions.")
                if !parkedSessions.isEmpty {
                    for (sessionKey, sessionData) in parkedSessions {
                        print("   - Key: \(sessionKey), Game: \(sessionData.gameName), Day: \(sessionData.currentDay + 1)")
                    }
                }
            } catch {
                print("❌ [PARKED SESSION] FAILED to decode parked sessions from data: \(error)")
                parkedSessions = [:]
            }
        } else {
            parkedSessions = [:]
            print("🅿️ [PARKED SESSION] No data found in UserDefaults for parked sessions.")
        }
    }
    
    private func removeParkedSessionsState() {
        UserDefaults.standard.removeObject(forKey: "ParkedSessions_\(userId)")
        parkedSessions = [:]
        print("[SessionStore] Parked sessions state cleared")
    }
    
    // MARK: - State Persistence
    
    func saveLiveSessionState() {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(liveSession)
            UserDefaults.standard.set(encoded, forKey: "LiveSession_\(userId)")
            UserDefaults.standard.synchronize()
            // print("[SessionStore] Live session state saved successfully") // Less verbose logging
        } catch {
            print("[SessionStore] Failed to save live session state: \(error)")
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

            // --- VALIDATION DISABLED FOR DEBUGGING ---
            // The aggressive validation logic that was here has been temporarily disabled.
            // This will allow us to inspect the state of parked sessions without the app
            // automatically clearing them on launch. The validation should be moved to the
            // restore function, triggered only by user action.
            print("⚠️ DEBUGGING: Automatic session validation on load is currently DISABLED.")

            let isPotentiallyRestorable = loadedSession.isActive || loadedSession.lastPausedAt != nil || loadedSession.pausedForNextDay
            let hasValidBuyIn = loadedSession.buyIn > 0

            // SCORCHED EARTH: Enhanced staleness check
            // let lastActivityTime = loadedSession.lastActiveAt ?? loadedSession.lastPausedAt ?? loadedSession.startTime
            // let timeSinceLastActivity = Date().timeIntervalSince(lastActivityTime)
            // let isAbandoned = timeSinceLastActivity > maximumSessionDuration // 120-hour abandonment window

            // SCORCHED EARTH: More aggressive validation
            // let isCorrupted = loadedSession.startTime > Date() || // Future start time
            //                  loadedSession.elapsedTime > maximumSessionDuration || // Exceeds maximum duration
            //                  (loadedSession.isActive && loadedSession.lastActiveAt == nil) // Active but no lastActiveAt

            // if isCorrupted {
            //     print("💥 LOADING: Detected corrupted session - clearing")
            //     scorachedEarthSessionClear()
            //     return
            // }

            // NEW CHECK: Look inside the persisted *enhanced* session for a final cashout entry.
            // if let enhancedData = UserDefaults.standard.data(forKey: "EnhancedLiveSession_\(userId)"),
            //    let enhancedSession = try? JSONDecoder().decode(LiveSessionData_Enhanced.self, from: enhancedData) {
            //     let hasFinalCashout = enhancedSession.chipUpdates.contains { update in
            //         update.note?.contains("Final cashout amount") == true
            //     }
            //     if hasFinalCashout {
            //         print("🗑️ LOADING: Found 'Final cashout amount' in enhanced session – treating as ended and clearing")
            //         scorachedEarthSessionClear()
            //         return
            //     }
            // }

            // REMOVED: Duplicate checking during automatic load (moved to explicit validation only)
            // This was causing performance issues and UI lag due to synchronous database calls
            // Duplicate checking is now only performed when explicitly requested
            
            print("🔍 LOADING: Session validation - hasValidBuyIn: \(hasValidBuyIn), isPotentiallyRestorable: \(isPotentiallyRestorable)")
            
            if hasValidBuyIn && isPotentiallyRestorable {
                print("✅ LOADING: Restoring valid session (without aggressive validation).")
                
                // TRANSITION PERIOD FIX: If this session is paused for next day, 
                // it should be moved to parked sessions instead of staying in live session
                if loadedSession.pausedForNextDay {
                    print("🔄 LOADING: Session is paused for next day - converting to parked session")
                    let parkedSessionKey = "\(loadedSession.id)_day\(loadedSession.currentDay + 1)"
                    parkedSessions[parkedSessionKey] = loadedSession
                    saveParkedSessionsState()
                    
                    // Clear the live session since it should be parked
                    self.liveSession = LiveSessionData()
                    self.enhancedLiveSession = LiveSessionData_Enhanced(basicSession: self.liveSession)
                    self.showLiveSessionBar = false
                    
                    print("✅ LOADING: Converted session to parked session: \(parkedSessionKey)")
                } else {
                    // Normal session restoration
                    var sessionToRestore = loadedSession
                    if sessionToRestore.isActive, let lastActive = sessionToRestore.lastActiveAt {
                        // If it was active, calculate time passed since last active and add to elapsed.
                        let additionalTime = Date().timeIntervalSince(lastActive)
                        sessionToRestore.elapsedTime += additionalTime
                        sessionToRestore.lastActiveAt = Date() // Update last active to now
                    }
                    
                    self.liveSession = sessionToRestore
                    
                    if self.liveSession.isActive {
                        startLiveSessionTimer()
                    }
                    self.showLiveSessionBar = true
                }
                loadEnhancedLiveSessionState() // Also load its associated enhanced data
                
            } else {
                print("🗑️ LOADING: Session doesn't meet basic restoration criteria - clearing")
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
    
    // MARK: - Data Sanitization
    
    /// Sanitizes all session data to remove corrupted values
    func sanitizeAllSessionData() {
        print("🧹 SANITIZING: Starting comprehensive data sanitization")
        
        // Sanitize current enhanced session
        let originalCount = enhancedLiveSession.chipUpdates.count
        enhancedLiveSession.chipUpdates = enhancedLiveSession.chipUpdates.filter { update in
            let isValid = !update.amount.isNaN && !update.amount.isInfinite && update.amount >= 0
            if !isValid {
                print("🧹 SANITIZING: Removing invalid chip update: \(update.amount)")
            }
            return isValid
        }
        
        if originalCount != enhancedLiveSession.chipUpdates.count {
            print("🧹 SANITIZING: Removed \(originalCount - enhancedLiveSession.chipUpdates.count) corrupted chip updates")
            saveEnhancedLiveSessionState()
        }
        
        // Sanitize basic session data
        if liveSession.buyIn.isNaN || liveSession.buyIn.isInfinite || liveSession.buyIn < 0 {
            print("🧹 SANITIZING: Fixing corrupted buy-in: \(liveSession.buyIn)")
            liveSession.buyIn = 0
            saveLiveSessionState()
        }
        
        print("🧹 SANITIZING: Data sanitization complete")
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
                self.refreshSessions()

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
                self.refreshSessions()

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
                        "adjustedProfit": netProfit, // Initially equals raw profit for imports
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
                self.refreshSessions()

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
                
                self.refreshSessions()

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
        listener?.remove()
    }
} 
