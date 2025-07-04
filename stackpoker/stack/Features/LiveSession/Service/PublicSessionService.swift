import Foundation
import FirebaseFirestore
import Combine

@MainActor
class PublicSessionService: ObservableObject {
    @Published var liveSessions: [PublicLiveSession] = []
    @Published var liveStorySessions: [PublicLiveSession] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 10
    
    // Add properties to track filtering context
    private var currentUserId: String?
    private var followersOnly: Bool = false
    private var liveSessionsListener: ListenerRegistration?
    private var liveStorySessionsListener: ListenerRegistration?
    
    // MARK: - Fetch Public Live Sessions for Feed (Followers Only)
    
    func fetchPublicSessions(currentUserId: String? = nil, followersOnly: Bool = false) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Store context for real-time filtering
        self.currentUserId = currentUserId
        self.followersOnly = followersOnly
        
        do {
            let query = db.collection("public_sessions")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            var sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            // Filter by follower relationships if requested
            if followersOnly, let currentUserId = currentUserId {
                sessions = try await filterSessionsByFollowing(sessions: sessions, currentUserId: currentUserId)
            }
            
            liveSessions = sessions
            lastDocument = snapshot.documents.last
            
            print("[PublicSessionService] Fetched \(sessions.count) public sessions (followersOnly: \(followersOnly))")
        } catch {
            print("[PublicSessionService] Error fetching public sessions: \(error)")
            throw error
        }
    }
    
    // MARK: - Fetch More Sessions (Pagination with Privacy)
    
    func fetchMoreSessions(currentUserId: String? = nil, followersOnly: Bool = false) async throws {
        guard let lastDoc = lastDocument else { return }
        
        do {
            let query = db.collection("public_sessions")
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            var newSessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            // Filter by follower relationships if requested
            if followersOnly, let currentUserId = currentUserId {
                newSessions = try await filterSessionsByFollowing(sessions: newSessions, currentUserId: currentUserId)
            }
            
            liveSessions.append(contentsOf: newSessions)
            lastDocument = snapshot.documents.last
            
            print("[PublicSessionService] Fetched \(newSessions.count) more public sessions (followersOnly: \(followersOnly))")
        } catch {
            print("[PublicSessionService] Error fetching more sessions: \(error)")
            throw error
        }
    }
    
    // MARK: - Privacy Filtering Helper
    
    private func filterSessionsByFollowing(sessions: [PublicLiveSession], currentUserId: String) async throws -> [PublicLiveSession] {
        // Get list of users the current user is following
        let followingQuery = db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
        
        let followingSnapshot = try await followingQuery.getDocuments()
        let followingUserIds = Set(followingSnapshot.documents.compactMap { doc in
            doc.data()["followeeId"] as? String
        })
        
        // Add current user's own sessions (users can see their own public sessions)
        var allowedUserIds = followingUserIds
        allowedUserIds.insert(currentUserId)
        
        // Filter sessions to only include those from followed users or own sessions
        let filteredSessions = sessions.filter { session in
            allowedUserIds.contains(session.userId)
        }
        
        print("[PublicSessionService] Filtered \(sessions.count) sessions to \(filteredSessions.count) based on following relationships")
        return filteredSessions
    }
    
    // MARK: - Check if session should be visible to current user
    
    private func isSessionVisibleToUser(_ session: PublicLiveSession, currentUserId: String) async -> Bool {
        // Always show own sessions
        if session.userId == currentUserId {
            return true
        }
        
        // Check if current user follows the session owner
        let followingQuery = db.collection("userFollows")
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followeeId", isEqualTo: session.userId)
            .limit(to: 1)
        
        do {
            let snapshot = try await followingQuery.getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            print("[PublicSessionService] Error checking follow relationship: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch User's Public Sessions
    
    func fetchUserSessions(userId: String) async throws -> [PublicLiveSession] {
        print("🔍 [PublicSessionService] Fetching sessions for userId: \(userId)")
        do {
            let snapshot = try await db.collection("public_sessions")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            print("📊 [PublicSessionService] Found \(snapshot.documents.count) documents for user \(userId)")
            
            let sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                let session = PublicLiveSession(id: document.documentID, document: document.data())
                print("📝 [PublicSessionService] Processing session: \(session.id), type: \(session.sessionType), game: \(session.gameName)")
                return session
            }
            
            print("✅ [PublicSessionService] Successfully parsed \(sessions.count) sessions for user \(userId)")
            return sessions
        } catch {
            print("❌ [PublicSessionService] Error fetching user sessions: \(error)")
            throw error
        }
    }
    
    // MARK: - Fetch Live Sessions Only (with Privacy)
    
    func fetchLiveSessions(currentUserId: String? = nil, followersOnly: Bool = false) async throws -> [PublicLiveSession] {
        do {
            let snapshot = try await db.collection("public_sessions")
                .whereField("isActive", isEqualTo: true)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            var sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            // Filter by follower relationships if requested
            if followersOnly, let currentUserId = currentUserId {
                sessions = try await filterSessionsByFollowing(sessions: sessions, currentUserId: currentUserId)
            }
            
            print("[PublicSessionService] Fetched \(sessions.count) live sessions (followersOnly: \(followersOnly))")
            return sessions
        } catch {
            print("[PublicSessionService] Error fetching live sessions: \(error)")
            throw error
        }
    }
    
    // MARK: - Real-time Updates for Live Sessions (Updated with Privacy)
    
    func startListeningToLiveSessions(currentUserId: String? = nil, followersOnly: Bool = false) {
        // Stop any existing listener
        stopListeningToLiveSessions()
        
        // Store context for filtering
        self.currentUserId = currentUserId
        self.followersOnly = followersOnly
        
        liveSessionsListener = db.collection("public_sessions")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[PublicSessionService] Error listening to live sessions: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    // Process document changes with privacy filtering
                    for change in snapshot.documentChanges {
                        let session = PublicLiveSession(id: change.document.documentID, document: change.document.data())
                        
                        switch change.type {
                        case .added:
                            // Check privacy before adding
                            if await self.shouldIncludeSessionInFeed(session) {
                                // Check if session is already in the list to avoid duplicates
                                if !self.liveSessions.contains(where: { $0.id == session.id }) {
                                    self.liveSessions.insert(session, at: 0)
                                    print("[PublicSessionService] Added live session to feed: \(session.id)")
                                }
                            } else {
                                print("[PublicSessionService] Filtered out live session: \(session.id) (privacy)")
                            }
                            
                        case .modified:
                            // Check if we should keep this session in the feed
                            if await self.shouldIncludeSessionInFeed(session) {
                                if let index = self.liveSessions.firstIndex(where: { $0.id == session.id }) {
                                    self.liveSessions[index] = session
                                    print("[PublicSessionService] Updated live session in feed: \(session.id)")
                                } else {
                                    // Session wasn't in feed but now should be (maybe user started following)
                                    self.liveSessions.insert(session, at: 0)
                                    print("[PublicSessionService] Added previously filtered session to feed: \(session.id)")
                                }
                            } else {
                                // Remove from feed if it's there but no longer should be visible
                                self.liveSessions.removeAll { $0.id == session.id }
                                print("[PublicSessionService] Removed session from feed due to privacy: \(session.id)")
                            }
                            
                        case .removed:
                            self.liveSessions.removeAll { $0.id == session.id }
                            print("[PublicSessionService] Removed ended session from feed: \(session.id)")
                        }
                    }
                }
            }
    }
    
    // MARK: - Stop real-time listener
    
    func stopListeningToLiveSessions() {
        liveSessionsListener?.remove()
        liveSessionsListener = nil
    }
    
    // MARK: - Real-time Updates for Live Story Sessions
    
    func startListeningToLiveStorySessions(currentUserId: String) {
        // Stop any existing listener
        stopListeningToLiveStorySessions()
        
        // Store context for filtering
        self.currentUserId = currentUserId
        
        liveStorySessionsListener = db.collection("public_sessions")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[PublicSessionService] Error listening to live story sessions: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    var sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                        return PublicLiveSession(id: document.documentID, document: document.data())
                    }
                    
                    // Filter by follower relationships
                    do {
                        sessions = try await self.filterSessionsByFollowing(sessions: sessions, currentUserId: currentUserId)
                        
                        // Sort by most recent activity
                        sessions.sort { $0.lastUpdated > $1.lastUpdated }
                        
                        // Limit to 20 for stories
                        self.liveStorySessions = Array(sessions.prefix(20))
                        
                        print("[PublicSessionService] Updated live story sessions: \(self.liveStorySessions.count)")
                    } catch {
                        print("[PublicSessionService] Error filtering story sessions: \(error)")
                    }
                }
            }
    }
    
    func stopListeningToLiveStorySessions() {
        liveStorySessionsListener?.remove()
        liveStorySessionsListener = nil
    }
    
    // MARK: - Privacy check helper for real-time updates
    
    private func shouldIncludeSessionInFeed(_ session: PublicLiveSession) async -> Bool {
        // If not using follower filtering, include all sessions
        guard followersOnly, let currentUserId = currentUserId else {
            return true
        }
        
        // Always include own sessions
        if session.userId == currentUserId {
            return true
        }
        
        // Check if user follows the session owner
        return await isSessionVisibleToUser(session, currentUserId: currentUserId)
    }
    
    // MARK: - Force Refresh
    
    func forceRefresh(currentUserId: String? = nil, followersOnly: Bool = false) async throws {
        // Clear current sessions and reset pagination
        liveSessions = []
        lastDocument = nil
        
        // Store context for filtering
        self.currentUserId = currentUserId
        self.followersOnly = followersOnly
        
        try await fetchPublicSessions(currentUserId: currentUserId, followersOnly: followersOnly)
        
        // Also refresh story sessions
        if let currentUserId = currentUserId {
            liveStorySessions = try await fetchLiveSessionsForStories(currentUserId: currentUserId)
        }
    }
    
    // MARK: - Get Specific Session
    
    func getSession(id: String) async throws -> PublicLiveSession? {
        do {
            let document = try await db.collection("public_sessions").document(id).getDocument()
            
            guard document.exists, let data = document.data() else {
                return nil
            }
            
            return PublicLiveSession(id: document.documentID, document: data)
        } catch {
            print("[PublicSessionService] Error getting session \(id): \(error)")
            throw error
        }
    }
    
    // MARK: - Fetch Live Sessions for Stories (Only Live/Active Sessions)
    
    func fetchLiveSessionsForStories(currentUserId: String) async throws -> [PublicLiveSession] {
        do {
            let snapshot = try await db.collection("public_sessions")
                .whereField("isActive", isEqualTo: true)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 20) // Limit to 20 for stories
                .getDocuments()
            
            var sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            // Filter by follower relationships
            sessions = try await filterSessionsByFollowing(sessions: sessions, currentUserId: currentUserId)
            
            print("[PublicSessionService] Fetched \(sessions.count) live sessions for stories")
            return sessions
        } catch {
            print("[PublicSessionService] Error fetching live sessions for stories: \(error)")
            throw error
        }
    }
} 