import Foundation
import FirebaseFirestore
import Combine

@MainActor
class PublicSessionService: ObservableObject {
    @Published var liveSessions: [PublicLiveSession] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 10
    
    // MARK: - Fetch Public Live Sessions for Feed
    
    func fetchPublicSessions() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let query = db.collection("public_sessions")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            liveSessions = sessions
            lastDocument = snapshot.documents.last
            
            print("[PublicSessionService] Fetched \(sessions.count) public sessions")
        } catch {
            print("[PublicSessionService] Error fetching public sessions: \(error)")
            throw error
        }
    }
    
    // MARK: - Fetch More Sessions (Pagination)
    
    func fetchMoreSessions() async throws {
        guard let lastDoc = lastDocument else { return }
        
        do {
            let query = db.collection("public_sessions")
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let newSessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            liveSessions.append(contentsOf: newSessions)
            lastDocument = snapshot.documents.last
            
            print("[PublicSessionService] Fetched \(newSessions.count) more public sessions")
        } catch {
            print("[PublicSessionService] Error fetching more sessions: \(error)")
            throw error
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
    
    // MARK: - Fetch Live Sessions Only
    
    func fetchLiveSessions() async throws -> [PublicLiveSession] {
        do {
            let snapshot = try await db.collection("public_sessions")
                .whereField("isActive", isEqualTo: true)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            let sessions = snapshot.documents.compactMap { document -> PublicLiveSession? in
                return PublicLiveSession(id: document.documentID, document: document.data())
            }
            
            print("[PublicSessionService] Fetched \(sessions.count) live sessions")
            return sessions
        } catch {
            print("[PublicSessionService] Error fetching live sessions: \(error)")
            throw error
        }
    }
    
    // MARK: - Real-time Updates for Live Sessions
    
    func startListeningToLiveSessions() {
        db.collection("public_sessions")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[PublicSessionService] Error listening to live sessions: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    // Update existing live sessions in the list
                    for change in snapshot.documentChanges {
                        let session = PublicLiveSession(id: change.document.documentID, document: change.document.data())
                        
                        switch change.type {
                        case .added:
                            // Check if session is already in the list to avoid duplicates
                            if !self.liveSessions.contains(where: { $0.id == session.id }) {
                                self.liveSessions.insert(session, at: 0)
                            }
                        case .modified:
                            if let index = self.liveSessions.firstIndex(where: { $0.id == session.id }) {
                                self.liveSessions[index] = session
                            }
                        case .removed:
                            self.liveSessions.removeAll { $0.id == session.id }
                        }
                    }
                }
            }
    }
    
    // MARK: - Force Refresh
    
    func forceRefresh() async throws {
        lastDocument = nil
        try await fetchPublicSessions()
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
} 