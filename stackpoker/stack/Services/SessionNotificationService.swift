import Foundation
import FirebaseFirestore
import FirebaseAuth

class SessionNotificationService: ObservableObject {
    
    // MARK: - Session Notification Model
    struct SessionNotification {
        let id: String
        let sessionId: String
        let playerId: String
        let playerDisplayName: String
        let gameName: String
        let stakes: String
        let buyIn: Double
        let startTime: Date
        let isTournament: Bool
        let tournamentName: String?
        let casino: String?
        let createdAt: Date
        
        // Firebase data conversion
        var data: [String: Any] {
            var result: [String: Any] = [
                "sessionId": sessionId,
                "playerId": playerId,
                "playerDisplayName": playerDisplayName,
                "gameName": gameName,
                "stakes": stakes,
                "buyIn": buyIn,
                "startTime": Timestamp(date: startTime),
                "isTournament": isTournament,
                "createdAt": Timestamp(date: createdAt)
            ]
            
            if let tournamentName = tournamentName {
                result["tournamentName"] = tournamentName
            }
            
            if let casino = casino {
                result["casino"] = casino
            }
            
            return result
        }
        
        init(id: String = UUID().uuidString, sessionId: String, playerId: String, playerDisplayName: String, gameName: String, stakes: String, buyIn: Double, startTime: Date, isTournament: Bool, tournamentName: String? = nil, casino: String? = nil) {
            self.id = id
            self.sessionId = sessionId
            self.playerId = playerId
            self.playerDisplayName = playerDisplayName
            self.gameName = gameName
            self.stakes = stakes
            self.buyIn = buyIn
            self.startTime = startTime
            self.isTournament = isTournament
            self.tournamentName = tournamentName
            self.casino = casino
            self.createdAt = Date()
        }
    }
    
    // MARK: - Rebuy Notification Model
    struct RebuyNotification {
        let id: String
        let sessionId: String
        let playerId: String
        let playerDisplayName: String
        let gameName: String
        let stakes: String
        let rebuyAmount: Double
        let newTotalBuyIn: Double
        let rebuyTime: Date
        let isTournament: Bool
        let tournamentName: String?
        let createdAt: Date
        
        var data: [String: Any] {
            var result: [String: Any] = [
                "sessionId": sessionId,
                "playerId": playerId,
                "playerDisplayName": playerDisplayName,
                "gameName": gameName,
                "stakes": stakes,
                "rebuyAmount": rebuyAmount,
                "newTotalBuyIn": newTotalBuyIn,
                "rebuyTime": Timestamp(date: rebuyTime),
                "isTournament": isTournament,
                "createdAt": Timestamp(date: createdAt)
            ]
            
            if let tournamentName = tournamentName {
                result["tournamentName"] = tournamentName
            }
            
            return result
        }
        
        init(id: String = UUID().uuidString, sessionId: String, playerId: String, playerDisplayName: String, gameName: String, stakes: String, rebuyAmount: Double, newTotalBuyIn: Double, rebuyTime: Date, isTournament: Bool, tournamentName: String? = nil) {
            self.id = id
            self.sessionId = sessionId
            self.playerId = playerId
            self.playerDisplayName = playerDisplayName
            self.gameName = gameName
            self.stakes = stakes
            self.rebuyAmount = rebuyAmount
            self.newTotalBuyIn = newTotalBuyIn
            self.rebuyTime = rebuyTime
            self.isTournament = isTournament
            self.tournamentName = tournamentName
            self.createdAt = Date()
        }
    }
    
    // MARK: - Service Methods
    
