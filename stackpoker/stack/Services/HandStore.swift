import Foundation
import FirebaseFirestore

@MainActor
class HandStore: ObservableObject {
    @Published var savedHands: [SavedHand] = []
    @Published var sharedHands: [String: SavedHand] = [:] // Cache for shared hands from other users
    let userId: String
    private let db = Firestore.firestore()
    
    // Computed property to get the most recent hand
    var mostRecentHand: SavedHand? {
        return savedHands.first // savedHands is already sorted by timestamp descending
    }
    
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
                // Error handling can be added here if needed
                Task { // Hop to the main actor to call the processing method
                    await self?.processHandDocuments(snapshot?.documents)
                }
            }
    }
    
    private func processHandDocuments(_ documents: [QueryDocumentSnapshot]?) {
        guard let documents = documents else {
            // Optionally handle the case where documents are nil, e.g., due to an error
            // For now, if documents are nil, we won't change savedHands
            return
        }
        
        self.savedHands = documents.compactMap { document in
            guard let dict = document.data()["hand"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: data),
                  let timestamp = document.data()["timestamp"] as? Timestamp
            else {
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
    }
    
    func deleteHand(id: String) async throws {
        // Delete the hand document from Firestore
        try await db.collection("users")
            .document(userId)
            .collection("hands")
            .document(id)
            .delete()
        
        // Update the local state by removing the deleted hand
        self.savedHands.removeAll { $0.id == id }
    }
    
    // Fetch a hand by ID from any user
    func fetchSharedHand(handId: String, ownerUserId: String? = nil) async throws -> SavedHand? {

        
        // Check if we already have this hand in our cache
        if let cachedHand = sharedHands[handId] {

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

                return nil
            }
            
            guard let handData = handDoc.data(),
                  let dict = handData["hand"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: data),
                  let timestamp = handData["timestamp"] as? Timestamp
            else {

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

                return nil
            }
        } catch {

            return nil
        }
    }
    
    // New function to fetch hands for a specific session ID
    func fetchHands(forSessionId sessionId: String, completion: @escaping ([SavedHand]) -> Void) {
        guard !userId.isEmpty else {

            completion([])
            return
        }

        
        db.collection("users")
            .document(self.userId) // Explicitly use self.userId for clarity
            .collection("hands")
            .whereField("sessionId", isEqualTo: sessionId)
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {

                    // Check for specific Firestore errors like missing index
                    if let firestoreError = error as NSError? {
                        if firestoreError.domain == FirestoreErrorDomain && firestoreError.code == FirestoreErrorCode.failedPrecondition.rawValue {

                        }
                    }
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {

                    completion([])
                    return
                }
                

                
                if documents.isEmpty {

                    completion([])
                    return
                }

                let handsForSession = documents.compactMap { document -> SavedHand? in

                    let documentData = document.data()


                    guard let dict = documentData["hand"] as? [String: Any] else {

                        return nil
                    }
                    
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else {

                        return nil
                    }
                    
                    guard let hand = try? JSONDecoder().decode(ParsedHandHistory.self, from: data) else {

                        return nil
                    }
                    
                    guard let timestamp = documentData["timestamp"] as? Timestamp else {

                        return nil
                    }
                    
                    // sessionId field is confirmed by the whereField query, but let's log what's in the doc
                    // let docSessionId = documentData[\"sessionId\"] as? String ?? \"MISSING/NIL\"
                    // print(\"Document \(document.documentID) has session ID: \(docSessionId) (querying for \(sessionId))\")\n


                    var savedHand = SavedHand(
                        id: document.documentID,
                        hand: hand,
                        timestamp: timestamp.dateValue()
                    )
                    // We are querying for this specific sessionId, so we can confidently assign it.
                    savedHand.sessionId = sessionId 

                    return savedHand
                }
                

                completion(handsForSession)
            }
    }
} 