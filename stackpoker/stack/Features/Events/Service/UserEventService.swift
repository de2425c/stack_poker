import Foundation
import Firebase
import FirebaseFirestore
import FirebaseStorage
import Combine
import FirebaseAuth

@MainActor
class UserEventService: ObservableObject {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let homeGameService = HomeGameService()
    @Published var userEvents: [UserEvent] = []
    @Published var pendingInvites: [EventInvite] = []
    @Published var publicEventRSVPs: [PublicEventRSVP] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var eventListeners: [String: ListenerRegistration] = [:]
    private var myEventsListener: ListenerRegistration? = nil
    private var myRSVPListener: ListenerRegistration? = nil
    private var invitesListener: ListenerRegistration? = nil
    private var statusUpdateTimer: Timer? = nil
    
    // MARK: - Event Creation and Management
    
    /// Create a new user event
    func createEvent(
        title: String,
        description: String?,
        eventType: UserEvent.EventType,
        startDate: Date,
        endDate: Date?,
        timezone: String = TimeZone.current.identifier,
        location: String?,
        maxParticipants: Int?,
        waitlistEnabled: Bool = true,
        groupId: String? = nil,
        isPublic: Bool = false,
        rsvpDeadline: Date? = nil,
        reminderSettings: UserEvent.ReminderSettings? = nil,
        image: UIImage? = nil,
        isBanked: Bool = false
    ) async throws -> UserEvent {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Get user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Create event document
        let eventRef = db.collection("userEvents").document()
        let eventId = eventRef.documentID
        
        // Upload image if provided
        var imageURL: String? = nil
        if let image = image {
            imageURL = try await uploadEventImage(image, eventId: eventId)
        }
        
        let newEvent = UserEvent(
            id: eventId,
            title: title,
            description: description,
            eventType: eventType,
            creatorId: currentUser.uid,
            creatorName: displayName,
            startDate: startDate,
            endDate: endDate,
            timezone: timezone,
            location: location,
            maxParticipants: maxParticipants,
            waitlistEnabled: waitlistEnabled,
            groupId: groupId,
            isPublic: isPublic,
            rsvpDeadline: rsvpDeadline,
            reminderSettings: reminderSettings ?? UserEvent.ReminderSettings.defaultReminders,
            imageURL: imageURL,
            isBanked: isBanked
        )
        
        // set participant count locally to 1
        var dict = newEvent.toDictionary()
        dict["currentParticipants"] = 1
        
        try await eventRef.setData(dict)
        
        // Auto-RSVP creator as GOING
        let rsvp = EventRSVP(eventId: eventId,
                             userId: currentUser.uid,
                             userDisplayName: displayName,
                             status: .going)
        try await db.collection("eventRSVPs").document(rsvp.id).setData(rsvp.toDictionary())
        
        // ensure currentParticipants is correct
        try await updateEventParticipantCount(eventId: eventId)
        
        return newEvent
    }
    
    /// Update event statuses based on current time
    func updateEventStatuses() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        let allEventsNeedingCheck = userEvents
        