    /// Create a session start notification that Firebase Functions can listen to
    func notifySessionStart(
        sessionId: String,
        playerId: String,
        playerDisplayName: String,
        gameName: String,
        stakes: String,
        buyIn: Double,
        startTime: Date,
        isTournament: Bool = false,
        tournamentName: String? = nil,
        casino: String? = nil
    ) async throws {
        
        print("[SessionNotificationService] Creating session start notification for session: \(sessionId), player: \(playerDisplayName)")
        
        let notification = SessionNotification(
            sessionId: sessionId,
            playerId: playerId,
            playerDisplayName: playerDisplayName,
            gameName: gameName,
            stakes: stakes,
            buyIn: buyIn,
            startTime: startTime,
            isTournament: isTournament,
            tournamentName: tournamentName,
            casino: casino
        )
        
        try await Firestore.firestore()
            .collection("sessionStartNotifications")
            .document(notification.id)
            .setData(notification.data)
        
        print("[SessionNotificationService] ✅ Session start notification created successfully")
    }
    
    /// Create a rebuy notification that Firebase Functions can listen to
    func notifyRebuy(
        sessionId: String,
        playerId: String,
        playerDisplayName: String,
        gameName: String,
        stakes: String,
        rebuyAmount: Double,
        newTotalBuyIn: Double,
        isTournament: Bool = false,
        tournamentName: String? = nil
    ) async throws {
        
        print("[SessionNotificationService] Creating rebuy notification for session: \(sessionId), player: \(playerDisplayName), amount: $\(rebuyAmount)")
        
        let notification = RebuyNotification(
            sessionId: sessionId,
            playerId: playerId,
            playerDisplayName: playerDisplayName,
            gameName: gameName,
            stakes: stakes,
            rebuyAmount: rebuyAmount,
            newTotalBuyIn: newTotalBuyIn,
            rebuyTime: Date(),
            isTournament: isTournament,
            tournamentName: tournamentName
        )
        
        try await Firestore.firestore()
            .collection("sessionRebuyNotifications")
            .document(notification.id)
            .setData(notification.data)
        
        print("[SessionNotificationService] ✅ Rebuy notification created successfully")
    }
    
    /// Get the current user's display name for notifications
    private func getCurrentUserDisplayName() async -> String {
        guard let currentUser = Auth.auth().currentUser else {
            return "Unknown Player"
        }
        
        // Try to get from Firestore first
        do {
            let userDoc = try await Firestore.firestore()
                .collection("users")
                .document(currentUser.uid)
                .getDocument()
            
            if let userData = userDoc.data(),
               let displayName = userData["displayName"] as? String {
                return displayName
            }
        } catch {
            print("[SessionNotificationService] Error fetching user display name: \(error)")
        }
        
        // Fallback to Auth display name or email
        return currentUser.displayName ?? currentUser.email ?? "Unknown Player"
    }
    
    /// Convenience method to create session start notification with current user
    func notifyCurrentUserSessionStart(
        sessionId: String,
        gameName: String,
        stakes: String,
        buyIn: Double,
        startTime: Date,
        isTournament: Bool = false,
        tournamentName: String? = nil,
        casino: String? = nil
    ) async throws {
        
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "SessionNotificationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let displayName = await getCurrentUserDisplayName()
        
        try await notifySessionStart(
            sessionId: sessionId,
            playerId: currentUser.uid,
            playerDisplayName: displayName,
            gameName: gameName,
            stakes: stakes,
            buyIn: buyIn,
            startTime: startTime,
            isTournament: isTournament,
            tournamentName: tournamentName,
            casino: casino
        )
    }
    
    /// Convenience method to create rebuy notification with current user
    func notifyCurrentUserRebuy(
        sessionId: String,
        gameName: String,
        stakes: String,
        rebuyAmount: Double,
        newTotalBuyIn: Double,
        isTournament: Bool = false,
        tournamentName: String? = nil
    ) async throws {
        
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "SessionNotificationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let displayName = await getCurrentUserDisplayName()
        
        try await notifyRebuy(
            sessionId: sessionId,
            playerId: currentUser.uid,
            playerDisplayName: displayName,
            gameName: gameName,
            stakes: stakes,
            rebuyAmount: rebuyAmount,
            newTotalBuyIn: newTotalBuyIn,
            isTournament: isTournament,
            tournamentName: tournamentName
        )
    }
} 