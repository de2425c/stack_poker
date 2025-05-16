import Foundation
import FirebaseFirestore

class CashGameService: ObservableObject {
    @Published var cashGames: [CashGame] = []
    private let db = Firestore.firestore()
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
        print("CashGameService initialized with userId: \(userId)")
        fetchCashGames()
    }
    
    func fetchCashGames() {
        print("Fetching cash games for userId: \(userId)")
        db.collection("cashGames")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching cash games: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found in cashGames collection")
                    return
                }
                
                print("Found \(documents.count) cash games")
                self?.cashGames = documents.compactMap { document in
                    if let game = CashGame(dictionary: document.data()) {
                        print("Successfully parsed game: \(game.name) - \(game.stakes)")
                        return game
                    } else {
                        print("Failed to parse game from document: \(document.data())")
                        return nil
                    }
                }
                
                print("Updated cashGames array with \(self?.cashGames.count ?? 0) games")
            }
    }
    
    func addCashGame(name: String, smallBlind: Double, bigBlind: Double, straddle: Double? = nil, location: String? = nil) async throws {
        print("Adding new cash game: \(name) - \(smallBlind)/\(bigBlind)")
        let game = CashGame(
            userId: userId,
            name: name,
            smallBlind: smallBlind,
            bigBlind: bigBlind,
            straddle: straddle,
            location: location
        )
        try await db.collection("cashGames").document(game.id).setData(game.dictionary)
        print("Successfully added game to Firebase")
    }
    
    func deleteCashGame(_ game: CashGame) async throws {
        print("Deleting cash game: \(game.name) - \(game.stakes)")
        try await db.collection("cashGames").document(game.id).delete()
        print("Successfully deleted game from Firebase")
    }
} 