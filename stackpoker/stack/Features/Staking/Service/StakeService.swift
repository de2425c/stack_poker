import Foundation
import FirebaseFirestore

class StakeService: ObservableObject {
    private let db = Firestore.firestore()
    private var stakesCollectionRef: CollectionReference { db.collection("stakes") }

    // MARK: - Create
    func addStake(_ stake: Stake) async throws -> String {
        var stakeToSave = stake
        // If ID is nil, Firestore will generate one. 
        // If it has an ID (e.g. from a specific assignment), it will use that.
        if stakeToSave.id == nil {
            stakeToSave.id = stakesCollectionRef.document().documentID
        }
        
        guard let stakeId = stakeToSave.id else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Stake ID is missing"])
        }
        
        print("StakeService: Adding stake to Firestore with ID: \(stakeId)")
        print("StakeService: Stake details - sessionGameName: '\(stakeToSave.sessionGameName)', isOffAppStake: '\(stakeToSave.isOffAppStake ?? false)'")
        
        try stakesCollectionRef.document(stakeId).setData(from: stakeToSave)
        
        print("StakeService: Successfully saved stake with ID: \(stakeId)")
        return stakeId
    }

    // MARK: - Read
    func fetchStakes(forUser userId: String) async throws -> [Stake] {
        // Fetch stakes where the user is the staker
        let stakerQuery = stakesCollectionRef.whereField(Stake.CodingKeys.stakerUserId.rawValue, isEqualTo: userId)
        // Fetch stakes where the user is the staked player
        let stakedPlayerQuery = stakesCollectionRef.whereField(Stake.CodingKeys.stakedPlayerUserId.rawValue, isEqualTo: userId)

        var allStakes: [Stake] = []
        var encounteredStakeIds = Set<String>()

        do {
            let stakerSnapshots = try await stakerQuery.getDocuments()
            for document in stakerSnapshots.documents {
                if let stake = try? document.data(as: Stake.self), let stakeId = stake.id {
                    if !encounteredStakeIds.contains(stakeId) {
                        allStakes.append(stake)
                        encounteredStakeIds.insert(stakeId)
                    }
                }
            }

            let stakedPlayerSnapshots = try await stakedPlayerQuery.getDocuments()
            for document in stakedPlayerSnapshots.documents {
                if let stake = try? document.data(as: Stake.self), let stakeId = stake.id {
                    if !encounteredStakeIds.contains(stakeId) {
                        allStakes.append(stake)
                        encounteredStakeIds.insert(stakeId)
                    }
                }
            }
            
            // Sort by date, most recent first
            allStakes.sort { $0.proposedAt > $1.proposedAt }
            return allStakes
        } catch {

            throw error
        }
    }
    
    // NEW: Fetch stakes where user is specifically the staked player
    func fetchStakesForUser(userId: String, asStakedPlayer: Bool) async throws -> [Stake] {
        if asStakedPlayer {
            // Only fetch stakes where the user is the staked player
            let stakedPlayerQuery = stakesCollectionRef.whereField(Stake.CodingKeys.stakedPlayerUserId.rawValue, isEqualTo: userId)
            
            do {
                let snapshot = try await stakedPlayerQuery.getDocuments()
                let stakes = snapshot.documents.compactMap { try? $0.data(as: Stake.self) }
                return stakes.sorted { $0.proposedAt > $1.proposedAt }
            } catch {
                throw error
            }
        } else {
            // Fallback to the existing method that fetches all stakes
            return try await fetchStakes(forUser: userId)
        }
    }
    
    // MARK: - Read (single session fetch by ID)
    func fetchStakesForSession(_ sessionId: String) async throws -> [Stake] {
        // Simple query by sessionId (document ID of the session)
        let query = stakesCollectionRef.whereField(Stake.CodingKeys.sessionId.rawValue, isEqualTo: sessionId)
        do {
            let snapshot = try await query.getDocuments()
            let stakes = snapshot.documents.compactMap { try? $0.data(as: Stake.self) }
            return stakes.sorted { $0.proposedAt > $1.proposedAt }
        } catch {
            throw error
        }
    }
    
    // MARK: - Read stakes by live session UUID (active sessions)
    func fetchStakesForLiveSession(_ liveSessionId: String) async throws -> [Stake] {
        // Stakes saved during an in-progress live session can be keyed by either:
        // 1. `liveSessionId` field (for paused sessions)
        // 2. `sessionId` field (for immediately persisted stakes)
        
        print("StakeService: Fetching stakes for live session ID: \(liveSessionId)")
        
        // First try to find by liveSessionId field
        let liveSessionQuery = stakesCollectionRef.whereField("liveSessionId", isEqualTo: liveSessionId)
        var stakes: [Stake] = []
        
        do {
            let liveSessionSnapshot = try await liveSessionQuery.getDocuments()
            stakes = liveSessionSnapshot.documents.compactMap { try? $0.data(as: Stake.self) }
            print("StakeService: Found \(stakes.count) stakes with liveSessionId field")
            
            // Also try to find by sessionId field (for immediately persisted stakes)
            let sessionIdQuery = stakesCollectionRef.whereField(Stake.CodingKeys.sessionId.rawValue, isEqualTo: liveSessionId)
            let sessionIdSnapshot = try await sessionIdQuery.getDocuments()
            let sessionIdStakes = sessionIdSnapshot.documents.compactMap { try? $0.data(as: Stake.self) }
            print("StakeService: Found \(sessionIdStakes.count) stakes with sessionId field")
            
            // Combine and deduplicate
            var allStakes = stakes
            for stake in sessionIdStakes {
                if !allStakes.contains(where: { $0.id == stake.id }) {
                    allStakes.append(stake)
                }
            }
            
            print("StakeService: Total unique stakes found: \(allStakes.count)")
            return allStakes.sorted { $0.proposedAt > $1.proposedAt }
        } catch {
            print("StakeService: Error fetching stakes: \(error)")
            throw error
        }
    }
    
    // WORKAROUND: Fetch by user then filter (calls the direct query first)
    func fetchStakesForSession(_ sessionId: String, forUser userId: String) async throws -> [Stake] {
        // Try direct query first
        let direct = try await fetchStakesForSession(sessionId)
        if !direct.isEmpty {
            return direct
        }
        // Fallback: fetch all stakes for user and filter
        let allUserStakes = try await fetchStakes(forUser: userId)
        return allUserStakes.filter { $0.sessionId == sessionId }
    }

    // MARK: - Update
    // func updateStakeStatus(stakeId: String, newStatus: Stake.StakeStatus, settledAt: Date? = nil) async throws { // Old function
    //     var dataToUpdate: [String: Any] = [
    //         Stake.CodingKeys.status.rawValue: newStatus.rawValue,
    //         Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
    //     ]
    //     if let settledAt = settledAt, newStatus == .settled {
    //         dataToUpdate[Stake.CodingKeys.settledAt.rawValue] = Timestamp(date: settledAt)
    //     }
    //     try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
    // }
    
    // // func markStakeAsSettled(stakeId: String) async throws { // Old function
    // //     try await updateStakeStatus(stakeId: stakeId, newStatus: .settled, settledAt: Date())
    // // }

    func initiateSettlement(stakeId: String, initiatorUserId: String) async throws {
        // First, fetch the current stake to validate the operation
        let stakeDoc = try await stakesCollectionRef.document(stakeId).getDocument()
        guard let currentStake = try? stakeDoc.data(as: Stake.self) else {
            throw NSError(domain: "StakeService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stake not found"])
        }
        
        // Validate that the stake is in the correct state for settlement initiation
        guard currentStake.status == .awaitingSettlement else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Stake is not in awaiting settlement status"])
        }
        
        // Validate that the initiator is either the staker or the player
        guard currentStake.stakerUserId == initiatorUserId || currentStake.stakedPlayerUserId == initiatorUserId else {
            throw NSError(domain: "StakeService", code: 403, userInfo: [NSLocalizedDescriptionKey: "User not authorized to initiate settlement"])
        }
        
        let dataToUpdate: [String: Any] = [
            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.awaitingConfirmation.rawValue,
            Stake.CodingKeys.settlementInitiatorUserId.rawValue: initiatorUserId,
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
    }

    func confirmSettlement(stakeId: String, confirmingUserId: String) async throws {
        // Fetch the current stake to validate the operation
        let stakeDoc = try await stakesCollectionRef.document(stakeId).getDocument()
        guard let currentStake = try? stakeDoc.data(as: Stake.self) else {
            throw NSError(domain: "StakeService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stake not found"])
        }
        
        // Validate that the stake is in the correct state for confirmation
        guard currentStake.status == .awaitingConfirmation else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Stake is not awaiting confirmation"])
        }
        
        // Validate that the confirming user is not the same as the initiator
        guard currentStake.settlementInitiatorUserId != confirmingUserId else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot confirm your own settlement initiation"])
        }
        
        // Validate that the confirming user is either the staker or the player
        guard currentStake.stakerUserId == confirmingUserId || currentStake.stakedPlayerUserId == confirmingUserId else {
            throw NSError(domain: "StakeService", code: 403, userInfo: [NSLocalizedDescriptionKey: "User not authorized to confirm settlement"])
        }
        
        let dataToUpdate: [String: Any] = [
            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.settled.rawValue,
            Stake.CodingKeys.settlementConfirmerUserId.rawValue: confirmingUserId,
            Stake.CodingKeys.settledAt.rawValue: Timestamp(date: Date()),
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
    }
    
    // Special method for manual stakers - player can mark as settled directly
    func settleManualStake(stakeId: String, userId: String) async throws {
        // Fetch the current stake to validate the operation
        let stakeDoc = try await stakesCollectionRef.document(stakeId).getDocument()
        guard let currentStake = try? stakeDoc.data(as: Stake.self) else {
            throw NSError(domain: "StakeService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stake not found"])
        }
        
        // Validate that this is actually a manual stake
        guard currentStake.isOffAppStake == true else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "This is not a manual stake"])
        }
        
        // Validate that the stake is in a settleable state
        guard currentStake.status == .awaitingSettlement || currentStake.status == .awaitingConfirmation else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Stake is not in a settleable state"])
        }
        
        // Validate that the user is either the staked player OR the staker (both can settle manual stakes)
        guard currentStake.stakedPlayerUserId == userId || currentStake.stakerUserId == userId else {
            throw NSError(domain: "StakeService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only the staked player or staker can settle manual stakes"])
        }
        
        let dataToUpdate: [String: Any] = [
            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.settled.rawValue,
            Stake.CodingKeys.settlementInitiatorUserId.rawValue: userId,
            Stake.CodingKeys.settlementConfirmerUserId.rawValue: userId, // Same user for manual stakes
            Stake.CodingKeys.settledAt.rawValue: Timestamp(date: Date()),
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
    }

    // MARK: - Update Stake Percentage & Markup
    func updateStake(stakeId: String, newPercentage: Double, newMarkup: Double) async throws {
        let data: [String: Any] = [
            Stake.CodingKeys.stakePercentage.rawValue: newPercentage,
            Stake.CodingKeys.markup.rawValue: newMarkup,
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        try await stakesCollectionRef.document(stakeId).updateData(data)
    }
    
    // General method to update any stake fields
    func updateStake(stakeId: String, updateData: [String: Any]) async throws {
        var dataToUpdate = updateData
        // Always update the lastUpdatedAt timestamp
        dataToUpdate[Stake.CodingKeys.lastUpdatedAt.rawValue] = Timestamp(date: Date())
        
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
    }
    
    // Method to update session results for tournament stakes
    func updateStakeSessionResults(stakeId: String, buyIn: Double, cashout: Double) async throws {
        // First, fetch the current stake to validate the operation
        let stakeDoc = try await stakesCollectionRef.document(stakeId).getDocument()
        guard let currentStake = try? stakeDoc.data(as: Stake.self) else {
            throw NSError(domain: "StakeService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stake not found"])
        }
        
        // Validate that the stake is active and can have results updated
        guard currentStake.status == .active else {
            throw NSError(domain: "StakeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Can only update results for active stakes"])
        }
        
        // Calculate the settlement amount using the correct formula
        let stakerCost = buyIn * currentStake.stakePercentage * currentStake.markup
        let stakerShareOfCashout = cashout * currentStake.stakePercentage
        let amountTransferred = stakerShareOfCashout - stakerCost
        
        let dataToUpdate: [String: Any] = [
            Stake.CodingKeys.totalPlayerBuyInForSession.rawValue: buyIn,
            Stake.CodingKeys.playerCashoutForSession.rawValue: cashout,
            Stake.CodingKeys.storedAmountTransferredAtSettlement.rawValue: amountTransferred,
            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.awaitingSettlement.rawValue,
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
    }

    // MARK: - Delete
    // (Optional - consider if stakes should be deletable or only cancellable/archived)
    func deleteStake(_ stakeId: String) async throws {
        try await stakesCollectionRef.document(stakeId).delete()
    }
    
    // Function to delete all stakes associated with a session (e.g., if a session is deleted)
    /*
    func deleteAllStakesForSession(sessionId: String) async throws {
        let stakesToDelete = try await fetchStakesForSession(sessionId)
        let batch = db.batch()
        for stake in stakesToDelete {
            if let stakeId = stake.id {
                batch.deleteDocument(stakesCollectionRef.document(stakeId))
            }
        }
        try await batch.commit()
    }
    */
    
    // NEW: Callback for when stakes are updated - allows other services to recalculate adjusted profits
    var onStakeUpdated: ((String) -> Void)? // Callback with sessionId
    
    // NEW: Helper method to trigger adjusted profit recalculation
    func notifyStakeUpdated(for sessionId: String) {
        onStakeUpdated?(sessionId)
    }
    
    // MARK: - Enhanced methods that trigger adjusted profit recalculation
    
    func addStakeWithAdjustedProfitUpdate(_ stake: Stake) async throws {
        try await addStake(stake)
        notifyStakeUpdated(for: stake.sessionId)
    }
    
    func updateStakeWithAdjustedProfitUpdate(stakeId: String, updateData: [String: Any]) async throws {
        // Get the stake first to know which session to update
        let stakeDoc = try await stakesCollectionRef.document(stakeId).getDocument()
        guard let currentStake = try? stakeDoc.data(as: Stake.self) else {
            throw NSError(domain: "StakeService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stake not found"])
        }
        
        try await updateStake(stakeId: stakeId, updateData: updateData)
        notifyStakeUpdated(for: currentStake.sessionId)
    }
} 
