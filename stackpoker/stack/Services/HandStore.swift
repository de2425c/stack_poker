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
    
    func saveHand(_ hand: ParsedHandHistory) async throws {
        let data = try JSONEncoder().encode(hand)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        try await db.collection("users")
            .document(userId)
            .collection("hands")
            .addDocument(data: [
                "hand": dict,
                "timestamp": FieldValue.serverTimestamp()
            ])
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
                    return SavedHand(
                        id: document.documentID,
                        hand: hand,
                        timestamp: timestamp.dateValue()
                    )
                }
                
                print("Loaded \(self?.savedHands.count ?? 0) hands")
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
} 