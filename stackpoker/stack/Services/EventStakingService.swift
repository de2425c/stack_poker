import Foundation
import FirebaseFirestore

class EventStakingService: ObservableObject {
    private let db = Firestore.firestore()
    private var eventStakingInvitesCollectionRef: CollectionReference { 
        db.collection("eventStakingInvites") 
    }
    
    @Published var stakingInvites: [EventStakingInvite] = []
    @Published var isLoading = false
    
    // MARK: - Create
    
    /// Create staking invites for an event
    func createEventStakingInvites(
        eventId: String,
        eventName: String,
        eventDate: Date,
        stakedPlayerUserId: String,
        maxBullets: Int,
        markup: Double,
        stakers: [(stakerUserId: String, percentageBought: Double, amountBought: Double, isManual: Bool, displayName: String?)]
    ) async throws -> [String] {
        var createdInviteIds: [String] = []
        
        for stakerInfo in stakers {
            let invite = EventStakingInvite(
                eventId: eventId,
                eventName: eventName,
                eventDate: eventDate,
                stakedPlayerUserId: stakedPlayerUserId,
                stakerUserId: stakerInfo.stakerUserId,
                maxBullets: maxBullets,
                markup: markup,
                percentageBought: stakerInfo.percentageBought,
                amountBought: stakerInfo.amountBought,
                isManualStaker: stakerInfo.isManual,
                manualStakerDisplayName: stakerInfo.displayName
            )
            
            let docRef = eventStakingInvitesCollectionRef.document()
            try docRef.setData(from: invite)
            createdInviteIds.append(docRef.documentID)
        }
        
        return createdInviteIds
    }
    
    // MARK: - Read
    
    /// Fetch staking invites where user is invited as a staker
    func fetchStakingInvitesAsStaker(userId: String) async throws -> [EventStakingInvite] {
        await MainActor.run { isLoading = true }
        
        let query = eventStakingInvitesCollectionRef
            .whereField(EventStakingInvite.CodingKeys.stakerUserId.rawValue, isEqualTo: userId)
            .order(by: EventStakingInvite.CodingKeys.createdAt.rawValue, descending: true)
        
        do {
            let snapshot = try await query.getDocuments()
            
            var invites: [EventStakingInvite] = []
            for document in snapshot.documents {
                do {
                    let invite = try document.data(as: EventStakingInvite.self)
                    invites.append(invite)
                } catch {
                    print("Failed to decode event staking invite document \(document.documentID): \(error)")
                }
            }
            
            await MainActor.run {
                self.isLoading = false
            }
            
            return invites
        } catch {
            await MainActor.run { isLoading = false }
            throw error
        }
    }
    
    /// Fetch staking invites where user created the staking setup
    func fetchStakingInvitesAsPlayer(userId: String) async throws -> [EventStakingInvite] {
        await MainActor.run { isLoading = true }
        
        let query = eventStakingInvitesCollectionRef
            .whereField(EventStakingInvite.CodingKeys.stakedPlayerUserId.rawValue, isEqualTo: userId)
            .order(by: EventStakingInvite.CodingKeys.createdAt.rawValue, descending: true)
        
        do {
            let snapshot = try await query.getDocuments()
            
            var invites: [EventStakingInvite] = []
            for document in snapshot.documents {
                do {
                    let invite = try document.data(as: EventStakingInvite.self)
                    invites.append(invite)
                } catch {
                    print("Failed to decode event staking invite document \(document.documentID): \(error)")
                }
            }
            
            await MainActor.run {
                self.isLoading = false
            }
            
            return invites
        } catch {
            await MainActor.run { isLoading = false }
            throw error
        }
    }
    
    /// Fetch staking invites for a specific event
    func fetchStakingInvitesForEvent(eventId: String) async throws -> [EventStakingInvite] {
        let query = eventStakingInvitesCollectionRef
            .whereField(EventStakingInvite.CodingKeys.eventId.rawValue, isEqualTo: eventId)
            .order(by: EventStakingInvite.CodingKeys.createdAt.rawValue, descending: true)
        
        let snapshot = try await query.getDocuments()
        
        var invites: [EventStakingInvite] = []
        for document in snapshot.documents {
            do {
                let invite = try document.data(as: EventStakingInvite.self)
                invites.append(invite)
            } catch {
                print("Failed to decode event staking invite document \(document.documentID): \(error)")
            }
        }
        
        return invites
    }
    
    // MARK: - Update
    
    /// Accept a staking invite
    func acceptStakingInvite(inviteId: String) async throws {
        let data: [String: Any] = [
            EventStakingInvite.CodingKeys.status.rawValue: EventStakingInvite.InviteStatus.accepted.rawValue,
            EventStakingInvite.CodingKeys.respondedAt.rawValue: Timestamp(date: Date()),
            EventStakingInvite.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        
        try await eventStakingInvitesCollectionRef.document(inviteId).updateData(data)
    }
    
    /// Decline a staking invite
    func declineStakingInvite(inviteId: String) async throws {
        let data: [String: Any] = [
            EventStakingInvite.CodingKeys.status.rawValue: EventStakingInvite.InviteStatus.declined.rawValue,
            EventStakingInvite.CodingKeys.respondedAt.rawValue: Timestamp(date: Date()),
            EventStakingInvite.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date())
        ]
        
        try await eventStakingInvitesCollectionRef.document(inviteId).updateData(data)
    }
    
    // MARK: - Delete
    
    /// Delete staking invites for an event (useful when event is cancelled)
    func deleteStakingInvitesForEvent(eventId: String) async throws {
        let query = eventStakingInvitesCollectionRef
            .whereField(EventStakingInvite.CodingKeys.eventId.rawValue, isEqualTo: eventId)
        
        let snapshot = try await query.getDocuments()
        
        for document in snapshot.documents {
            try await document.reference.delete()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Check if user has any pending staking invites
    func hasPendingInvites(userId: String) async throws -> Bool {
        let query = eventStakingInvitesCollectionRef
            .whereField(EventStakingInvite.CodingKeys.stakerUserId.rawValue, isEqualTo: userId)
            .whereField(EventStakingInvite.CodingKeys.status.rawValue, isEqualTo: EventStakingInvite.InviteStatus.pending.rawValue)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        return !snapshot.documents.isEmpty
    }
    
    /// Get count of pending invites for a user
    func getPendingInvitesCount(userId: String) async throws -> Int {
        let query = eventStakingInvitesCollectionRef
            .whereField(EventStakingInvite.CodingKeys.stakerUserId.rawValue, isEqualTo: userId)
            .whereField(EventStakingInvite.CodingKeys.status.rawValue, isEqualTo: EventStakingInvite.InviteStatus.pending.rawValue)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.count
    }
} 