import Foundation
import Firebase
import FirebaseFirestore
import Combine
import FirebaseAuth

class HomeGameService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var activeGames: [HomeGame] = []
    @Published var isLoading = false
    
    private var gameListeners: [String: ListenerRegistration] = [:]
    
    // MARK: - Real-time Updates
    
    /// Listen for real-time updates to a game
    func listenForGameUpdates(gameId: String, onChange: @escaping (HomeGame) -> Void) {
        // If we already have a listener for this game, remove it
        stopListeningForGameUpdates(gameId: gameId)
        
        // Create a new listener
        let listener = db.collection("homeGames").document(gameId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else {
                    print("Error listening for game updates: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                guard document.exists, let data = document.data() else {
                    print("Game document no longer exists")
                    return
                }
                
                do {
                    if let game = try? self.parseHomeGame(data: data, id: gameId) {
                        onChange(game)
                    }
                } catch {
                    print("Error parsing game data: \(error.localizedDescription)")
                }
            }
        
        // Store the listener for later cleanup
        gameListeners[gameId] = listener
    }
    
    /// Stop listening for updates to a specific game
    func stopListeningForGameUpdates(gameId: String) {
        if let listener = gameListeners[gameId] {
            listener.remove()
            gameListeners.removeValue(forKey: gameId)
        }
    }
    
    /// Stop all active listeners
    func stopListeningForGameUpdates() {
        for (_, listener) in gameListeners {
            listener.remove()
        }
        gameListeners.removeAll()
    }
    
    // MARK: - Game Management
    
    /// Create a new home game
    func createHomeGame(title: String, groupId: String) async throws -> HomeGame {
        guard let currentUser =
            Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Create the game object
        let game = HomeGame(
            id: UUID().uuidString,
            title: title,
            createdAt: Date(),
            creatorId: currentUser.uid,
            creatorName: displayName,
            groupId: groupId,
            status: .active,
            players: [],
            buyInRequests: [],
            cashOutRequests: [],
            gameHistory: [
                HomeGame.GameEvent(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    eventType: .gameCreated,
                    userId: currentUser.uid,
                    userName: displayName,
                    amount: nil,
                    description: "Game created: \(title)"
                )
            ]
        )
        
        // Save to Firestore
        try await db.collection("homeGames").document(game.id).setData([
            "id": game.id,
            "title": game.title,
            "createdAt": Timestamp(date: game.createdAt),
            "creatorId": game.creatorId,
            "creatorName": game.creatorName,
            "groupId": game.groupId,
            "status": game.status.rawValue,
            "players": [],
            "buyInRequests": [],
            "cashOutRequests": [],
            "gameHistory": [
                [
                    "id": game.gameHistory[0].id,
                    "timestamp": Timestamp(date: game.gameHistory[0].timestamp),
                    "eventType": game.gameHistory[0].eventType.rawValue,
                    "userId": game.gameHistory[0].userId,
                    "userName": game.gameHistory[0].userName,
                    "description": game.gameHistory[0].description
                ]
            ]
        ])
        
        return game
    }
    
    /// End a game and process all active players
    func endGame(gameId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // First get the game and check ownership
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can end the game"])
        }
        
        // Process in transaction to prevent race conditions
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Mark all active players as cashed out
                var players = gameData["players"] as? [[String: Any]] ?? []
                let activePlayers = players.filter { ($0["status"] as? String) == HomeGame.Player.PlayerStatus.active.rawValue }
                
                var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                
                // For each active player, create a cash-out event
                for i in 0..<players.count {
                    if let status = players[i]["status"] as? String,
                       status == HomeGame.Player.PlayerStatus.active.rawValue {
                        // Mark player as cashed out
                        players[i]["status"] = HomeGame.Player.PlayerStatus.cashedOut.rawValue
                        players[i]["cashedOutAt"] = Timestamp(date: Date())
                        
                        // Get player info for event
                        if let userId = players[i]["userId"] as? String,
                           let displayName = players[i]["displayName"] as? String,
                           let currentStack = players[i]["currentStack"] as? Double {
                            
                            // Add cash-out event
                            let cashOutEvent: [String: Any] = [
                                "id": UUID().uuidString,
                                "timestamp": Timestamp(date: Date()),
                                "eventType": HomeGame.GameEvent.EventType.cashOut.rawValue,
                                "userId": userId,
                                "userName": displayName,
                                "amount": currentStack,
                                "description": "\(displayName) cashed out $\(Int(currentStack)) (game ended)"
                            ]
                            
                            gameHistory.append(cashOutEvent)
                        }
                    }
                }
                
                // Add game ended event
                let endEvent: [String: Any] = [
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "eventType": HomeGame.GameEvent.EventType.gameEnded.rawValue,
                    "userId": currentUser.uid,
                    "userName": game.creatorName,
                    "description": "Game ended: \(game.title)"
                ]
                
                gameHistory.append(endEvent)
                
                // Update the game status to completed
                transaction.updateData([
                    "players": players,
                    "gameHistory": gameHistory,
                    "status": HomeGame.GameStatus.completed.rawValue
                ], forDocument: gameRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    /// Fetch a specific home game by ID
    func fetchHomeGame(gameId: String) async throws -> HomeGame? {
        let docSnapshot = try await db.collection("homeGames").document(gameId).getDocument()
        
        guard docSnapshot.exists, let data = docSnapshot.data() else {
            return nil
        }
        
        return try parseHomeGame(data: data, id: gameId)
    }
    
    /// Fetch active home games for a specific group
    func fetchActiveGamesForGroup(groupId: String) async throws -> [HomeGame] {
        isLoading = true
        defer { isLoading = false }
        
        let querySnapshot = try await db.collection("homeGames")
            .whereField("groupId", isEqualTo: groupId)
            .whereField("status", isEqualTo: HomeGame.GameStatus.active.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        var games: [HomeGame] = []
        
        for document in querySnapshot.documents {
            let data = document.data()
            if let game = try? parseHomeGame(data: data, id: document.documentID) {
                games.append(game)
            }
        }
        
        DispatchQueue.main.async {
            self.activeGames = games
        }
        
        return games
    }
    
    // MARK: - Player Management
    
    /// Request to join a game with a buy-in
    func requestBuyIn(gameId: String, amount: Double) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Create the buy-in request
        let requestId = UUID().uuidString
        let request: [String: Any] = [
            "id": requestId,
            "userId": currentUser.uid,
            "displayName": displayName,
            "amount": amount,
            "requestedAt": Timestamp(date: Date()),
            "status": HomeGame.BuyInRequest.RequestStatus.pending.rawValue
        ]
        
        // Add the request to the game
        try await db.collection("homeGames").document(gameId).updateData([
            "buyInRequests": FieldValue.arrayUnion([request])
        ])
        
        // Add event to game history
        let event: [String: Any] = [
            "id": UUID().uuidString,
            "timestamp": Timestamp(date: Date()),
            "eventType": HomeGame.GameEvent.EventType.buyIn.rawValue,
            "userId": currentUser.uid,
            "userName": displayName,
            "amount": amount,
            "description": "\(displayName) requested buy-in of $\(Int(amount))"
        ]
        
        try await db.collection("homeGames").document(gameId).updateData([
            "gameHistory": FieldValue.arrayUnion([event])
        ])
    }
    
    /// Approve a buy-in request
    func approveBuyIn(gameId: String, requestId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // First get the game and check ownership
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can approve buy-ins"])
        }
        
        // Find the request
        guard let request = game.buyInRequests.first(where: { $0.id == requestId && $0.status == .pending }) else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Buy-in request not found"])
        }
        
        // Process in transaction to prevent race conditions
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Update the request status to approved
                var buyInRequests = gameData["buyInRequests"] as? [[String: Any]] ?? []
                for i in 0..<buyInRequests.count {
                    if let reqId = buyInRequests[i]["id"] as? String, reqId == requestId {
                        buyInRequests[i]["status"] = HomeGame.BuyInRequest.RequestStatus.approved.rawValue
                    }
                }
                
                // Check if player already exists
                var players = gameData["players"] as? [[String: Any]] ?? []
                let existingPlayerIndex = players.firstIndex(where: { ($0["userId"] as? String) == request.userId })
                
                if let index = existingPlayerIndex {
                    // Player exists, update their stack and buy-in
                    let currentStack = players[index]["currentStack"] as? Double ?? 0
                    let totalBuyIn = players[index]["totalBuyIn"] as? Double ?? 0
                    
                    players[index]["currentStack"] = currentStack + request.amount
                    players[index]["totalBuyIn"] = totalBuyIn + request.amount
                    players[index]["status"] = HomeGame.Player.PlayerStatus.active.rawValue
                } else {
                    // Add new player
                    let player: [String: Any] = [
                        "id": UUID().uuidString,
                        "userId": request.userId,
                        "displayName": request.displayName,
                        "currentStack": request.amount,
                        "totalBuyIn": request.amount,
                        "joinedAt": Timestamp(date: Date()),
                        "status": HomeGame.Player.PlayerStatus.active.rawValue
                    ]
                    players.append(player)
                }
                
                // Add event to game history
                let event: [String: Any] = [
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "eventType": HomeGame.GameEvent.EventType.buyIn.rawValue,
                    "userId": request.userId,
                    "userName": request.displayName,
                    "amount": request.amount,
                    "description": "\(request.displayName) bought in for $\(Int(request.amount))"
                ]
                
                var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                gameHistory.append(event)
                
                // Update the game
                transaction.updateData([
                    "buyInRequests": buyInRequests,
                    "players": players,
                    "gameHistory": gameHistory
                ], forDocument: gameRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    /// Decline a buy-in request
    func declineBuyIn(gameId: String, requestId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // First get the game and check ownership
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can decline buy-ins"])
        }
        
        // Find the request
        guard let request = game.buyInRequests.first(where: { $0.id == requestId && $0.status == .pending }) else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Buy-in request not found"])
        }
        
        // Process in transaction to prevent race conditions
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Update the request status to rejected
                var buyInRequests = gameData["buyInRequests"] as? [[String: Any]] ?? []
                for i in 0..<buyInRequests.count {
                    if let reqId = buyInRequests[i]["id"] as? String, reqId == requestId {
                        buyInRequests[i]["status"] = HomeGame.BuyInRequest.RequestStatus.rejected.rawValue
                    }
                }
                
                // Add rejection event to game history
                let event: [String: Any] = [
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "eventType": HomeGame.GameEvent.EventType.buyIn.rawValue,
                    "userId": request.userId,
                    "userName": request.displayName,
                    "amount": request.amount,
                    "description": "\(request.displayName)'s buy-in request of $\(Int(request.amount)) was declined"
                ]
                
                var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                gameHistory.append(event)
                
                // Update the game
                transaction.updateData([
                    "buyInRequests": buyInRequests,
                    "gameHistory": gameHistory
                ], forDocument: gameRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    /// Request to cash out from a game
    func requestCashOut(gameId: String, amount: Double) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get the game
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        // Find the player
        guard let player = game.players.first(where: { $0.userId == currentUser.uid && $0.status == .active }) else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Player not found in game"])
        }
        
        // No maximum check - allow any amount

        // Create the cash-out request
        let requestId = UUID().uuidString
        let request: [String: Any] = [
            "id": requestId,
            "userId": currentUser.uid,
            "displayName": player.displayName,
            "amount": amount,
            "requestedAt": Timestamp(date: Date()),
            "status": HomeGame.CashOutRequest.RequestStatus.pending.rawValue
        ]
        
        // Add the request to the game
        try await db.collection("homeGames").document(gameId).updateData([
            "cashOutRequests": FieldValue.arrayUnion([request])
        ])
        
        // Add event to game history
        let event: [String: Any] = [
            "id": UUID().uuidString,
            "timestamp": Timestamp(date: Date()),
            "eventType": HomeGame.GameEvent.EventType.cashOut.rawValue,
            "userId": currentUser.uid,
            "userName": player.displayName,
            "amount": amount,
            "description": "\(player.displayName) requested cash-out of $\(Int(amount))"
        ]
        
        try await db.collection("homeGames").document(gameId).updateData([
            "gameHistory": FieldValue.arrayUnion([event])
        ])
    }
    
    /// Host auto-approved buy-in/rebuy
    func hostBuyIn(gameId: String, amount: Double) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get the game
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        // Verify user is the host
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can use direct buy-in"])
        }
        
        // Get user's display name
        let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
        let userData = userDoc.data()
        let displayName = userData?["displayName"] as? String ?? userData?["username"] as? String ?? "Unknown"
        
        // Process in transaction
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Check if player already exists
                var players = gameData["players"] as? [[String: Any]] ?? []
                let existingPlayerIndex = players.firstIndex(where: { ($0["userId"] as? String) == currentUser.uid })
                
                if let index = existingPlayerIndex {
                    // Player exists, update their stack and buy-in
                    let currentStack = players[index]["currentStack"] as? Double ?? 0
                    let totalBuyIn = players[index]["totalBuyIn"] as? Double ?? 0
                    
                    players[index]["currentStack"] = currentStack + amount
                    players[index]["totalBuyIn"] = totalBuyIn + amount
                    players[index]["status"] = HomeGame.Player.PlayerStatus.active.rawValue
                } else {
                    // Add new player
                    let player: [String: Any] = [
                        "id": UUID().uuidString,
                        "userId": currentUser.uid,
                        "displayName": displayName,
                        "currentStack": amount,
                        "totalBuyIn": amount,
                        "joinedAt": Timestamp(date: Date()),
                        "status": HomeGame.Player.PlayerStatus.active.rawValue
                    ]
                    players.append(player)
                }
                
                // Add event to game history
                let event: [String: Any] = [
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "eventType": HomeGame.GameEvent.EventType.buyIn.rawValue,
                    "userId": currentUser.uid,
                    "userName": displayName,
                    "amount": amount,
                    "description": "\(displayName) (host) bought in for $\(Int(amount))"
                ]
                
                var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                gameHistory.append(event)
                
                // Update the game
                transaction.updateData([
                    "players": players,
                    "gameHistory": gameHistory
                ], forDocument: gameRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    /// Process a cash-out request
    func processCashOut(gameId: String, requestId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // First get the game and check ownership
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can process cash-outs"])
        }
        
        // Find the request
        guard let request = game.cashOutRequests.first(where: { $0.id == requestId && $0.status == .pending }) else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cash-out request not found"])
        }
        
        // Add validation for amount
        guard request.amount > 0 else {
            // Optionally, decline the request instead of throwing an error
            // try? await declineCashOutRequest(gameId: gameId, requestId: requestId) 
            throw NSError(domain: "HomeGameService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cash-out amount must be greater than zero"])
        }
        
        // Process in transaction
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Update the request status to processed
                var cashOutRequests = gameData["cashOutRequests"] as? [[String: Any]] ?? []
                for i in 0..<cashOutRequests.count {
                    if let reqId = cashOutRequests[i]["id"] as? String, reqId == requestId {
                        cashOutRequests[i]["status"] = HomeGame.CashOutRequest.RequestStatus.processed.rawValue
                        cashOutRequests[i]["processedAt"] = Timestamp(date: Date())
                    }
                }
                
                // Update the player status and stack
                var players = gameData["players"] as? [[String: Any]] ?? []
                for i in 0..<players.count {
                    if let userId = players[i]["userId"] as? String, userId == request.userId {
                        players[i]["status"] = HomeGame.Player.PlayerStatus.cashedOut.rawValue
                        players[i]["cashedOutAt"] = Timestamp(date: Date())
                        // Explicitly set currentStack to the cashed out amount
                        players[i]["currentStack"] = request.amount 
                    }
                }
                
                // Add event to game history
                let event: [String: Any] = [
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "eventType": HomeGame.GameEvent.EventType.cashOut.rawValue,
                    "userId": request.userId,
                    "userName": request.displayName,
                    "amount": request.amount,
                    "description": "\(request.displayName) cashed out $\(Int(request.amount))"
                ]
                
                var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                gameHistory.append(event)
                
                // Check if all players have cashed out, then end the game
                let activePlayers = players.filter { ($0["status"] as? String) == HomeGame.Player.PlayerStatus.active.rawValue }
                
                var gameStatus = gameData["status"] as? String ?? HomeGame.GameStatus.active.rawValue
                
                if activePlayers.isEmpty && !players.isEmpty {
                    gameStatus = HomeGame.GameStatus.completed.rawValue
                    
                    // Add game ended event
                    let endEvent: [String: Any] = [
                        "id": UUID().uuidString,
                        "timestamp": Timestamp(date: Date()),
                        "eventType": HomeGame.GameEvent.EventType.gameEnded.rawValue,
                        "userId": currentUser.uid,
                        "userName": game.creatorName,
                        "description": "Game ended: \(game.title)"
                    ]
                    
                    gameHistory.append(endEvent)
                }
                
                // Update the game
                transaction.updateData([
                    "cashOutRequests": cashOutRequests,
                    "players": players,
                    "gameHistory": gameHistory,
                    "status": gameStatus
                ], forDocument: gameRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    // MARK: - Game End Handling
    
    /// Process a cashout during game end without requiring a request
    func processCashoutForGameEnd(gameId: String, playerId: String, userId: String, amount: Double) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Verify user is the host
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can process cash-outs during game end"])
        }
        
        // Process in transaction
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Find the player
                var players = gameData["players"] as? [[String: Any]] ?? []
                var targetPlayer: [String: Any]? = nil
                var targetPlayerIndex = -1
                
                for (index, player) in players.enumerated() {
                    if let id = player["id"] as? String, id == playerId {
                        targetPlayer = player
                        targetPlayerIndex = index
                        break
                    }
                }
                
                guard let player = targetPlayer, targetPlayerIndex >= 0 else {
                    throw NSError(domain: "HomeGameService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Player not found"])
                }
                
                guard let displayName = player["displayName"] as? String,
                      let currentStack = player["currentStack"] as? Double,
                      (player["status"] as? String) == HomeGame.Player.PlayerStatus.active.rawValue else {
                    throw NSError(domain: "HomeGameService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Player is not active or missing required data"])
                }
                
                // No maximum amount validation - allow any amount
                
                // Update player's stack and status for game end cashout
                players[targetPlayerIndex]["status"] = HomeGame.Player.PlayerStatus.cashedOut.rawValue
                players[targetPlayerIndex]["cashedOutAt"] = Timestamp(date: Date())
                // Set currentStack to the exact amount specified for the cashout (can be 0)
                players[targetPlayerIndex]["currentStack"] = amount

                // Add event to game history
                let event: [String: Any] = [
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "eventType": HomeGame.GameEvent.EventType.cashOut.rawValue,
                    "userId": userId,
                    "userName": displayName,
                    "amount": amount,
                    "description": "\(displayName) cashed out $\(Int(amount))"
                ]
                
                var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                gameHistory.append(event)
                
                // Update the game
                transaction.updateData([
                    "players": players,
                    "gameHistory": gameHistory
                ], forDocument: gameRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Parse a home game from Firestore data
    private func parseHomeGame(data: [String: Any], id: String) throws -> HomeGame {
        guard let title = data["title"] as? String,
              let creatorId = data["creatorId"] as? String,
              let creatorName = data["creatorName"] as? String,
              let groupId = data["groupId"] as? String,
              let statusRaw = data["status"] as? String,
              let status = HomeGame.GameStatus(rawValue: statusRaw),
              let createdAtTimestamp = data["createdAt"] as? Timestamp else {
            throw NSError(domain: "HomeGameService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid game data format"])
        }
        
        let createdAt = createdAtTimestamp.dateValue()
        
        // Parse players
        var players: [HomeGame.Player] = []
        if let playersData = data["players"] as? [[String: Any]] {
            for playerData in playersData {
                if let playerId = playerData["id"] as? String,
                   let userId = playerData["userId"] as? String,
                   let displayName = playerData["displayName"] as? String,
                   let currentStack = playerData["currentStack"] as? Double,
                   let totalBuyIn = playerData["totalBuyIn"] as? Double,
                   let joinedAtTimestamp = playerData["joinedAt"] as? Timestamp,
                   let statusRaw = playerData["status"] as? String,
                   let status = HomeGame.Player.PlayerStatus(rawValue: statusRaw) {
                    
                    let player = HomeGame.Player(
                        id: playerId,
                        userId: userId,
                        displayName: displayName,
                        currentStack: currentStack,
                        totalBuyIn: totalBuyIn,
                        joinedAt: joinedAtTimestamp.dateValue(),
                        cashedOutAt: playerData["cashedOutAt"] as? Timestamp != nil ? 
                            (playerData["cashedOutAt"] as! Timestamp).dateValue() : nil,
                        status: status
                    )
                    
                    players.append(player)
                }
            }
        }
        
        // Parse buy-in requests
        var buyInRequests: [HomeGame.BuyInRequest] = []
        if let requestsData = data["buyInRequests"] as? [[String: Any]] {
            for requestData in requestsData {
                if let requestId = requestData["id"] as? String,
                   let userId = requestData["userId"] as? String,
                   let displayName = requestData["displayName"] as? String,
                   let amount = requestData["amount"] as? Double,
                   let requestedAtTimestamp = requestData["requestedAt"] as? Timestamp,
                   let statusRaw = requestData["status"] as? String,
                   let status = HomeGame.BuyInRequest.RequestStatus(rawValue: statusRaw) {
                    
                    let request = HomeGame.BuyInRequest(
                        id: requestId,
                        userId: userId,
                        displayName: displayName,
                        amount: amount,
                        requestedAt: requestedAtTimestamp.dateValue(),
                        status: status
                    )
                    
                    buyInRequests.append(request)
                }
            }
        }
        
        // Parse cash-out requests
        var cashOutRequests: [HomeGame.CashOutRequest] = []
        if let requestsData = data["cashOutRequests"] as? [[String: Any]] {
            for requestData in requestsData {
                if let requestId = requestData["id"] as? String,
                   let userId = requestData["userId"] as? String,
                   let displayName = requestData["displayName"] as? String,
                   let amount = requestData["amount"] as? Double,
                   let requestedAtTimestamp = requestData["requestedAt"] as? Timestamp,
                   let statusRaw = requestData["status"] as? String,
                   let status = HomeGame.CashOutRequest.RequestStatus(rawValue: statusRaw) {
                    
                    var processedAt: Date? = nil
                    if let processedAtTimestamp = requestData["processedAt"] as? Timestamp {
                        processedAt = processedAtTimestamp.dateValue()
                    }
                    
                    let request = HomeGame.CashOutRequest(
                        id: requestId,
                        userId: userId,
                        displayName: displayName,
                        amount: amount,
                        requestedAt: requestedAtTimestamp.dateValue(),
                        processedAt: processedAt,
                        status: status
                    )
                    
                    cashOutRequests.append(request)
                }
            }
        }
        
        // Parse game history
        var gameHistory: [HomeGame.GameEvent] = []
        if let eventsData = data["gameHistory"] as? [[String: Any]] {
            for eventData in eventsData {
                if let eventId = eventData["id"] as? String,
                   let timestampData = eventData["timestamp"] as? Timestamp,
                   let eventTypeRaw = eventData["eventType"] as? String,
                   let eventType = HomeGame.GameEvent.EventType(rawValue: eventTypeRaw),
                   let userId = eventData["userId"] as? String,
                   let userName = eventData["userName"] as? String,
                   let description = eventData["description"] as? String {
                    
                    let event = HomeGame.GameEvent(
                        id: eventId,
                        timestamp: timestampData.dateValue(),
                        eventType: eventType,
                        userId: userId,
                        userName: userName,
                        amount: eventData["amount"] as? Double,
                        description: description
                    )
                    
                    gameHistory.append(event)
                }
            }
        }
        
        return HomeGame(
            id: id,
            title: title,
            createdAt: createdAt,
            creatorId: creatorId,
            creatorName: creatorName,
            groupId: groupId,
            status: status,
            players: players,
            buyInRequests: buyInRequests,
            cashOutRequests: cashOutRequests,
            gameHistory: gameHistory
        )
    }
} 
