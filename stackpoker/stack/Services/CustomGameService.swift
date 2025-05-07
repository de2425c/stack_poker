import Foundation
import FirebaseFirestore

class CustomGameService: ObservableObject {
    @Published var customGames: [CustomGame] = []
    private let db = Firestore.firestore()
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
        print("CustomGameService initialized with userId: \(userId)")
        fetchCustomGames()
    }
    
    func fetchCustomGames() {
        print("Fetching custom games for userId: \(userId)")
        db.collection("customGames")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching custom games: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found in customGames collection")
                    return
                }
                
                print("Found \(documents.count) custom games")
                self?.customGames = documents.compactMap { document in
                    if let game = CustomGame(dictionary: document.data()) {
                        print("Successfully parsed game: \(game.name) - \(game.stakes)")
                        return game
                    } else {
                        print("Failed to parse game from document: \(document.data())")
                        return nil
                    }
                }
                
                print("Updated customGames array with \(self?.customGames.count ?? 0) games")
            }
    }
    
    func addCustomGame(name: String, stakes: String) async throws {
        print("Adding new custom game: \(name) - \(stakes)")
        let game = CustomGame(userId: userId, name: name, stakes: stakes)
        try await db.collection("customGames").document(game.id).setData(game.dictionary)
        print("Successfully added game to Firebase")
    }
    
    func deleteCustomGame(_ game: CustomGame) async throws {
        print("Deleting custom game: \(game.name) - \(game.stakes)")
        try await db.collection("customGames").document(game.id).delete()
        print("Successfully deleted game from Firebase")
    }
} 