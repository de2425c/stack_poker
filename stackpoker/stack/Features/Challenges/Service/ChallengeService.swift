import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ChallengeService: ObservableObject {
    @Published var activeChallenges: [Challenge] = []
    @Published var completedChallenges: [Challenge] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // Add property to track newly completed challenges for celebration
    @Published var justCompletedChallenge: Challenge? = nil
    
    // Add property to track newly created challenges for sharing
    @Published var justCreatedChallenge: Challenge? = nil
    
    private let db = Firestore.firestore()
    private let userId: String
    private var bankrollStore: BankrollStore? // Use BankrollStore instead of userService
    
    init(userId: String, bankrollStore: BankrollStore? = nil) {
        self.userId = userId
        self.bankrollStore = bankrollStore
        loadUserChallenges()
    }
    
    // Method to set bankrollStore after initialization if needed
    func setBankrollStore(_ bankrollStore: BankrollStore) {
        self.bankrollStore = bankrollStore
    }
    
    // MARK: - Public Methods
    
    func createChallenge(_ challenge: Challenge) async throws {
        isLoading = true
        error = nil
        
        do {
            let docRef = try await db.collection("challenges").addDocument(data: challenge.dictionary)
            print("✅ Challenge created with ID: \(docRef.documentID)")
            
            // Also add to user's active challenges subcollection
            try await db.collection("users")
                .document(userId)
                .collection("activeChallenges")
                .document(docRef.documentID)
                .setData(["challengeId": docRef.documentID, "createdAt": Timestamp(date: Date())])
            
            // Reload challenges
            loadUserChallenges()
            
            // Set the just created challenge for a share prompt
            // Create a copy of the challenge with the new document ID
            var challengeWithId = challenge
            challengeWithId.id = docRef.documentID
            justCreatedChallenge = challengeWithId
            print("✅ Set justCreatedChallenge: \(challengeWithId.title) with ID: \(docRef.documentID)")
            
        } catch {
            self.error = "Failed to create challenge: \(error.localizedDescription)"
            print("❌ Error creating challenge: \(error)")
            throw error
        }
        
        isLoading = false
    }
    
    func updateChallengeProgress(challengeId: String, newValue: Double, triggerEvent: String, relatedEntityId: String? = nil) async throws {
        guard !challengeId.isEmpty else { return }
        
        do {
            // Find the challenge in our local array
            if let index = activeChallenges.firstIndex(where: { $0.id == challengeId }) {
                var challenge = activeChallenges[index]
                let oldValue = challenge.currentValue
                challenge.currentValue = newValue
                challenge.lastUpdated = Date()
                
                // Check if challenge is completed - more specific logic for different challenge types
                var shouldComplete = false
                
                switch challenge.type {
                case .bankroll:
                    // For bankroll challenges, check if current bankroll >= target bankroll
                    // But don't complete on app load unless there was actual progress
                    let hasActualProgress = triggerEvent != "bankroll_calculated" || abs(newValue - oldValue) > 0.01
                    let hasReachedTarget = newValue >= challenge.targetValue
                    
                    // Additional safeguard: don't complete if this is the initial value
                    let isInitialValue = challenge.startingBankroll != nil && abs(newValue - (challenge.startingBankroll ?? 0)) < 0.01
                    
                    shouldComplete = hasReachedTarget && 
                                   challenge.status == .active && 
                                   hasActualProgress &&
                                   !isInitialValue
                    
                    print("🎯 Bankroll Challenge Completion Check:")
                    print("   Current Value: $\(challenge.currentValue)")
                    print("   New Value: $\(newValue)")
                    print("   Target Value: $\(challenge.targetValue)")
                    print("   Starting Bankroll: $\(challenge.startingBankroll ?? 0)")
                    print("   Status: \(challenge.status)")
                    print("   Old Value: $\(oldValue)")
                    print("   Has Reached Target: \(hasReachedTarget)")
                    print("   Has Actual Progress: \(hasActualProgress)")
                    print("   Is Initial Value: \(isInitialValue)")
                    print("   Trigger Event: \(triggerEvent)")
                    print("   Should Complete: \(shouldComplete)")
                case .hands:
                    // For hands challenges, check if hand count >= target hand count
                    shouldComplete = challenge.currentValue >= challenge.targetValue && challenge.status == .active
                case .session:
                    // For session challenges, check if session count >= target session count
                    shouldComplete = challenge.currentValue >= challenge.targetValue && challenge.status == .active
                }
                
                if shouldComplete {
                    challenge.status = .completed
                    challenge.completedAt = Date()
                    
                    // For bankroll challenges, update currentValue with dynamic calculation
                    if challenge.type == .bankroll {
                        let dynamicBankroll = await calculateCurrentBankroll()
                        challenge.currentValue = dynamicBankroll
                        print("💰 Updated challenge currentValue with dynamic bankroll: $\(dynamicBankroll)")
                    }
                    
                    // Move from active to completed
                    try await moveToCompletedChallenges(challenge)
                    
                    // Set the just completed challenge for celebration
                    justCompletedChallenge = challenge
                    
                    // Create completion post
                    await createChallengeCompletionPost(for: challenge)
                    
                    print("🎉 Challenge completed! \(challenge.title) - \(challenge.currentValue) reached target \(challenge.targetValue)")
                    print("   Trigger event: \(triggerEvent)")
                    print("   Old value: \(oldValue)")
                } else {
                    // Update the challenge document
                    try await db.collection("challenges").document(challengeId).updateData([
                        "currentValue": newValue,
                        "lastUpdated": Timestamp(date: Date()),
                        "status": challenge.status.rawValue
                    ])
                    
                    // Update local state
                    activeChallenges[index] = challenge
                }
                
                // Log progress entry
                let progress = ChallengeProgress(
                    challengeId: challengeId,
                    userId: userId,
                    progressValue: newValue,
                    triggerEvent: triggerEvent,
                    relatedEntityId: relatedEntityId
                )
                
                try await db.collection("challengeProgress").addDocument(data: progress.dictionary)
                
                print("📈 Challenge progress updated: \(oldValue) -> \(newValue) (\(triggerEvent))")
            }
            
        } catch {
            self.error = "Failed to update challenge progress: \(error.localizedDescription)"
            print("❌ Error updating challenge progress: \(error)")
            throw error
        }
    }
    
    func abandonChallenge(challengeId: String) async throws {
        guard !challengeId.isEmpty else { return }
        
        do {
            // Update challenge status
            try await db.collection("challenges").document(challengeId).updateData([
                "status": ChallengeStatus.abandoned.rawValue,
                "lastUpdated": Timestamp(date: Date())
            ])
            
            // Remove from user's active challenges
            try await db.collection("users")
                .document(userId)
                .collection("activeChallenges")
                .document(challengeId)
                .delete()
            
            // Update local state
            if let index = activeChallenges.firstIndex(where: { $0.id == challengeId }) {
                activeChallenges.remove(at: index)
            }
            
            print("❌ Challenge abandoned: \(challengeId)")
            
        } catch {
            self.error = "Failed to abandon challenge: \(error.localizedDescription)"
            print("❌ Error abandoning challenge: \(error)")
            throw error
        }
    }
    
    func fetchPublicChallenges(for userId: String) async throws -> [Challenge] {
        do {
            let snapshot = try await db.collection("challenges")
                .whereField("userId", isEqualTo: userId)
                .whereField("isPublic", isEqualTo: true)
                .whereField("status", isEqualTo: ChallengeStatus.active.rawValue)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            return snapshot.documents.compactMap { Challenge(document: $0) }
            
        } catch {
            print("❌ Error fetching public challenges: \(error)")
            throw error
        }
    }
    
    // MARK: - Session Challenge Helper
    
    func updateSessionChallengesFromSession(_ session: Session) async {
        print("🎯 Updating session challenges from completed session")
        print("   Session ID: \(session.id)")
        print("   Session Date: \(session.startDate)")
        print("   Session Hours: \(session.hoursPlayed)")
        
        // Update all active session challenges
        for challenge in activeChallenges where challenge.type == .session {
            guard let challengeId = challenge.id else { continue }
            
            // Check if this session occurred after the challenge start date
            guard session.startDate >= challenge.startDate else {
                print("   ❌ Session \(session.id) predates challenge \(challenge.title) - skipping")
                continue
            }
            
            // Check if session meets minimum hour requirement (if any)
            let sessionQualifies = challenge.sessionQualifies(hoursPlayed: session.hoursPlayed)
            
            // Skip if this session was already counted
            if challenge.countedSessionIds.contains(session.id) {
                print("   ⚠️ Session already counted for challenge \(challenge.title) - skipping duplicate")
                continue
            }
            
            var updatedChallenge = challenge
            
            // Append session id to prevent double counting
            updatedChallenge.countedSessionIds.append(session.id)
            
            // Always increment total session count and hours
            updatedChallenge.currentSessionCount += 1
            updatedChallenge.totalHoursPlayed += session.hoursPlayed
            
            // Increment valid sessions count if it qualifies
            if sessionQualifies {
                updatedChallenge.validSessionsCount += 1
            }
            
            print("   📊 Challenge: \(challenge.title)")
            print("     Session hours: \(String(format: "%.1f", session.hoursPlayed))")
            print("     Min hours required: \(challenge.minHoursPerSession ?? 0)")
            print("     Session qualifies: \(sessionQualifies)")
            print("     Total sessions: \(updatedChallenge.currentSessionCount)")
            print("     Valid sessions: \(updatedChallenge.validSessionsCount)")
            print("     Total hours: \(String(format: "%.1f", updatedChallenge.totalHoursPlayed))")
            
            // CRITICAL: Update currentValue based on challenge configuration
            if let targetHours = updatedChallenge.targetHours {
                // Hours-based challenge: currentValue tracks total hours
                updatedChallenge.currentValue = updatedChallenge.totalHoursPlayed
                print("     Hours-based challenge - currentValue: \(updatedChallenge.currentValue)")
            } else if let targetCount = updatedChallenge.targetSessionCount {
                // Count-based challenge: currentValue tracks valid session count
                updatedChallenge.currentValue = Double(updatedChallenge.validSessionsCount)
                print("     Count-based challenge - currentValue: \(updatedChallenge.currentValue)")
            }
            
            // Update lastUpdated
            updatedChallenge.lastUpdated = Date()
            
            // Check if challenge is now completed
            let wasCompleted = challenge.isSessionChallengeCompleted
            let isNowCompleted = updatedChallenge.isSessionChallengeCompleted
            
            print("     Was completed: \(wasCompleted)")
            print("     Is now completed: \(isNowCompleted)")
            
            if !wasCompleted && isNowCompleted {
                updatedChallenge.status = .completed
                updatedChallenge.completedAt = Date()
                
                // Move from active to completed
                do {
                    try await moveToCompletedChallenges(updatedChallenge)
                    
                    // Set the just completed challenge for celebration
                    justCompletedChallenge = updatedChallenge
                    
                    // Create completion post
                    await createChallengeCompletionPost(for: updatedChallenge)
                    
                    print("🎉 Session Challenge completed! \(updatedChallenge.title)")
                } catch {
                    print("❌ Error completing session challenge: \(error)")
                }
            } else {
                // Update the challenge document with new progress
                do {
                    try await db.collection("challenges").document(challengeId).updateData([
                        "currentSessionCount": updatedChallenge.currentSessionCount,
                        "totalHoursPlayed": updatedChallenge.totalHoursPlayed,
                        "validSessionsCount": updatedChallenge.validSessionsCount,
                        "currentValue": updatedChallenge.currentValue,
                        "countedSessionIds": updatedChallenge.countedSessionIds,
                        "lastUpdated": Timestamp(date: updatedChallenge.lastUpdated),
                        "status": updatedChallenge.status.rawValue
                    ])
                    
                    // Update local state
                    if let index = activeChallenges.firstIndex(where: { $0.id == challengeId }) {
                        activeChallenges[index] = updatedChallenge
                    }
                    
                    print("✅ Session challenge progress updated successfully")
                } catch {
                    print("❌ Error updating session challenge: \(error)")
                }
            }
        }
    }
    
    // MARK: - Live Session Challenge Helper
    
    func updateSessionChallengesFromLiveSession(_ liveSession: LiveSessionData) async {
        print("🔄 Updating session challenges from live session")
        
        // Update all active session challenges with current progress
        for challenge in activeChallenges where challenge.type == .session {
            guard let challengeId = challenge.id else { continue }
            
            // Check if this session started after the challenge start date
            guard liveSession.startTime >= challenge.startDate else {
                print("   Live session predates challenge \(challenge.title) - skipping")
                continue
            }
            
            let currentHours = liveSession.elapsedTime / 3600.0
            
            print("   Challenge: \(challenge.title)")
            print("     Live session hours: \(String(format: "%.1f", currentHours))")
            print("     Minimum required: \(challenge.minHoursPerSession ?? 0)")
            
            // For live sessions, we can show real-time progress but don't update the actual challenge until session ends
            // This is handled by the UI components that display live progress
        }
    }
    
    // MARK: - Bankroll Challenge Helper
    
    func updateBankrollFromSessions(_ sessions: [Session]) async {
        print("🔍 Updating bankroll from sessions (per challenge)")
        
        // Update all active bankroll challenges
        for challenge in activeChallenges where challenge.type == .bankroll {
            guard let challengeId = challenge.id else { continue }
            
            // Calculate profit/loss from ALL sessions (to match how challenge setup calculates current bankroll)
            let totalSessionProfit = sessions.reduce(0) { $0 + $1.profit }
            
            let userBankroll = bankrollStore?.bankrollSummary.currentTotal ?? 0
            let currentBankroll = userBankroll + totalSessionProfit
            
            // Don't update challenges that were just created (within 30 seconds)
            let timeSinceCreation = Date().timeIntervalSince(challenge.createdAt)
            let isRecentlyCreated = timeSinceCreation < 30
            
            print("   Challenge: \(challenge.title)")
            print("     Total session profit: $\(totalSessionProfit)")
            print("     User bankroll: $\(userBankroll)")
            print("     Current bankroll : $\(currentBankroll)")
            print("     Target bankroll  : $\(challenge.targetValue)")
            print("     Time since creation: \(String(format: "%.1f", timeSinceCreation))s  (recent: \(isRecentlyCreated))")
            
            // Only update if the value actually changed and challenge isn't recently created
            if abs(currentBankroll - challenge.currentValue) > 0.01 && !isRecentlyCreated {
                do {
                    try await updateChallengeProgress(
                        challengeId: challengeId,
                        newValue: currentBankroll,
                        triggerEvent: "session_update"
                    )
                } catch {
                    print("❌ Error updating bankroll challenge: \(error)")
                }
            } else {
                if isRecentlyCreated {
                    print("     ⏳ Skipping update - challenge recently created")
                } else {
                    print("     ⏩ No update needed - bankroll unchanged")
                }
            }
        }
    }
    
    // MARK: - Unified Session Update Method
    
    func updateChallengesFromCompletedSession(_ session: Session) async {
        // Update both bankroll and session challenges
        await updateBankrollFromSessions([session])
        await updateSessionChallengesFromSession(session)
    }
    
    // MARK: - Challenge Completion Posts
    
    func createChallengeCompletionPost(for challenge: Challenge) async {
        guard challenge.status == .completed else { return }
        
        // Create display model and use its completion post generation
        let displayModel = ChallengeDisplayModel(challenge: challenge)
        let completionText = displayModel.generateCompletionPostContent()
        
        // Get user profile for post creation
        do {
            // This would need to be updated to work with the PostService
            // For now, we'll print the completion message
            print("🎉 Challenge Completed Post: \(completionText)")
            
            // TODO: Create actual post using PostService
            // This would require injecting PostService or UserService
            
        } catch {
            print("❌ Error creating challenge completion post: \(error)")
        }
    }
    
    // Helper method to format challenge values
    private func formattedValue(_ value: Double, type: ChallengeType) -> String {
        switch type {
        case .bankroll:
            return "$" + Int(value).formattedWithCommas
        case .hands:
            return "\(Int(value))"
        case .session:
            return "\(Int(value))" // Will be used for hours or session count
        }
    }
    
    // Helper method to format session challenge values specifically
    private func formattedSessionValue(_ challenge: Challenge) -> String {
        if let targetCount = challenge.targetSessionCount {
            return "\(challenge.validSessionsCount)/\(targetCount) sessions"
        } else if let targetHours = challenge.targetHours {
            return "\(String(format: "%.1f", challenge.totalHoursPlayed))/\(String(format: "%.1f", targetHours)) hours"
        } else {
            return "\(String(format: "%.1f", challenge.totalHoursPlayed)) hours"
        }
    }
    
    // MARK: - Challenge Progress Posts
    
    func createChallengeProgressPost(for challenge: Challenge, progressMade: Double, triggerEvent: String) async {
        guard challenge.status == .active,
              let challengeId = challenge.id,
              progressMade > 0 else { return }
        
        // Calculate current value dynamically for bankroll challenges
        let updatedChallenge: Challenge
        if challenge.type == .bankroll {
            // For bankroll challenges, calculate current bankroll dynamically
            let currentProgressValue = await calculateCurrentBankroll()
            print("💰 Dynamically calculated current bankroll for progress post: $\(currentProgressValue)")
            
            // Create updated challenge with dynamic value
            updatedChallenge = Challenge(
                id: challenge.id,
                userId: challenge.userId,
                type: challenge.type,
                title: challenge.title,
                description: challenge.description,
                targetValue: challenge.targetValue,
                currentValue: currentProgressValue,
                endDate: challenge.endDate,
                status: challenge.status,
                createdAt: challenge.createdAt,
                completedAt: challenge.completedAt,
                lastUpdated: challenge.lastUpdated,
                startingBankroll: challenge.startingBankroll,
                targetHours: challenge.targetHours,
                targetSessionCount: challenge.targetSessionCount,
                minHoursPerSession: challenge.minHoursPerSession,
                currentSessionCount: challenge.currentSessionCount,
                totalHoursPlayed: challenge.totalHoursPlayed,
                validSessionsCount: challenge.validSessionsCount,
            )
        } else {
            // For other challenge types, use stored currentValue
            updatedChallenge = challenge
        }
        
        // Create display model and use its progress post generation
        let displayModel = ChallengeDisplayModel(challenge: updatedChallenge)
        let progressText = displayModel.generatePostContent(isStarting: false)
        
        // TODO: Create actual post using PostService
        print("📈 Challenge Progress Post: \(progressText)")
    }
    
    // MARK: - Private Methods
    
    private func loadUserChallenges() {
        guard !userId.isEmpty else { return }
        
        isLoading = true
        
        // Listen to active challenges
        db.collection("challenges")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: ChallengeStatus.active.rawValue)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.error = "Failed to load challenges: \(error.localizedDescription)"
                        self.isLoading = false
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.isLoading = false
                        return
                    }
                    
                    self.activeChallenges = documents.compactMap { Challenge(document: $0) }
                    self.isLoading = false
                    
                    print("📊 Loaded \(self.activeChallenges.count) active challenges")
                }
            }
        
        // Listen to completed challenges
        db.collection("challenges")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: [ChallengeStatus.completed.rawValue, ChallengeStatus.failed.rawValue, ChallengeStatus.abandoned.rawValue])
            .order(by: "completedAt", descending: true)
            .limit(to: 10) // Limit completed challenges to recent ones
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("❌ Error loading completed challenges: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    
                    self.completedChallenges = documents.compactMap { Challenge(document: $0) }
                    
                    print("🏆 Loaded \(self.completedChallenges.count) completed challenges")
                }
            }
    }
    
    private func moveToCompletedChallenges(_ challenge: Challenge) async throws {
        guard let challengeId = challenge.id else { return }
        
        // Update challenge document - include currentValue to persist the final calculated value
        try await db.collection("challenges").document(challengeId).updateData([
            "status": ChallengeStatus.completed.rawValue,
            "completedAt": Timestamp(date: Date()),
            "lastUpdated": Timestamp(date: Date()),
            "currentValue": challenge.currentValue // CRITICAL: Persist the updated currentValue
        ])
        
        print("💾 Persisted challenge completion with currentValue: $\(challenge.currentValue)")
        
        // Remove from user's active challenges
        try await db.collection("users")
            .document(userId)
            .collection("activeChallenges")
            .document(challengeId)
            .delete()
        
        // Add to user's challenge history
        try await db.collection("users")
            .document(userId)
            .collection("challengeHistory")
            .document(challengeId)
            .setData([
                "challengeId": challengeId,
                "completedAt": Timestamp(date: Date()),
                "status": ChallengeStatus.completed.rawValue
            ])
        
        // Update local state - challenges will be updated via listeners
    }
    
    // MARK: - Helper Methods
    
    private func calculateCurrentBankroll() async -> Double {
        // Calculate the current bankroll using the same logic as updateBankrollFromSessions
        do {
            let snapshot = try await db.collection("sessions")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            let sessions = snapshot.documents.compactMap { document in
                Session(id: document.documentID, data: document.data())
            }
            let totalSessionProfit = sessions.reduce(0) { $0 + $1.profit }
            let userBankroll = bankrollStore?.bankrollSummary.currentTotal ?? 0
            let currentBankroll = userBankroll + totalSessionProfit
            
            print("💰 Current bankroll calculation:")
            print("   User bankroll: $\(userBankroll)")
            print("   Total session profit: $\(totalSessionProfit)")
            print("   Current bankroll: $\(currentBankroll)")
            
            return currentBankroll
        } catch {
            print("❌ Error calculating current bankroll: \(error)")
            return 0 // Fallback to 0 if calculation fails
        }
    }
} 
