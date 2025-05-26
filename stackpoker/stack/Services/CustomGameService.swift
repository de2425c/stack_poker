import Foundation
import FirebaseFirestore

class CustomGameService: ObservableObject {
    @Published var customGames: [CustomGame] = []
    private let db = Firestore.firestore()
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
        fetchCustomGames()
    }
    
    func fetchCustomGames() {
        db.collection("customGames")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    return
                }
                
                self?.customGames = documents.compactMap { document in
                    if let game = CustomGame(dictionary: document.data()) {
                        return game
                    } else {
                        return nil
                    }
                }
                
            }
    }
    
    func addCustomGame(name: String, stakes: String) async throws {
        let game = CustomGame(userId: userId, name: name, stakes: stakes)
        try await db.collection("customGames").document(game.id).setData(game.dictionary)
    }
    
    func deleteCustomGame(_ game: CustomGame) async throws {
        try await db.collection("customGames").document(game.id).delete()
    }
} 