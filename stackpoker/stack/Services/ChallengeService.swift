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
    
    private let db = Firestore.firestore()
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
        if !userId.isEmpty {
            loadUserChallenges()
        }
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
    
    // MARK: - Bankroll Challenge Helper
    
    func updateBankrollFromSessions(_ sessions: [Session]) async {
        print("🔍 Updating bankroll from sessions (per challenge)")
        
        // Update all active bankroll challenges
        for challenge in activeChallenges where challenge.type == .bankroll {
            guard let challengeId = challenge.id else { continue }
            
            // Calculate profit/loss ONLY from sessions that occurred AFTER the challenge start date
            let profitSinceStart = sessions
                .filter { $0.startDate >= challenge.startDate }
                .reduce(0) { $0 + $1.profit }
            
            let startingBankroll = challenge.startingBankroll ?? 0
            let currentBankroll = startingBankroll + profitSinceStart
            
            // Don't update challenges that were just created (within 30 seconds)
            let timeSinceCreation = Date().timeIntervalSince(challenge.createdAt)
            let isRecentlyCreated = timeSinceCreation < 30
            
            print("   Challenge: \(challenge.title)")
            print("     Profit since start: $\(profitSinceStart)")
            print("     Starting bankroll: $\(startingBankroll)")
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
    
    // MARK: - Challenge Completion Posts
    
    func createChallengeCompletionPost(for challenge: Challenge) async {
        guard challenge.status == .completed,
              let challengeId = challenge.id else { return }
        
        let completionText = """
        🎉 Challenge Completed!
        
        \(challenge.title)
        
        Target: \(formattedValue(challenge.targetValue, type: challenge.type))
        Final: \(formattedValue(challenge.currentValue, type: challenge.type))
        
        #ChallengeCompleted #\(challenge.type.rawValue.capitalized)Goal
        """
        
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
            return "$\(Int(value).formattedWithCommas)"
        case .hands:
            return "\(Int(value))"
        case .session:
            return "\(Int(value))"
        }
    }
    
    // MARK: - Challenge Progress Posts
    
    func createChallengeProgressPost(for challenge: Challenge, progressMade: Double, triggerEvent: String) async {
        guard challenge.status == .active,
              let challengeId = challenge.id,
              progressMade > 0 else { return }
        
        let progressText = """
        🎯 Challenge Update: \(challenge.title)
        
        Progress: \(formattedValue(challenge.currentValue, type: challenge.type))
        Target: \(formattedValue(challenge.targetValue, type: challenge.type))
        
        \(Int(challenge.progressPercentage))% Complete
        
        #ChallengeProgress #\(challenge.type.rawValue.capitalized)Goal
        """
        
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
        
        // Update challenge document
        try await db.collection("challenges").document(challengeId).updateData([
            "status": ChallengeStatus.completed.rawValue,
            "completedAt": Timestamp(date: Date()),
            "lastUpdated": Timestamp(date: Date())
        ])
        
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
}

// Extension for number formatting
extension Int {
    var formattedWithCommas: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
} 