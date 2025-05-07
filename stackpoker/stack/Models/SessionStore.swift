import Foundation
import FirebaseFirestore
import SwiftUI
import UserNotifications

struct Session: Identifiable, Equatable {
    let id: String
    let userId: String
    let gameType: String
    let gameName: String
    let stakes: String
    let startDate: Date
    let startTime: Date
    let endTime: Date
    let hoursPlayed: Double
    let buyIn: Double
    let cashout: Double
    let profit: Double
    let createdAt: Date
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = data["userId"] as? String ?? ""
        self.gameType = data["gameType"] as? String ?? ""
        self.gameName = data["gameName"] as? String ?? ""
        self.stakes = data["stakes"] as? String ?? ""
        
        // More detailed date logging
        if let startDateTimestamp = data["startDate"] as? Timestamp {
            self.startDate = startDateTimestamp.dateValue()
            print("📅 Session \(id) startDate: \(startDateTimestamp.dateValue())")
        } else {
            print("⚠️ No startDate timestamp for session \(id)")
            self.startDate = Date()
        }
        
        if let startTimeTimestamp = data["startTime"] as? Timestamp {
            self.startTime = startTimeTimestamp.dateValue()
            print("🕒 Session \(id) startTime: \(startTimeTimestamp.dateValue())")
        } else {
            print("⚠️ No startTime timestamp for session \(id)")
            self.startTime = Date()
        }
        
        if let endTimeTimestamp = data["endTime"] as? Timestamp {
            self.endTime = endTimeTimestamp.dateValue()
        } else {
            self.endTime = Date()
        }
        
        self.hoursPlayed = data["hoursPlayed"] as? Double ?? 0
        self.buyIn = data["buyIn"] as? Double ?? 0
        self.cashout = data["cashout"] as? Double ?? 0
        self.profit = data["profit"] as? Double ?? 0
        
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdAtTimestamp.dateValue()
            print("📝 Session \(id) createdAt: \(createdAtTimestamp.dateValue())")
        } else {
            self.createdAt = Date()
        }
    }
    
    static func == (lhs: Session, rhs: Session) -> Bool {
        return lhs.id == rhs.id &&
               lhs.userId == rhs.userId &&
               lhs.gameType == rhs.gameType &&
               lhs.gameName == rhs.gameName &&
               lhs.stakes == rhs.stakes &&
               lhs.startDate == rhs.startDate &&
               lhs.startTime == rhs.startTime &&
               lhs.endTime == rhs.endTime &&
               lhs.hoursPlayed == rhs.hoursPlayed &&
               lhs.buyIn == rhs.buyIn &&
               lhs.cashout == rhs.cashout &&
               lhs.profit == rhs.profit &&
               lhs.createdAt == rhs.createdAt
    }
}

