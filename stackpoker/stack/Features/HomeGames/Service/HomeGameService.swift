import Foundation
import Firebase
import FirebaseFirestore
import Combine
import FirebaseAuth

@MainActor
class HomeGameService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var activeGames: [HomeGame] = []
    @Published var isLoading = false
    
    private var gameListeners: [String: ListenerRegistration] = [:]
    private var standaloneListener: ListenerRegistration? = nil
    
    struct PlayerInfo {
        let userId: String
        let displayName: String
    }
    
    // MARK: - Real-time Updates
    
    /// Listen for real-time updates to a game
    func listenForGameUpdates(gameId: String, onChange: @escaping (HomeGame) -> Void) {
        // If we already have a listener for this game, remove it
        stopListeningForGameUpdates(gameId: gameId)
        
        // Create a new listener
        let listener = db.collection("homeGames").document(gameId)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let document = documentSnapshot else {
                    // Handle error or return
                    return
                }
                
                // Use a Task to hop to the MainActor for processing
                Task {
                    await self?._processGameUpdate(gameId: gameId, document: document, onChange: onChange)
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
    
    /// Listen in real-time for active standalone games for a user (creator or player)
    func startListeningForActiveStandaloneGame(userId: String, onChange: @escaping (HomeGame?) -> Void) {
        stopListeningForActiveStandaloneGame()

        // Helper to process snapshots
        let process: (QuerySnapshot?) -> Void = { snapshot in
            guard let snap = snapshot else { return }
            var latestGame: HomeGame? = nil
            for doc in snap.documents {
                if let game = try? self.parseHomeGame(data: doc.data(), id: doc.documentID) {
                    // Only include games explicitly marked as ACTIVE
                    if game.status == .active {
                        // Prefer most recently created active game
                        if latestGame == nil || game.createdAt > latestGame!.createdAt {
                            latestGame = game
                        }
                    }
                    // Ignore games marked as completed
                }
            }
            onChange(latestGame)
        }
        
        // Listener for games the user created - ONLY ACTIVE games to avoid confusion
        let l1 = db.collection("homeGames")
            .whereField("status", isEqualTo: HomeGame.GameStatus.active.rawValue)
            .whereField("groupId", isEqualTo: NSNull())
            .whereField("creatorId", isEqualTo: userId)
            .addSnapshotListener { snap, _ in process(snap) }
        
        // Listener for games the user is a player in - ONLY ACTIVE games to avoid confusion
        let l2 = db.collection("homeGames")
            .whereField("status", isEqualTo: HomeGame.GameStatus.active.rawValue)
            .whereField("groupId", isEqualTo: NSNull())
            .whereField("playerIds", arrayContains: userId)
            .addSnapshotListener { snap, _ in process(snap) }
        
        // Store a combined listener reference that removes both when called
        standaloneListener = CombinedListener(listeners: [l1, l2])
    }
    
    private func forceGameStatusToActive(gameId: String) async throws {
        try await db.collection("homeGames").document(gameId).updateData([
            "status": HomeGame.GameStatus.active.rawValue
        ])
    }
    
    func stopListeningForActiveStandaloneGame() {
        standaloneListener?.remove(); standaloneListener = nil
    }
    
    private class CombinedListener: NSObject, ListenerRegistration {
        let listeners: [ListenerRegistration]
        init(listeners: [ListenerRegistration]) { self.listeners = listeners }
        func remove() { listeners.forEach { $0.remove() } }
    }
    
    // MARK: - Game Management
    
    /// Create a new home game
    func createHomeGame(title: String, creatorId: String, creatorName: String, initialPlayers: [PlayerInfo], smallBlind: Double? = nil, bigBlind: Double? = nil, groupId: String? = nil, linkedEventId: String? = nil) async throws -> HomeGame {
        let players = initialPlayers.map {
            HomeGame.Player(
                id: UUID().uuidString,
                userId: $0.userId,
                displayName: $0.displayName,
                currentStack: 0,
                totalBuyIn: 0,
                joinedAt: Date(),
                cashedOutAt: nil,
                status: .active
            )
        }

        // Create game document
        let gameId = UUID().uuidString
        let createdAt = Date()
        
        var gameData: [String: Any] = [
            "title": title,
            "createdAt": Timestamp(date: createdAt),
            "creatorId": creatorId,
            "creatorName": creatorName,
            "status": HomeGame.GameStatus.active.rawValue,
            "players": players.map { $0.toDictionary() },
            "playerIds": players.map { $0.userId },
            "buyInRequests": [],
            "cashOutRequests": [],
        ]
        
        // Add stakes if provided
        if let smallBlind = smallBlind {
            gameData["smallBlind"] = smallBlind
        }
        if let bigBlind = bigBlind {
            gameData["bigBlind"] = bigBlind
        }
        
        // Only add groupId if it's provided and not nil
        if let groupId = groupId {
            gameData["groupId"] = groupId
        } else {
            // Explicitly set groupId to nil for standalone games (to ensure it's searchable)
            gameData["groupId"] = NSNull()
        }
        
        if let linkedEventId = linkedEventId {
            gameData["linkedEventId"] = linkedEventId
        }
        
        // Add initial game created event
        let event: [String: Any] = [
            "id": UUID().uuidString,
            "timestamp": Timestamp(date: createdAt),
            "eventType": HomeGame.GameEvent.EventType.gameCreated.rawValue,
            "userId": creatorId,
            "userName": creatorName,
            "description": "Game created: \(title)"
        ]
        
        gameData["gameHistory"] = [event]
        
        // Save the game
        try await db.collection("homeGames").document(gameId).setData(gameData)
        
        // If this is for a group, add a reference to the game in the group
        if let groupId = groupId {
            try await db.collection("groups").document(groupId).updateData([
                "gameIds": FieldValue.arrayUnion([gameId])
            ])
        }
        
        // Create and return the HomeGame object
        return HomeGame(
            id: gameId,
            title: title,
            createdAt: createdAt,
            creatorId: creatorId,
            creatorName: creatorName,
            groupId: groupId,
            linkedEventId: linkedEventId,
            playerIds: players.map { $0.userId },
            status: .active,
            players: players,
            buyInRequests: [],
            cashOutRequests: [],
            gameHistory: [
                HomeGame.GameEvent(
                    id: event["id"] as! String,
                    timestamp: createdAt,
                    eventType: .gameCreated,
                    userId: creatorId,
                    userName: creatorName,
                    amount: nil,
                    description: "Game created: \(title)"
                )
            ],
            settlementTransactions: nil,
            smallBlind: smallBlind,
            bigBlind: bigBlind
        )
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
                
                // Calculate settlement transactions and store them
                let settlementTransactions = self.calculateSettlementTransactions(for: players)
                let settlementTransactionsData = settlementTransactions.map { $0.toDictionary() }
                
                // Update the game status to completed
                transaction.updateData([
                    "players": players,
                    "gameHistory": gameHistory,
                    "settlementTransactions": settlementTransactionsData,
                    "status": HomeGame.GameStatus.completed.rawValue
                ], forDocument: gameRef)
                
                if let linkedEventId = gameData["linkedEventId"] as? String {
                    let eventRef = self.db.collection("userEvents").document(linkedEventId)
                    transaction.updateData(["status": UserEvent.EventStatus.completed.rawValue], forDocument: eventRef)
                }
                
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
        
        self.activeGames = games
        
        return games
    }
    
    /// Fetch all active games created by a specific user ID
    func fetchActiveGames(createdBy userId: String) async throws -> [HomeGame] {
        self.isLoading = true
        defer { 
            self.isLoading = false
        }
        
        let querySnapshot = try await db.collection("homeGames")
            .whereField("creatorId", isEqualTo: userId)
            .whereField("status", isEqualTo: HomeGame.GameStatus.active.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        var games: [HomeGame] = []
        for document in querySnapshot.documents {
            let data = document.data()
            // Ensure we correctly parse games, including those with an optional groupId
            if let game = try? parseHomeGame(data: data, id: document.documentID) {
                games.append(game)
            }
        }
        // Note: This function doesn't update the @Published activeGames property directly,
        // as that property is typically used for group-specific active games.
        // The caller (HomePage) will manage the state for these fetched games.
        return games
    }
    
    /// Fetch active games where user is a player (standalone)
    func fetchActiveStandaloneGames(for userId: String) async throws -> [HomeGame] {
        self.isLoading = true
        defer { self.isLoading = false }

        let snapshot = try await db.collection("homeGames")
            .whereField("status", isEqualTo: HomeGame.GameStatus.active.rawValue)
            .whereField("groupId", isEqualTo: NSNull())
            .whereField("playerIds", arrayContains: userId)
            .getDocuments()

        var games: [HomeGame] = []
        for doc in snapshot.documents {
            if let game = try? parseHomeGame(data: doc.data(), id: doc.documentID) {
                games.append(game)
            }
        }
        return games
    }
    
    // MARK: - Player Management
    
    func addPlayerToGame(gameId: String, userId: String, displayName: String) async throws {
        let gameRef = db.collection("homeGames").document(gameId)
        
        // Use a transaction to safely check for existence and add the player
        try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let gameDoc: DocumentSnapshot
            do {
                gameDoc = try transaction.getDocument(gameRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            guard let gameData = gameDoc.data(),
                  let statusRaw = gameData["status"] as? String,
                  let status = HomeGame.GameStatus(rawValue: statusRaw),
                  status == .active else {
                // Game doesn't exist or is not active
                return nil
            }
            
            // Check if player already exists
            if let players = gameData["players"] as? [[String: Any]], players.contains(where: { ($0["userId"] as? String) == userId }) {
                // Player already in the game, do nothing.
                return nil
            }
            
            // Create a new player
            let newPlayer = HomeGame.Player(
                id: UUID().uuidString,
                userId: userId,
                displayName: displayName,
                currentStack: 0,
                totalBuyIn: 0,
                joinedAt: Date(),
                cashedOutAt: nil,
                status: .active
            )
            
            // Create a "player joined" event
            let joinEvent: [String: Any] = [
                "id": UUID().uuidString,
                "timestamp": Timestamp(date: Date()),
                "eventType": HomeGame.GameEvent.EventType.playerJoined.rawValue,
                "userId": userId,
                "userName": displayName,
                "description": "\(displayName) joined the game."
            ]
            
            // Update the game document
            transaction.updateData([
                "players": FieldValue.arrayUnion([newPlayer.toDictionary()]),
                "playerIds": FieldValue.arrayUnion([userId]),
                "gameHistory": FieldValue.arrayUnion([joinEvent])
            ], forDocument: gameRef)
            
            return nil
        }
    }
    
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
                var playerIds = gameData["playerIds"] as? [String] ?? []
                let existingPlayerIndex = players.firstIndex(where: { ($0["userId"] as? String) == request.userId })
                
                if let index = existingPlayerIndex {
                    // Player exists, update their stack and buy-in
                    let currentStack = players[index]["currentStack"] as? Double ?? 0
                    let totalBuyIn = players[index]["totalBuyIn"] as? Double ?? 0
                    
                    players[index]["currentStack"] = currentStack + request.amount
                    players[index]["totalBuyIn"] = totalBuyIn + request.amount
                    players[index]["status"] = HomeGame.Player.PlayerStatus.active.rawValue
                    
                    // Ensure userId is in playerIds array
                    if !playerIds.contains(request.userId) {
                        playerIds.append(request.userId)
                    }
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
                    
                    // Add userId to playerIds array
                    if !playerIds.contains(request.userId) {
                        playerIds.append(request.userId)
                    }
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
                    "playerIds": playerIds,
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
                var playerIds = gameData["playerIds"] as? [String] ?? []
                let existingPlayerIndex = players.firstIndex(where: { ($0["userId"] as? String) == currentUser.uid })
                
                if let index = existingPlayerIndex {
                    // Player exists, update their stack and buy-in
                    let currentStack = players[index]["currentStack"] as? Double ?? 0
                    let totalBuyIn = players[index]["totalBuyIn"] as? Double ?? 0
                    
                    players[index]["currentStack"] = currentStack + amount
                    players[index]["totalBuyIn"] = totalBuyIn + amount
                    players[index]["status"] = HomeGame.Player.PlayerStatus.active.rawValue
                    
                    // Ensure userId is in playerIds array
                    if !playerIds.contains(currentUser.uid) {
                        playerIds.append(currentUser.uid)
                    }
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
                    
                    // Add userId to playerIds array
                    if !playerIds.contains(currentUser.uid) {
                        playerIds.append(currentUser.uid)
                    }
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
                    "playerIds": playerIds,
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
                
                // FOR BANKED GAMES: NEVER auto-complete when all players cash out
                // Banked games (those with linkedEventId) should only be manually ended
                let hasLinkedEvent = gameData["linkedEventId"] != nil && !(gameData["linkedEventId"] is NSNull)
                
                if hasLinkedEvent {
                    // This is a banked game - ALWAYS keep it active, never auto-complete
                    gameStatus = HomeGame.GameStatus.active.rawValue
                } else if activePlayers.isEmpty && !players.isEmpty {
                    // Regular standalone game - auto-complete when all players cash out
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
    
    /// Update player values (current stack and total buy-in)
    func updatePlayerValues(gameId: String, playerId: String, newCurrentStack: Double, newTotalBuyIn: Double) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // First get the game and check ownership
        let game = try await fetchHomeGame(gameId: gameId)
        
        guard let game = game else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can edit player values"])
        }
        
        // Find the player
        guard let player = game.players.first(where: { $0.id == playerId }) else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Player not found"])
        }
        
        // Process in transaction to prevent race conditions
        try await db.runTransaction { transaction, errorPointer in
            do {
                let gameRef = self.db.collection("homeGames").document(gameId)
                let gameDoc = try transaction.getDocument(gameRef)
                
                guard var gameData = gameDoc.data() else {
                    throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game data not found"])
                }
                
                // Update the player's values
                var players = gameData["players"] as? [[String: Any]] ?? []
                for i in 0..<players.count {
                    if let id = players[i]["id"] as? String, id == playerId {
                        let oldCurrentStack = players[i]["currentStack"] as? Double ?? 0
                        let oldTotalBuyIn = players[i]["totalBuyIn"] as? Double ?? 0
                        
                        players[i]["currentStack"] = newCurrentStack
                        players[i]["totalBuyIn"] = newTotalBuyIn
                        
                        // Add event to game history about the update
                        let event: [String: Any] = [
                            "id": UUID().uuidString,
                            "timestamp": Timestamp(date: Date()),
                            "eventType": "playerUpdated", // Custom event type for player updates
                            "userId": player.userId,
                            "userName": player.displayName,
                            "description": "\(player.displayName)'s values updated: Stack $\(Int(oldCurrentStack)) → $\(Int(newCurrentStack)), Buy-in $\(Int(oldTotalBuyIn)) → $\(Int(newTotalBuyIn))"
                        ]
                        
                        var gameHistory = gameData["gameHistory"] as? [[String: Any]] ?? []
                        gameHistory.append(event)
                        
                        // Update the game
                        transaction.updateData([
                            "players": players,
                            "gameHistory": gameHistory
                        ], forDocument: gameRef)
                        
                        break
                    }
                }
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
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
    
    // MARK: - Settlement Calculation
    
    /// Calculate settlement transactions for completed game
    private func calculateSettlementTransactions(for playersData: [[String: Any]]) -> [HomeGame.SettlementTransaction] {
        var playerBalances: [(name: String, balance: Double)] = []
        
        // Calculate net profit/loss for each player
        for playerData in playersData {
            guard let displayName = playerData["displayName"] as? String,
                  let currentStack = playerData["currentStack"] as? Double,
                  let totalBuyIn = playerData["totalBuyIn"] as? Double else { continue }
            
            let netBalance = currentStack - totalBuyIn
            if abs(netBalance) > 1.0 {
                playerBalances.append((name: displayName, balance: netBalance))
            }
        }
        
        var transactions: [HomeGame.SettlementTransaction] = []
        var index = 1
        
        // Simple settlement algorithm - pair creditors with debtors
        while let creditorIndex = playerBalances.firstIndex(where: { $0.balance > 1.0 }),
              let debtorIndex = playerBalances.firstIndex(where: { $0.balance < -1.0 }) {
            
            let creditor = playerBalances[creditorIndex]
            let debtor = playerBalances[debtorIndex]
            
            let settlementAmount = min(creditor.balance, abs(debtor.balance))
            
            transactions.append(HomeGame.SettlementTransaction(
                id: UUID().uuidString,
                fromPlayer: debtor.name,
                toPlayer: creditor.name,
                amount: settlementAmount,
                index: index
            ))
            
            playerBalances[creditorIndex].balance -= settlementAmount
            playerBalances[debtorIndex].balance += settlementAmount
            
            playerBalances.removeAll { abs($0.balance) <= 1.0 }
            index += 1
        }
        
        return transactions
    }
    
    // MARK: - Helper Methods
    
    /// Parse a home game from Firestore data
    private func parseHomeGame(data: [String: Any], id: String) throws -> HomeGame {
        guard let title = data["title"] as? String,
              let creatorId = data["creatorId"] as? String,
              let creatorName = data["creatorName"] as? String,
              let statusRaw = data["status"] as? String,
              let status = HomeGame.GameStatus(rawValue: statusRaw),
              let createdAtTimestamp = data["createdAt"] as? Timestamp else {
            throw NSError(domain: "HomeGameService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid game data format"])
        }
        
        let groupId = data["groupId"] as? String
        let linkedEventId = data["linkedEventId"] as? String
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
        
        // Parse settlement transactions
        var settlementTransactions: [HomeGame.SettlementTransaction] = []
        if let settlementsData = data["settlementTransactions"] as? [[String: Any]] {
            for settlementData in settlementsData {
                if let settlementId = settlementData["id"] as? String,
                   let fromPlayer = settlementData["fromPlayer"] as? String,
                   let toPlayer = settlementData["toPlayer"] as? String,
                   let amount = settlementData["amount"] as? Double,
                   let index = settlementData["index"] as? Int {
                    
                    let settlement = HomeGame.SettlementTransaction(
                        id: settlementId,
                        fromPlayer: fromPlayer,
                        toPlayer: toPlayer,
                        amount: amount,
                        index: index
                    )
                    
                    settlementTransactions.append(settlement)
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
            linkedEventId: linkedEventId,
            playerIds: data["playerIds"] as? [String],
            status: status,
            players: players,
            buyInRequests: buyInRequests,
            cashOutRequests: cashOutRequests,
            gameHistory: gameHistory,
            settlementTransactions: settlementTransactions.isEmpty ? nil : settlementTransactions,
            smallBlind: data["smallBlind"] as? Double,
            bigBlind: data["bigBlind"] as? Double
        )
    }
    
    // New private method to handle game update processing on the MainActor
    private func _processGameUpdate(gameId: String, document: DocumentSnapshot, onChange: @escaping (HomeGame) -> Void) {
        guard document.exists, let data = document.data() else {
            // Handle document not existing or no data
            return
        }
        
        do {
            // self.parseHomeGame will run on MainActor because the class is @MainActor
            if let game = try? self.parseHomeGame(data: data, id: gameId) {
                onChange(game) // This callback will also be on the MainActor
            }
        } catch {
            // Handle parsing error
        }
    }
    
    // MARK: - Game Invites
    
    /// Send an invite to a user for a specific game
    func sendGameInvite(
        gameId: String, 
        invitedUserId: String, 
        invitedUserDisplayName: String, 
        message: String? = nil
    ) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get the game to verify ownership and get details
        guard let game = try await fetchHomeGame(gameId: gameId) else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can send invites"])
        }
        
        guard game.status == .active else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot invite to completed games"])
        }
        
        // Check if user is already invited or playing
        let existingInvites = try await fetchGameInvites(gameId: gameId)
        let hasExistingInvite = existingInvites.contains { 
            $0.invitedUserId == invitedUserId && $0.status == .pending 
        }
        
        if hasExistingInvite {
            throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "User already has a pending invite"])
        }
        
        // Check if user is already playing
        let isAlreadyPlaying = game.players.contains { $0.userId == invitedUserId }
        if isAlreadyPlaying {
            throw NSError(domain: "HomeGameService", code: 6, userInfo: [NSLocalizedDescriptionKey: "User is already playing in this game"])
        }
        
        // Create the invite
        let inviteId = UUID().uuidString
        let invite = HomeGame.GameInvite(
            id: inviteId,
            gameId: gameId,
            gameTitle: game.title,
            hostId: currentUser.uid,
            hostName: game.creatorName,
            invitedUserId: invitedUserId,
            invitedUserDisplayName: invitedUserDisplayName,
            invitedGroupId: nil,
            invitedGroupName: nil,
            message: message,
            createdAt: Date(),
            status: .pending,
            respondedAt: nil
        )
        
        // Save the invite to Firestore
        try await db.collection("gameInvites").document(inviteId).setData(invite.toDictionary())
    }
    
    /// Send invites to all members of a group
    func sendGroupGameInvite(
        gameId: String,
        groupId: String,
        groupName: String,
        message: String? = nil
    ) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get the game to verify ownership
        guard let game = try await fetchHomeGame(gameId: gameId) else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Game not found"])
        }
        
        guard game.creatorId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only the game creator can send invites"])
        }
        
        guard game.status == .active else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot invite to completed games"])
        }
        
        // Get group members from the members subcollection
        let membersSnapshot = try await db.collection("groups")
            .document(groupId)
            .collection("members")
            .getDocuments()
        
        let memberIds = membersSnapshot.documents.map { $0.documentID }
        
        // Get existing invites to avoid duplicates
        let existingInvites = try await fetchGameInvites(gameId: gameId)
        let alreadyInvitedUserIds = Set(existingInvites.filter { $0.status == .pending }.map { $0.invitedUserId })
        let alreadyPlayingUserIds = Set(game.players.map { $0.userId })
        
        // Send invites to each member (except host and already invited/playing users)
        for memberId in memberIds {
            if memberId != currentUser.uid && 
               !alreadyInvitedUserIds.contains(memberId) && 
               !alreadyPlayingUserIds.contains(memberId) {
                
                // Get user display name
                let userDoc = try await db.collection("users").document(memberId).getDocument()
                let userDisplayName = userDoc.data()?["displayName"] as? String ?? 
                                    userDoc.data()?["username"] as? String ?? "Unknown"
                
                let inviteId = UUID().uuidString
                let invite = HomeGame.GameInvite(
                    id: inviteId,
                    gameId: gameId,
                    gameTitle: game.title,
                    hostId: currentUser.uid,
                    hostName: game.creatorName,
                    invitedUserId: memberId,
                    invitedUserDisplayName: userDisplayName,
                    invitedGroupId: groupId,
                    invitedGroupName: groupName,
                    message: message,
                    createdAt: Date(),
                    status: .pending,
                    respondedAt: nil
                )
                
                try await db.collection("gameInvites").document(inviteId).setData(invite.toDictionary())
            }
        }
    }
    
    /// Fetch all invites for a specific game
    func fetchGameInvites(gameId: String) async throws -> [HomeGame.GameInvite] {
        let snapshot = try await db.collection("gameInvites")
            .whereField("gameId", isEqualTo: gameId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        var invites: [HomeGame.GameInvite] = []
        for document in snapshot.documents {
            if let invite = try? parseGameInvite(data: document.data(), id: document.documentID) {
                invites.append(invite)
            }
        }
        
        return invites
    }
    
    /// Fetch pending invites for the current user
    func fetchPendingInvites(for userId: String) async throws -> [HomeGame.GameInvite] {
        let snapshot = try await db.collection("gameInvites")
            .whereField("invitedUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: HomeGame.GameInvite.InviteStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        var invites: [HomeGame.GameInvite] = []
        for document in snapshot.documents {
            if let invite = try? parseGameInvite(data: document.data(), id: document.documentID) {
                // Only include invites for active games
                if let game = try? await fetchHomeGame(gameId: invite.gameId), game.status == .active {
                    invites.append(invite)
                }
            }
        }
        
        return invites
    }
    
    /// Accept a game invite and prompt for buy-in
    func acceptGameInvite(inviteId: String) async throws -> HomeGame.GameInvite {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get the invite
        let inviteDoc = try await db.collection("gameInvites").document(inviteId).getDocument()
        guard let inviteData = inviteDoc.data(),
              let invite = try? parseGameInvite(data: inviteData, id: inviteId) else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invite not found"])
        }
        
        guard invite.invitedUserId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Not authorized to accept this invite"])
        }
        
        guard invite.status == .pending else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invite is no longer pending"])
        }
        
        // Check if game is still active
        guard let game = try await fetchHomeGame(gameId: invite.gameId), game.status == .active else {
            throw NSError(domain: "HomeGameService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Game is no longer active"])
        }
        
        // Update invite status
        try await db.collection("gameInvites").document(inviteId).updateData([
            "status": HomeGame.GameInvite.InviteStatus.accepted.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
        
        // Return updated invite
        var updatedInvite = invite
        updatedInvite.status = .accepted
        updatedInvite.respondedAt = Date()
        
        return updatedInvite
    }
    
    /// Decline a game invite
    func declineGameInvite(inviteId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "HomeGameService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get the invite to verify ownership
        let inviteDoc = try await db.collection("gameInvites").document(inviteId).getDocument()
        guard let inviteData = inviteDoc.data(),
              let invite = try? parseGameInvite(data: inviteData, id: inviteId) else {
            throw NSError(domain: "HomeGameService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invite not found"])
        }
        
        guard invite.invitedUserId == currentUser.uid else {
            throw NSError(domain: "HomeGameService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Not authorized to decline this invite"])
        }
        
        guard invite.status == .pending else {
            throw NSError(domain: "HomeGameService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invite is no longer pending"])
        }
        
        // Update invite status
        try await db.collection("gameInvites").document(inviteId).updateData([
            "status": HomeGame.GameInvite.InviteStatus.declined.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
    }
    
    /// Listen for real-time updates to pending invites
    func listenForPendingInvites(userId: String, onChange: @escaping ([HomeGame.GameInvite]) -> Void) -> ListenerRegistration {
        return db.collection("gameInvites")
            .whereField("invitedUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: HomeGame.GameInvite.InviteStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                var invites: [HomeGame.GameInvite] = []
                for document in documents {
                    if let invite = try? self.parseGameInvite(data: document.data(), id: document.documentID) {
                        invites.append(invite)
                    }
                }
                
                onChange(invites)
            }
    }
    
    /// Parse a game invite from Firestore data
    private func parseGameInvite(data: [String: Any], id: String) throws -> HomeGame.GameInvite {
        guard let gameId = data["gameId"] as? String,
              let gameTitle = data["gameTitle"] as? String,
              let hostId = data["hostId"] as? String,
              let hostName = data["hostName"] as? String,
              let invitedUserId = data["invitedUserId"] as? String,
              let invitedUserDisplayName = data["invitedUserDisplayName"] as? String,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let statusRaw = data["status"] as? String,
              let status = HomeGame.GameInvite.InviteStatus(rawValue: statusRaw) else {
            throw NSError(domain: "HomeGameService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid invite data format"])
        }
        
        let respondedAt = (data["respondedAt"] as? Timestamp)?.dateValue()
        
        return HomeGame.GameInvite(
            id: id,
            gameId: gameId,
            gameTitle: gameTitle,
            hostId: hostId,
            hostName: hostName,
            invitedUserId: invitedUserId,
            invitedUserDisplayName: invitedUserDisplayName,
            invitedGroupId: data["invitedGroupId"] as? String,
            invitedGroupName: data["invitedGroupName"] as? String,
            message: data["message"] as? String,
            createdAt: createdAtTimestamp.dateValue(),
            status: status,
            respondedAt: respondedAt
        )
    }
} 