        for event in allEventsNeedingCheck {
            let oldStatus = event.status
            let newStatus = event.currentStatus

            if oldStatus != newStatus {
                try await db.collection("userEvents").document(event.id).updateData([
                    "status": newStatus.rawValue,
                    "updatedAt": Timestamp(date: Date())
                ])
            }
        }
    }
    
    /// Start banking for an event - creates home game and sends invites to all going RSVPs
    func startBankingForEvent(eventId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Get the event and verify permissions
        guard let event = try await fetchEvent(eventId: eventId) else {
            throw UserEventServiceError.eventNotFound
        }
        
        guard event.creatorId == currentUser.uid else {
            throw UserEventServiceError.permissionDenied
        }
        
        guard event.isBanked && event.linkedGameId == nil else {
            throw UserEventServiceError.invalidData
        }
        
        // Get all "going" RSVPs
        let rsvps = try await fetchEventRSVPs(eventId: eventId)
        let goingRSVPs = rsvps.filter { $0.status == .going }
        
        // Create the home game with just the creator (host)
        let playerInfoList: [HomeGameService.PlayerInfo] = [
            .init(userId: event.creatorId, displayName: event.creatorName)
        ]
        
        // Create the home game
        let newHomeGame = try await homeGameService.createHomeGame(
            title: event.title,
            creatorId: event.creatorId,
            creatorName: event.creatorName,
            initialPlayers: playerInfoList,
            linkedEventId: event.id
        )
        
        // Send game invites to all other RSVP'd players (excluding the creator)
        for rsvp in goingRSVPs {
            if rsvp.userId != event.creatorId {
                try await homeGameService.sendGameInvite(
                    gameId: newHomeGame.id,
                    invitedUserId: rsvp.userId,
                    invitedUserDisplayName: rsvp.userDisplayName,
                    message: "You're invited to join the banking for '\(event.title)' that you RSVP'd to!"
                )
            }
        }
        
        // Update the event with the linkedGameId
        try await db.collection("userEvents").document(event.id).updateData([
            "linkedGameId": newHomeGame.id
        ])
        
        // Notify UI to refresh standalone game bar
        NotificationCenter.default.post(name: NSNotification.Name("RefreshStandaloneHomeGame"), object: nil)
    }
    
    /// Start periodic status updates (every 30 seconds)
    func startStatusUpdateTimer() {
        stopStatusUpdateTimer()
        
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                try? await self?.updateEventStatuses()
            }
        }
    }
    
    /// Stop periodic status updates
    func stopStatusUpdateTimer() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
    }
    
    /// Upload event image to Firebase Storage
    private func uploadEventImage(_ image: UIImage, eventId: String) async throws -> String {
        // Compress the image to reduce upload size
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw UserEventServiceError.invalidData
        }
        
        // Create a unique file name for the image
        let fileName = "event_\(eventId)_\(Date().timeIntervalSince1970).jpg"
        
        // Get the Firebase Storage reference
        let storageRef = storage.reference().child("events/\(fileName)")
        
        // Upload the image to Firebase Storage
        do {
            // Upload the image
            _ = try await storageRef.putData(imageData, metadata: nil)
            
            // Add a small delay to allow Firebase to process the upload
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Get the download URL with retries
            var downloadURL: URL?
            var retryCount = 0
            let maxRetries = 3
            
            while downloadURL == nil && retryCount < maxRetries {
                do {
                    downloadURL = try await storageRef.downloadURL()
                } catch {
                    retryCount += 1
                    if retryCount < maxRetries {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay between retries
                    }
                }
            }
            
            guard let finalURL = downloadURL else {
                throw NSError(domain: "UserEventService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL after \(maxRetries) attempts"])
            }
            
            return finalURL.absoluteString
        } catch {
            throw error
        }
    }
    
    /// Update an existing event
    func updateEvent(_ event: UserEvent) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        guard event.creatorId == currentUser.uid else {
            throw UserEventServiceError.permissionDenied
        }
        
        var updatedDict = event.toDictionary()
        updatedDict["updatedAt"] = Timestamp(date: Date())
        
        try await db.collection("userEvents").document(event.id).updateData(updatedDict)
    }
    
    /// Delete an event
    func deleteEvent(eventId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Check if user owns the event
        let eventDoc = try await db.collection("userEvents").document(eventId).getDocument()
        guard let eventData = eventDoc.data(),
              let creatorId = eventData["creatorId"] as? String,
              creatorId == currentUser.uid else {
            throw UserEventServiceError.permissionDenied
        }
        
        // Delete the event and all related data
        let batch = db.batch()
        
        // Delete event
        batch.deleteDocument(db.collection("userEvents").document(eventId))
        
        // Delete all RSVPs for this event
        let rsvpQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()
        
        for rsvpDoc in rsvpQuery.documents {
            batch.deleteDocument(rsvpDoc.reference)
        }
        
        // Delete all invites for this event
        let inviteQuery = try await db.collection("eventInvites")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()
        
        for inviteDoc in inviteQuery.documents {
            batch.deleteDocument(inviteDoc.reference)
        }
        
        try await batch.commit()
    }
    
    /// Fetch user's created events *and* events they've RSVP'd to
    func fetchUserEvents() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        var combined: [UserEvent] = []
        
        // 1. Events the user CREATED
        let createdSnapshot = try await db.collection("userEvents")
            .whereField("creatorId", isEqualTo: currentUser.uid)
            .order(by: "startDate", descending: false)
            .getDocuments()
        
        for doc in createdSnapshot.documents {
            if let ev = try? UserEvent(dictionary: doc.data(), id: doc.documentID) {
                combined.append(ev)
            }
        }
        
        // 2. Events the user RSVP'd to (going / maybe / waitlisted)
        let rsvpSnapshot = try await db.collection("eventRSVPs")
            .whereField("userId", isEqualTo: currentUser.uid)
            .whereField("status", in: ["going", "maybe", "waitlisted"])
            .getDocuments()
        
        let eventIds = rsvpSnapshot.documents.compactMap { $0.data()["eventId"] as? String }
        
        if !eventIds.isEmpty {
            // Firestore 'in' supports up to 10 ids – chunk if necessary
            let chunks = stride(from: 0, to: eventIds.count, by: 10).map { Array(eventIds[$0..<min($0+10, eventIds.count)]) }
            for chunk in chunks {
                let evSnap = try await db.collection("userEvents")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                for doc in evSnap.documents {
                    if let ev = try? UserEvent(dictionary: doc.data(), id: doc.documentID) {
                        // avoid duplicates (if user is creator too)
                        if !combined.contains(where: { $0.id == ev.id }) {
                            combined.append(ev)
                        }
                    }
                }
            }
        }
        
        // Sort by startDate
        combined.sort { $0.startDate < $1.startDate }
        self.userEvents = combined
    }
    
    /// Fetch a specific event by ID
    func fetchEvent(eventId: String) async throws -> UserEvent? {
        let docSnapshot = try await db.collection("userEvents").document(eventId).getDocument()
        
        guard docSnapshot.exists, let data = docSnapshot.data() else {
            return nil
        }
        
        return try UserEvent(dictionary: data, id: eventId)
    }
    
    /// Fetch all user events (for checking if regular events are already added to schedule)
    func fetchAllUserEvents() async throws -> [UserEvent] {
        let querySnapshot = try await db.collection("userEvents").getDocuments()
        
        var events: [UserEvent] = []
        for document in querySnapshot.documents {
            let data = document.data()
            if let event = try? UserEvent(dictionary: data, id: document.documentID) {
                events.append(event)
            }
        }
        
        return events.sorted { $0.startDate < $1.startDate }
    }
    
    // MARK: - RSVP Management
    
    /// Submit RSVP for an event
    func rsvpToEvent(eventId: String, status: EventRSVP.RSVPStatus, notes: String? = nil) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Get user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Get the event to check capacity
        guard let event = try await fetchEvent(eventId: eventId) else {
            throw UserEventServiceError.eventNotFound
        }
        
        let rsvpId = "\(eventId)_\(currentUser.uid)"
        let rsvp = EventRSVP(
            eventId: eventId,
            userId: currentUser.uid,
            userDisplayName: displayName,
            status: status,
            notes: notes
        )
        
        // Handle waitlist logic for "going" RSVPs
        var finalRSVP = rsvp
        if status == .going, let maxParticipants = event.maxParticipants {
            let currentCount = try await getCurrentParticipantCount(eventId: eventId)
            if currentCount >= maxParticipants && event.waitlistEnabled {
                finalRSVP.status = .waitlisted
                finalRSVP.waitlistPosition = try await getNextWaitlistPosition(eventId: eventId)
            }
        }
        
        // Save RSVP
        try await db.collection("eventRSVPs").document(rsvpId).setData(finalRSVP.toDictionary())
        
        // If the user RSVP'd as 'going' and the event already has a home game, add them to the game
        if finalRSVP.status == .going, event.isBanked, let gameId = event.linkedGameId {
            try await homeGameService.addPlayerToGame(gameId: gameId, userId: currentUser.uid, displayName: displayName)
        }
        
        // Update event participant count
        try await updateEventParticipantCount(eventId: eventId)
    }
    
    /// Update participant count for an event
    private func updateEventParticipantCount(eventId: String) async throws {
        let rsvpQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("status", isEqualTo: EventRSVP.RSVPStatus.going.rawValue)
            .getDocuments()
        
        let participantCount = rsvpQuery.documents.count
        
        try await db.collection("userEvents").document(eventId).updateData([
            "currentParticipants": participantCount,
            "updatedAt": Timestamp(date: Date())
        ])
        
        // Also refresh user events to update the UI
        try? await fetchUserEvents()
    }
    
    /// Get current participant count for an event
    private func getCurrentParticipantCount(eventId: String) async throws -> Int {
        let rsvpQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("status", isEqualTo: EventRSVP.RSVPStatus.going.rawValue)
            .getDocuments()
        
        return rsvpQuery.documents.count
    }
    
    /// Get next waitlist position
    private func getNextWaitlistPosition(eventId: String) async throws -> Int {
        let waitlistQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("status", isEqualTo: EventRSVP.RSVPStatus.waitlisted.rawValue)
            .order(by: "rsvpDate", descending: false) // Order by join date
            .getDocuments()
        
        return waitlistQuery.documents.count + 1
    }
    
    /// Cancel RSVP for an event
    func cancelRSVP(eventId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        let rsvpId = "\(eventId)_\(currentUser.uid)"
        
        // Get current RSVP to check status
        let rsvpDoc = try await db.collection("eventRSVPs").document(rsvpId).getDocument()
        guard let rsvpData = rsvpDoc.data(),
              let currentRSVP = try? EventRSVP(dictionary: rsvpData, id: rsvpId) else {
            throw UserEventServiceError.rsvpNotFound
        }
        
        // Delete the RSVP
        try await db.collection("eventRSVPs").document(rsvpId).delete()
        
        // If the cancelled user was "going", we need to promote someone from waitlist
        if currentRSVP.status == .going {
            try await promoteFromWaitlist(eventId: eventId)
        }
        
        // Update participant count
        try await updateEventParticipantCount(eventId: eventId)
    }
    
    /// Promote the next person from waitlist to going
    private func promoteFromWaitlist(eventId: String) async throws {
        // Get event to check if waitlist is enabled
        guard let event = try await fetchEvent(eventId: eventId), event.waitlistEnabled else {
            return
        }
        
        // Get the first person on waitlist (ordered by join date)
        let waitlistQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("status", isEqualTo: EventRSVP.RSVPStatus.waitlisted.rawValue)
            .order(by: "rsvpDate", descending: false) // First in, first promoted
            .limit(to: 1)
            .getDocuments()
        
        guard let firstInWaitlist = waitlistQuery.documents.first else {
            return // No one on waitlist
        }
        
        // Update their status to "going"
        try await db.collection("eventRSVPs").document(firstInWaitlist.documentID).updateData([
            "status": EventRSVP.RSVPStatus.going.rawValue,
            "waitlistPosition": FieldValue.delete() // Remove waitlist position
        ])
        
        // Update waitlist positions for remaining people
        try await updateWaitlistPositions(eventId: eventId)
    }
    
    /// Update waitlist positions after someone is promoted or leaves
    private func updateWaitlistPositions(eventId: String) async throws {
        let waitlistQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("status", isEqualTo: EventRSVP.RSVPStatus.waitlisted.rawValue)
            .order(by: "rsvpDate", descending: false) // Order by join date
            .getDocuments()
        
        let batch = db.batch()
        
        for (index, doc) in waitlistQuery.documents.enumerated() {
            let newPosition = index + 1
            batch.updateData(["waitlistPosition": newPosition], forDocument: doc.reference)
        }
        
        try await batch.commit()
    }
    
    /// Get waitlist for an event
    func getEventWaitlist(eventId: String) async throws -> [EventRSVP] {
        let waitlistQuery = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("status", isEqualTo: EventRSVP.RSVPStatus.waitlisted.rawValue)
            .order(by: "rsvpDate", descending: false) // Order by join date
            .getDocuments()
        
        var waitlist: [EventRSVP] = []
        
        for document in waitlistQuery.documents {
            let data = document.data()
            if let rsvp = try? EventRSVP(dictionary: data, id: document.documentID) {
                waitlist.append(rsvp)
            }
        }
        
        return waitlist
    }
    
    // MARK: - Invitation Management
    
    /// Invite users from a group to an event
    func inviteGroupToEvent(eventId: String, groupId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Check if user owns the event
        guard let event = try await fetchEvent(eventId: eventId),
              event.creatorId == currentUser.uid else {
            throw UserEventServiceError.permissionDenied
        }
        
        // Get current user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let inviterName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Get all group members
        let membersQuery = try await db.collection("groups")
            .document(groupId)
            .collection("members")
            .getDocuments()
        
        // Create invites for each member (except the creator)
        let batch = db.batch()
        
        for memberDoc in membersQuery.documents {
            let memberId = memberDoc.documentID
            if memberId != currentUser.uid { // Don't invite yourself
                let invite = EventInvite(
                    eventId: eventId,
                    inviterId: currentUser.uid,
                    inviterName: inviterName,
                    inviteeId: memberId,
                    inviteMethod: .group
                )
                
                let inviteRef = db.collection("eventInvites").document(invite.id)
                batch.setData(invite.toDictionary(), forDocument: inviteRef)
            }
        }
        
        try await batch.commit()
    }
    
    /// Invite specific users to an event
    func inviteUsersToEvent(eventId: String, userIds: [String]) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Check if user owns the event
        guard let event = try await fetchEvent(eventId: eventId),
              event.creatorId == currentUser.uid else {
            throw UserEventServiceError.permissionDenied
        }
        
        // Get current user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let inviterName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Create invites for each user
        let batch = db.batch()
        
        for userId in userIds {
            if userId != currentUser.uid { // Don't invite yourself
                let invite = EventInvite(
                    eventId: eventId,
                    inviterId: currentUser.uid,
                    inviterName: inviterName,
                    inviteeId: userId,
                    inviteMethod: .direct
                )
                
                let inviteRef = db.collection("eventInvites").document(invite.id)
                batch.setData(invite.toDictionary(), forDocument: inviteRef)
            }
        }
        
        try await batch.commit()
    }
    
    /// Fetch pending event invites for current user
    func fetchPendingEventInvites() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let querySnapshot = try await db.collection("eventInvites")
            .whereField("inviteeId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: EventInvite.InviteStatus.pending.rawValue)
            .order(by: "sentAt", descending: true)
            .getDocuments()
        
        var invites: [EventInvite] = []
        
        for document in querySnapshot.documents {
            let data = document.data()
            if let invite = try? EventInvite(dictionary: data, id: document.documentID) {
                invites.append(invite)
            }
        }
        
        self.pendingInvites = invites
    }
    
    /// Accept an event invite
    func acceptEventInvite(inviteId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Get the invite
        let inviteDoc = try await db.collection("eventInvites").document(inviteId).getDocument()
        guard let inviteData = inviteDoc.data(),
              let invite = try? EventInvite(dictionary: inviteData, id: inviteId),
              invite.inviteeId == currentUser.uid else {
            throw UserEventServiceError.inviteNotFound
        }
        
        // Update invite status
        try await db.collection("eventInvites").document(inviteId).updateData([
            "status": EventInvite.InviteStatus.accepted.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
        
        // Automatically RSVP as "going"
        try await rsvpToEvent(eventId: invite.eventId, status: .going)
        
        // Remove from pending invites
        self.pendingInvites.removeAll { $0.id == inviteId }
    }
    
    /// Decline an event invite
    func declineEventInvite(inviteId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Get the invite
        let inviteDoc = try await db.collection("eventInvites").document(inviteId).getDocument()
        guard let inviteData = inviteDoc.data(),
              let invite = try? EventInvite(dictionary: inviteData, id: inviteId),
              invite.inviteeId == currentUser.uid else {
            throw UserEventServiceError.inviteNotFound
        }
        
        // Update invite status
        try await db.collection("eventInvites").document(inviteId).updateData([
            "status": EventInvite.InviteStatus.declined.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
        
        // Remove from pending invites
        self.pendingInvites.removeAll { $0.id == inviteId }
    }
    
    /// Fetch user's RSVP for a specific event
    func fetchUserRSVP(eventId: String, userId: String) async throws -> EventRSVP? {
        let rsvpId = "\(eventId)_\(userId)"
        let docSnapshot = try await db.collection("eventRSVPs").document(rsvpId).getDocument()
        
        guard docSnapshot.exists, let data = docSnapshot.data() else {
            return nil
        }
        
        return try EventRSVP(dictionary: data, id: rsvpId)
    }
    
    /// Fetch all RSVPs for a specific event
    func fetchEventRSVPs(eventId: String) async throws -> [EventRSVP] {
        let querySnapshot = try await db.collection("eventRSVPs")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()
        
        var rsvps: [EventRSVP] = []
        
        for document in querySnapshot.documents {
            let data = document.data()
            if let rsvp = try? EventRSVP(dictionary: data, id: document.documentID) {
                rsvps.append(rsvp)
            }
        }
        
        return rsvps
    }
    
    // MARK: - Public Event RSVP Management
    
    /// RSVP to a public event (from enhanced_events collection)
    func rsvpToPublicEvent(publicEventId: String, eventName: String, eventDate: Date, status: PublicEventRSVP.RSVPStatus) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        // Get user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        let rsvp = PublicEventRSVP(
            publicEventId: publicEventId,
            userId: currentUser.uid,
            userDisplayName: displayName,
            status: status,
            eventName: eventName,
            eventDate: eventDate
        )
        
        // Save RSVP to publicEventRSVPs collection
        try await db.collection("publicEventRSVPs").document(rsvp.id).setData(rsvp.toDictionary())
        
        // Update local state
        await MainActor.run {
            if let index = self.publicEventRSVPs.firstIndex(where: { $0.publicEventId == publicEventId }) {
                self.publicEventRSVPs[index] = rsvp
            } else {
                self.publicEventRSVPs.append(rsvp)
            }
        }
    }
    
    /// Cancel RSVP to a public event
    func cancelPublicEventRSVP(publicEventId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        let rsvpId = "\(publicEventId)_\(currentUser.uid)"
        
        // Delete the RSVP
        try await db.collection("publicEventRSVPs").document(rsvpId).delete()
        
        // Update local state
        await MainActor.run {
            self.publicEventRSVPs.removeAll { $0.publicEventId == publicEventId }
        }
    }
    
    /// Fetch user's RSVP for a specific public event
    func fetchPublicEventRSVP(publicEventId: String, userId: String) async throws -> PublicEventRSVP? {
        let rsvpId = "\(publicEventId)_\(userId)"
        let docSnapshot = try await db.collection("publicEventRSVPs").document(rsvpId).getDocument()
        
        guard docSnapshot.exists, let data = docSnapshot.data() else {
            return nil
        }
        
        return try PublicEventRSVP(dictionary: data, id: rsvpId)
    }
    
    /// Fetch all public event RSVPs for current user
    func fetchPublicEventRSVPs() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw UserEventServiceError.notAuthenticated
        }
        
        let querySnapshot = try await db.collection("publicEventRSVPs")
            .whereField("userId", isEqualTo: currentUser.uid)
            .order(by: "eventDate", descending: false)
            .getDocuments()
        
        var rsvps: [PublicEventRSVP] = []
        
        for document in querySnapshot.documents {
            let data = document.data()
            if let rsvp = try? PublicEventRSVP(dictionary: data, id: document.documentID) {
                rsvps.append(rsvp)
            }
        }
        
        await MainActor.run {
            self.publicEventRSVPs = rsvps
        }
    }
    
    /// Fetch all RSVPs for a specific public event
    func fetchPublicEventRSVPs(publicEventId: String) async throws -> [PublicEventRSVP] {
        let querySnapshot = try await db.collection("publicEventRSVPs")
            .whereField("publicEventId", isEqualTo: publicEventId)
            .getDocuments()
        
        var rsvps: [PublicEventRSVP] = []
        
        for document in querySnapshot.documents {
            let data = document.data()
            if let rsvp = try? PublicEventRSVP(dictionary: data, id: document.documentID) {
                rsvps.append(rsvp)
            }
        }
        
        return rsvps
    }
    
    // MARK: - Real-time Updates
    
    /// Listen for real-time updates to an event
    func listenForEventUpdates(eventId: String, onChange: @escaping (UserEvent) -> Void) {
        stopListeningForEventUpdates(eventId: eventId)
        
        let listener = db.collection("userEvents").document(eventId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else { return }
                
                Task {
                    await self._processEventUpdate(eventId: eventId, document: document, onChange: onChange)
                }
            }
        
        eventListeners[eventId] = listener
    }
    
    /// Stop listening for updates to a specific event
    func stopListeningForEventUpdates(eventId: String) {
        if let listener = eventListeners[eventId] {
            listener.remove()
            eventListeners.removeValue(forKey: eventId)
        }
    }
    
    /// Stop all active listeners
    func stopListeningForEventUpdates() {
        for (_, listener) in eventListeners {
            listener.remove()
        }
        eventListeners.removeAll()
    }
    
    /// Begin listening for changes to events the current user owns or is RSVP'd to
    func startMyEventsListeners() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        stopMyEventsListeners()

        // Listener for events user CREATED
        myEventsListener = db.collection("userEvents")
            .whereField("creatorId", isEqualTo: uid)
            .addSnapshotListener { [weak self] _, _ in
                Task { try? await self?.fetchUserEvents() }
            }

        // Listener for RSVPs involving this user
        myRSVPListener = db.collection("eventRSVPs")
            .whereField("userId", isEqualTo: uid)
            .whereField("status", in: ["going","maybe","waitlisted"])
            .addSnapshotListener { [weak self] _, _ in
                Task { try? await self?.fetchUserEvents() }
            }
        
        // Listener for pending invites
        invitesListener = db.collection("eventInvites")
            .whereField("inviteeId", isEqualTo: uid)
            .whereField("status", isEqualTo: EventInvite.InviteStatus.pending.rawValue)
            .addSnapshotListener { [weak self] _, _ in
                Task { try? await self?.fetchPendingEventInvites() }
            }
        
        // Note: Status updates happen on-demand via currentStatus computed property
    }

    /// Stop the above listeners
    func stopMyEventsListeners() {
        myEventsListener?.remove(); myEventsListener = nil
        myRSVPListener?.remove();  myRSVPListener = nil
        invitesListener?.remove(); invitesListener = nil
    }
    
    private func _processEventUpdate(eventId: String, document: DocumentSnapshot, onChange: @escaping (UserEvent) -> Void) {
        guard document.exists, let data = document.data() else { return }
        
        do {
            if let event = try? UserEvent(dictionary: data, id: eventId) {
                onChange(event)
            }
        } catch {
            // Handle parsing error
        }
    }
}

// MARK: - Error Handling

enum UserEventServiceError: Error, CustomStringConvertible {
    case notAuthenticated
    case eventNotFound
    case permissionDenied
    case inviteNotFound
    case rsvpNotFound
    case eventFull
    case invalidData
    
    var description: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .eventNotFound:
            return "Event not found"
        case .permissionDenied:
            return "Permission denied"
        case .inviteNotFound:
            return "Invite not found"
        case .rsvpNotFound:
            return "RSVP not found"
        case .eventFull:
            return "Event is full"
        case .invalidData:
            return "Invalid data"
        }
    }
    
    var message: String {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to perform this action"
        case .eventNotFound:
            return "The event could not be found"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .inviteNotFound:
            return "The invite could not be found"
        case .rsvpNotFound:
            return "Your RSVP could not be found"
        case .eventFull:
            return "This event is full. You can join the waitlist if available."
        case .invalidData:
            return "Invalid data provided"
        }
    }
} 