// Model to track active live session
struct LiveSessionData: Codable {
    var isActive: Bool = false
    var startTime: Date = Date()
    var elapsedTime: TimeInterval = 0
    var gameName: String = ""
    var stakes: String = ""
    var buyIn: Double = 0
    var lastPausedAt: Date? = nil
    var lastActiveAt: Date? = nil
    var isEnded: Bool = false // Explicit flag to mark sessions that have been ended
}

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession = LiveSessionData()
    @Published var showLiveSessionBar = false
    
    private let db = Firestore.firestore()
    private let userId: String
    private var timer: Timer?
    
    init(userId: String) {
        print("📱 SessionStore initialized with userId: \(userId)")
        self.userId = userId
        fetchSessions()
        loadLiveSessionState()
    }
    
    // MARK: - Session Database Operations
    
    func fetchSessions() {
        print("🔍 Fetching sessions for user: \(userId)")
        db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .order(by: "startDate", descending: true)
            .order(by: "startTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching sessions: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ No documents found in snapshot")
                    return
                }
                
                print("📄 Received \(documents.count) session documents")
                
                self?.sessions = documents.map { document in
                    let data = document.data()
                    print("\n🔍 Processing session: \(document.documentID)")
                    print("Raw startDate: \(String(describing: data["startDate"]))")
                    print("Raw startTime: \(String(describing: data["startTime"]))")
                    print("Profit: \(data["profit"] as? Double ?? 0)")
                    return Session(id: document.documentID, data: data)
                }
                
                print("\n✅ Final sessions array:")
                self?.sessions.forEach { session in
                    print("ID: \(session.id)")
                    print("Date: \(session.startDate)")
                    print("Profit: \(session.profit)")
                    print("---")
                }
            }
    }
    
    func addSession(_ sessionData: [String: Any], completion: @escaping (Error?) -> Void) {
        db.collection("sessions").addDocument(data: sessionData, completion: completion)
    }
    
    func deleteSession(_ sessionId: String, completion: @escaping (Error?) -> Void) {
        db.collection("sessions").document(sessionId).delete(completion: completion)
    }
    
    // MARK: - Live Session Management
    
    func startLiveSession(gameName: String, stakes: String, buyIn: Double) {
        stopLiveSessionTimer() // Ensure any existing timer is stopped
        liveSession = LiveSessionData(
            isActive: true,
            startTime: Date(),
            elapsedTime: 0,
            gameName: gameName,
            stakes: stakes,
            buyIn: buyIn,
            lastPausedAt: nil,
            lastActiveAt: Date()
        )
        startLiveSessionTimer()
        showLiveSessionBar = true
        saveLiveSessionState()
        requestNotificationPermission()
        scheduleLiveSessionNotification()
    }
    
    func pauseLiveSession() {
        var session = liveSession
        session.isActive = false
        session.lastPausedAt = Date()
        if let lastActive = session.lastActiveAt {
            session.elapsedTime += Date().timeIntervalSince(lastActive)
        }
        session.lastActiveAt = nil
        liveSession = session // triggers SwiftUI update
        stopLiveSessionTimer()
        saveLiveSessionState()
        removeLiveSessionNotification()
    }
    
    func resumeLiveSession() {
        var session = liveSession
        session.isActive = true
        session.lastActiveAt = Date() // set to now
        liveSession = session // triggers SwiftUI update
        startLiveSessionTimer()
        saveLiveSessionState()
        scheduleLiveSessionNotification()
    }
    
    func updateLiveSessionBuyIn(amount: Double) {
        liveSession.buyIn += amount
        saveLiveSessionState()
    }
    
    func endLiveSession(cashout: Double, completion: @escaping (Error?) -> Void) {
        stopLiveSessionTimer()
        removeLiveSessionNotification()
        
        // Mark session as explicitly ended to prevent it from being loaded on next launch
        var session = liveSession
        session.isEnded = true
        session.isActive = false
        liveSession = session
        
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "CASH GAME",
            "gameName": liveSession.gameName,
            "stakes": liveSession.stakes,
            "startDate": Timestamp(date: liveSession.startTime),
            "startTime": Timestamp(date: liveSession.startTime),
            "endTime": Timestamp(date: Date()),
            "hoursPlayed": liveSession.elapsedTime / 3600, // Convert to hours
            "buyIn": liveSession.buyIn,
            "cashout": cashout,
            "profit": cashout - liveSession.buyIn,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Save ended state to UserDefaults immediately
        saveLiveSessionState()
        
        addSession(sessionData) { error in
            if error == nil {
                self.clearLiveSession()
                self.removeLiveSessionState()
            }
            completion(error)
        }
    }
    
    func clearLiveSession() {
        stopLiveSessionTimer()
        
        // Mark as explicitly ended before resetting
        var session = liveSession
        session.isEnded = true
        liveSession = session
        
        // Save the ended state first
        saveLiveSessionState()
        
        // Now reset completely
        liveSession = LiveSessionData()
        showLiveSessionBar = false
        removeLiveSessionState()
    }
    
    // MARK: - Timer Management
    
    private func startLiveSessionTimer() {
        stopLiveSessionTimer() // Ensure no duplicate timers
        var session = liveSession
        if session.isActive {
            session.lastActiveAt = Date()
            liveSession = session
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.liveSession.isActive, let lastActive = self.liveSession.lastActiveAt {
                let now = Date()
                let elapsed = now.timeIntervalSince(lastActive)
                self.liveSession.elapsedTime += elapsed
                self.liveSession.lastActiveAt = now
            }
            if Int(self.liveSession.elapsedTime) % 60 == 0 {
                self.saveLiveSessionState()
            }
        }
    }
    
    func stopLiveSessionTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - State Persistence
    
    private func saveLiveSessionState() {
        if let encoded = try? JSONEncoder().encode(liveSession) {
            UserDefaults.standard.set(encoded, forKey: "LiveSession_\(userId)")
        }
    }
    
    private func loadLiveSessionState() {
        if let savedData = UserDefaults.standard.data(forKey: "LiveSession_\(userId)"),
           var loadedSession = try? JSONDecoder().decode(LiveSessionData.self, from: savedData) {
            
            // Never restore a session that was explicitly ended
            if loadedSession.isEnded {
                clearLiveSession()
                return
            }
            
            // Only restore if session is actually in progress (active or paused, not ended)
            if loadedSession.isActive || loadedSession.lastPausedAt != nil {
                if loadedSession.isActive, let lastActive = loadedSession.lastActiveAt {
                    let additionalTime = Date().timeIntervalSince(lastActive)
                    loadedSession.elapsedTime += additionalTime
                    loadedSession.lastActiveAt = Date()
                }
                liveSession = loadedSession
                if loadedSession.isActive {
                    startLiveSessionTimer()
                }
                showLiveSessionBar = true
            } else {
                // If not active or paused, clear any lingering state
                clearLiveSession()
            }
        }
    }
    
    private func removeLiveSessionState() {
        UserDefaults.standard.removeObject(forKey: "LiveSession_\(userId)")
    }
    
    // MARK: - Notification Logic
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    private func scheduleLiveSessionNotification() {
        removeLiveSessionNotification() // Remove any previous
        let content = UNMutableNotificationContent()
        content.title = "Live Poker Session Running"
        let elapsed = Int(liveSession.elapsedTime)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        let timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        content.body = "Time: \(timeString)\nBuy-in: $\(Int(liveSession.buyIn))"
        content.sound = .default
        // Show immediately and repeat every 60 seconds
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true)
        let request = UNNotificationRequest(identifier: "LiveSessionNotification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling live session notification: \(error)")
            }
        }
    }
    private func removeLiveSessionNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["LiveSessionNotification"])
    }
    
    deinit {
        stopLiveSessionTimer()
    }
} 