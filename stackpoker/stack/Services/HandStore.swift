import Foundation
import FirebaseFirestore

class HandStore: ObservableObject {
    @Published var savedHands: [SavedHand] = []
    @Published var sharedHands: [String: SavedHand] = [:] // Cache for shared hands from other users
    let userId: String
    private let db = Firestore.firestore()
    
    init(userId: String) {
        self.userId = userId
        loadSavedHands()
    }
    
    func saveHand(_ hand: ParsedHandHistory, sessionId: String? = nil) async throws {
        let data = try JSONEncoder().encode(hand)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        var docData: [String: Any] = [
            "hand": dict,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        // Add sessionId if provided
        if let sessionId = sessionId {
            docData["sessionId"] = sessionId
        }
        
        try await db.collection("users")
            .document(userId)
            .collection("hands")
            .addDocument(data: docData)
    }
    
    func loadSavedHands() {
        db.collection("users")
            .document(userId)
            .collection("hands")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching hands: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                self?.savedHands = documents.compactMap { document in
                    guard let dict = document.data()["hand"] as? [String: Any],
                          let data = try? JSONSerialization.data(withJSONObject: dict),
                          let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: data),
                          let timestamp = document.data()["timestamp"] as? Timestamp
                    else {
                        print("Error decoding hand from document: \(document.documentID)")
                        return nil
                    }
                    
                    let sessionId = document.data()["sessionId"] as? String
                    
                    var savedHand = SavedHand(
                        id: document.documentID,
                        hand: hand,
                        timestamp: timestamp.dateValue()
                    )
                    
                    // Set the sessionId if available
                    savedHand.sessionId = sessionId
                    
                    return savedHand
                }
                
                print("Loaded \(self?.savedHands.count ?? 0) total hands for user")
            }
    }
    
    func deleteHand(id: String) async throws {
        // Delete the hand document from Firestore
        try await db.collection("users")
            .document(userId)
            .collection("hands")
            .document(id)
            .delete()
        
        // Update the local state by removing the deleted hand
        DispatchQueue.main.async {
            self.savedHands.removeAll { $0.id == id }
        }
    }
    
    // Fetch a hand by ID from any user
    func fetchSharedHand(handId: String, ownerUserId: String? = nil) async throws -> SavedHand? {
        print("HAND STORE: Fetching shared hand \(handId)")
        
        // Check if we already have this hand in our cache
        if let cachedHand = sharedHands[handId] {
            print("HAND STORE: Found hand in cache")
            return cachedHand
        }
        
        // If ownerUserId is provided, search that user's collection
        // Otherwise, we need to query across all users (more expensive)
        if let ownerUserId = ownerUserId {
            // Get the hand document
            let handDoc = try await db.collection("users")
                .document(ownerUserId)
                .collection("hands")
                .document(handId)
                .getDocument()
                
            if !handDoc.exists {
                print("HAND STORE: Hand not found for user \(ownerUserId)")
                return nil
            }
            
            guard let handData = handDoc.data(),
                  let dict = handData["hand"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: data),
                  let timestamp = handData["timestamp"] as? Timestamp
            else {
                print("HAND STORE: Failed to decode hand data")
                return nil
            }
            
            let savedHand = SavedHand(
                id: handDoc.documentID,
                hand: hand,
                timestamp: timestamp.dateValue()
            )
            
            // Cache the result
            await MainActor.run {
                sharedHands[handId] = savedHand
            }
            
            return savedHand
        } else {
            // This is a more expensive operation - searching across all users
            // We'll need to query a global database of hands or use a different approach
            // For now, we'll just search in the current user's hands
            if let localHand = savedHands.first(where: { $0.id == handId }) {
                return localHand
            }
            
            // If we haven't found it, we could implement a more comprehensive search across users
            print("HAND STORE: Hand not found and no owner ID provided")
            return nil
        }
    }
    
    // Method to fetch a specific hand by its ID for the current user
    func fetchHandById(_ handId: String) async -> SavedHand? {
        // Check local cache first
        if let cachedHand = self.savedHands.first(where: { $0.id == handId }) {
            return cachedHand
        }
        
        // If not in cache, fetch from Firestore
        do {
            let document = try await db.collection("users")
                                      .document(userId)
                                      .collection("hands")
                                      .document(handId)
                                      .getDocument()
            
            if document.exists,
               let data = document.data(),
               let dict = data["hand"] as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: dict),
               let handDetail = try? JSONDecoder().decode(ParsedHandHistory.self, from: jsonData),
               let timestamp = data["timestamp"] as? Timestamp {
                
                var savedHand = SavedHand(id: document.documentID,
                                          hand: handDetail,
                                          timestamp: timestamp.dateValue())
                savedHand.sessionId = data["sessionId"] as? String
                return savedHand
            } else {
                print("HandStore: Document \(handId) does not exist or failed to decode.")
                return nil
            }
        } catch {
            print("HandStore: Error fetching hand by ID \(handId): \(error.localizedDescription)")
            return nil
        }
    }
    
    // New function to fetch hands for a specific session ID
    func fetchHands(forSessionId sessionId: String, completion: @escaping ([SavedHand]) -> Void) {
        guard !userId.isEmpty else {
            print("HandStore.fetchHands: User ID is empty, cannot fetch hands.")
            completion([])
            return
        }
        print("HandStore.fetchHands: Fetching hands for session ID [\(sessionId)] for user ID [\(self.userId)]")
        
        db.collection("users")
            .document(self.userId) // Explicitly use self.userId for clarity
            .collection("hands")
            .whereField("sessionId", isEqualTo: sessionId)
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("HandStore.fetchHands: Error fetching hands for session [\(sessionId)]: \(error.localizedDescription)")
                    // Check for specific Firestore errors like missing index
                    if let firestoreError = error as NSError? {
                        if firestoreError.domain == FirestoreErrorDomain && firestoreError.code == FirestoreErrorCode.failedPrecondition.rawValue {
                            print("HandStore.fetchHands: FIRESTORE PRECONDITION FAILED. This often indicates a missing index. Check the Firestore console for index suggestions for collection 'hands' with fields 'sessionId' and 'timestamp'.")
                        }
                    }
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("HandStore.fetchHands: Snapshot was nil, or no documents found for session [\(sessionId)] (even if snapshot wasn't nil).")
                    completion([])
                    return
                }
                
                print("HandStore.fetchHands: Query successful. Found \(documents.count) raw documents for session [\(sessionId)]. Processing them...")
                
                if documents.isEmpty {
                    print("HandStore.fetchHands: No hand documents specifically matched sessionId [\(sessionId)] after query.")
                    completion([])
                    return
                }

                let handsForSession = documents.compactMap { document -> SavedHand? in
                    print("HandStore.fetchHands: Processing document ID [\(document.documentID)]")
                    let documentData = document.data()
                    print("HandStore.fetchHands: Document data: \(documentData)")

                    guard let dict = documentData["hand"] as? [String: Any] else {
                        print("HandStore.fetchHands: Failed to extract 'hand' dictionary from document [\(document.documentID)]. 'hand' field was: \(String(describing: documentData["hand"]))")
                        return nil
                    }
                    
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
                        print("HandStore.fetchHands: Failed to serialize 'hand' dictionary to JSON data for document [\(document.documentID)].")
                        return nil
                    }
                    
                    guard let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: data) else {
                        print("HandStore.fetchHands: Failed to decode ParsedHandHistory from JSON data for document [\(document.documentID)].")
                        return nil
                    }
                    
                    guard let timestamp = documentData["timestamp"] as? Timestamp else {
                        print("HandStore.fetchHands: Failed to extract 'timestamp' as Timestamp from document [\(document.documentID)]. 'timestamp' field was: \(String(describing: documentData["timestamp"]))")
                        return nil
                    }
                    
                    // sessionId field is confirmed by the whereField query, but let's log what's in the doc
                    let docSessionId = documentData["sessionId"] as? String ?? "MISSING/NIL"
                    print("HandStore.fetchHands: Document [\(document.documentID)] has sessionId in data: [\(docSessionId)]")

                    var savedHand = SavedHand(
                        id: document.documentID,
                        hand: hand,
                        timestamp: timestamp.dateValue()
                    )
                    // We are querying for this specific sessionId, so we can confidently assign it.
                    savedHand.sessionId = sessionId 
                    print("HandStore.fetchHands: Successfully decoded hand [\(savedHand.id)] for session [\(sessionId)].")
                    return savedHand
                }
                
                print("HandStore.fetchHands: Finished processing. Decoded \(handsForSession.count) hands for session [\(sessionId)]")
                completion(handsForSession)
            }
    }
} 