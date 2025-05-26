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
        try stakesCollectionRef.document(stakeToSave.id!).setData(from: stakeToSave)
        return stakeToSave.id!
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
            print("Error fetching stakes for user \(userId): \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchStakesForSession(_ sessionId: String) async throws -> [Stake] {
        let query = stakesCollectionRef.whereField(Stake.CodingKeys.sessionId.rawValue, isEqualTo: sessionId)
        do {
            let snapshot = try await query.getDocuments()
            let stakes = snapshot.documents.compactMap { document -> Stake? in
                try? document.data(as: Stake.self)
            }
            return stakes.sorted { $0.proposedAt > $1.proposedAt }
        } catch {
            print("Error fetching stakes for session \(sessionId): \(error.localizedDescription)")
            throw error
        }
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
        let dataToUpdate: [String: Any] = [
            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.awaitingConfirmation.rawValue,
            Stake.CodingKeys.settlementInitiatorUserId.rawValue: initiatorUserId,
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
        print("Settlement initiated for stake \(stakeId) by user \(initiatorUserId)")
    }

    func confirmSettlement(stakeId: String, confirmingUserId: String) async throws {
        // It might be good to fetch the stake first to ensure it's in awaitingConfirmation status
        // and that confirmingUserId is not the same as settlementInitiatorUserId.
        // For brevity in MVP, we'll directly update.
        let dataToUpdate: [String: Any] = [
            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.settled.rawValue,
            Stake.CodingKeys.settlementConfirmerUserId.rawValue: confirmingUserId,
            Stake.CodingKeys.settledAt.rawValue: Timestamp(date: Date()),
            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        try await stakesCollectionRef.document(stakeId).updateData(dataToUpdate)
        print("Settlement confirmed for stake \(stakeId) by user \(confirmingUserId)")
    }

    // MARK: - Delete
    // (Optional - consider if stakes should be deletable or only cancellable/archived)
    func deleteStake(_ stakeId: String) async throws {
        try await stakesCollectionRef.document(stakeId).delete()
    }
    
    // Function to delete all stakes associated with a session (e.g., if a session is deleted)
    func deleteAllStakesForSession(sessionId: String) async throws {
        let stakesToDelete = try await fetchStakesForSession(sessionId)
        let batch = db.batch()
        for stake in stakesToDelete {
            if let stakeId = stake.id {
                batch.deleteDocument(stakesCollectionRef.document(stakeId))
            }
        }
        try await batch.commit()
        print("Deleted all stakes for session \(sessionId).")
    }
} 
