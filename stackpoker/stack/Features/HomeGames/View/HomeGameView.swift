import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Model for a home game
struct HomeGame: Identifiable, Codable {
    var id: String
    var title: String
    var createdAt: Date
    var creatorId: String
    var creatorName: String
    var groupId: String?
    var linkedEventId: String?
    var playerIds: [String]?
    var status: GameStatus
    var players: [Player]
    var buyInRequests: [BuyInRequest]
    var cashOutRequests: [CashOutRequest]
    var gameHistory: [GameEvent]
    var settlementTransactions: [SettlementTransaction]?
    var smallBlind: Double?
    var bigBlind: Double?
    
    // Computed property for stakes display
    var stakesDisplay: String {
        if let sb = smallBlind, let bb = bigBlind {
            return "$\(Int(sb))/$\(Int(bb))"
        }
        return "Stakes not set"
    }
    
    enum GameStatus: String, Codable {
        case active, completed
    }
    
    struct Player: Identifiable, Codable {
        var id: String
        var userId: String
        var displayName: String
        var currentStack: Double
        var totalBuyIn: Double
        var joinedAt: Date
        var cashedOutAt: Date?
        var status: PlayerStatus
        
        enum PlayerStatus: String, Codable {
            case active, cashedOut
        }

        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "id": id,
                "userId": userId,
                "displayName": displayName,
                "currentStack": currentStack,
                "totalBuyIn": totalBuyIn,
                "joinedAt": Timestamp(date: joinedAt),
                "status": status.rawValue
            ]
            if let cashedOutAt = cashedOutAt {
                dict["cashedOutAt"] = Timestamp(date: cashedOutAt)
            }
            return dict
        }
    }
    
    struct BuyInRequest: Identifiable, Codable {
        var id: String
        var userId: String
        var displayName: String
        var amount: Double
        var requestedAt: Date
        var status: RequestStatus
        
        enum RequestStatus: String, Codable {
            case pending, approved, rejected
        }
    }
    
    struct CashOutRequest: Identifiable, Codable {
        var id: String
        var userId: String
        var displayName: String
        var amount: Double
        var requestedAt: Date
        var processedAt: Date?
        var status: RequestStatus
        
        enum RequestStatus: String, Codable {
            case pending, processed
        }
    }
    
    struct GameEvent: Identifiable, Codable {
        var id: String
        var timestamp: Date
        var eventType: EventType
        var userId: String
        var userName: String
        var amount: Double?
        var description: String
        
        enum EventType: String, Codable {
            case playerJoined, playerLeft, buyIn, cashOut, gameCreated, gameEnded
        }
    }
    
    struct SettlementTransaction: Identifiable, Codable {
        var id: String
        var fromPlayer: String
        var toPlayer: String
        var amount: Double
        var index: Int
        
        func toDictionary() -> [String: Any] {
            return [
                "id": id,
                "fromPlayer": fromPlayer,
                "toPlayer": toPlayer,
                "amount": amount,
                "index": index
            ]
        }
    }
    
    // MARK: - Game Invites
    struct GameInvite: Identifiable, Codable {
        var id: String
        var gameId: String
        var gameTitle: String
        var hostId: String
        var hostName: String
        var invitedUserId: String
        var invitedUserDisplayName: String
        var invitedGroupId: String? // For group invites
        var invitedGroupName: String? // For group invites
        var message: String?
        var createdAt: Date
        var status: InviteStatus
        var respondedAt: Date?
        
        enum InviteStatus: String, CaseIterable, Codable {
            case pending = "pending"
            case accepted = "accepted"
            case declined = "declined"
            case expired = "expired"
        }
        
        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "id": id,
                "gameId": gameId,
                "gameTitle": gameTitle,
                "hostId": hostId,
                "hostName": hostName,
                "invitedUserId": invitedUserId,
                "invitedUserDisplayName": invitedUserDisplayName,
                "createdAt": Timestamp(date: createdAt),
                "status": status.rawValue
            ]
            
            if let message = message {
                dict["message"] = message
            }
            if let invitedGroupId = invitedGroupId {
                dict["invitedGroupId"] = invitedGroupId
            }
            if let invitedGroupName = invitedGroupName {
                dict["invitedGroupName"] = invitedGroupName
            }
            if let respondedAt = respondedAt {
                dict["respondedAt"] = Timestamp(date: respondedAt)
            }
            
            return dict
        }
    }
}

struct HomeGameView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var userService: UserService
    @StateObject private var homeGameService = HomeGameService()
    
    let groupId: String?
    let onGameCreated: ((HomeGame) -> Void)?
    
    @State private var gameTitle = ""
    @State private var smallBlind = ""
    @State private var bigBlind = ""
    @State private var isCreating = false
    @State private var error: String?
    @State private var showError = false
    @State private var existingActiveGame: HomeGame?
    @State private var isCheckingForExistingGames = true
    
    init(groupId: String?, onGameCreated: ((HomeGame) -> Void)? = nil) {
        self.groupId = groupId
        self.onGameCreated = onGameCreated
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                if isCheckingForExistingGames {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Checking for active games...")
                            .foregroundColor(.white)
                            .padding(.top, 16)
                    }
                } else if let activeGame = existingActiveGame {
                    // Show existing active game message
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Top spacer for navigation bar clearance
                            Color.clear.frame(height: 30)
                            
                            VStack(spacing: 24) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                Text("Active Game Exists")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                Text("You already have an active game: \"\(activeGame.title)\"")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                Text("Only one active game can run at a time. Please complete your current game before creating a new one.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                Spacer()
                                
                                Button(action: {
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Text("Go Back")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(Color(red: 123/255, green: 255/255, blue: 99/255))
                                        .cornerRadius(16)
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                            }
                        }
                        .padding(.top, 16)
                        .frame(minHeight: UIScreen.main.bounds.height - 100)
                    }
                } else {
                    // Normal game creation view
                    VStack(spacing: 0) {
                        // Fixed input section at top
                        VStack(spacing: 16) {
                            GlassyInputField(
                                icon: "gamecontroller.fill",
                                title: "GAME TITLE",
                                labelColor: .white.opacity(0.8)
                            ) {
                                TextField("Enter game title", text: $gameTitle)
                                    .foregroundColor(.white)
                                    .font(.system(size: 17, design: .rounded))
                                    .padding(.vertical, 8)
                            }
                            HStack(spacing: 12) {
                                GlassyInputField(
                                    icon: "dollarsign.circle.fill",
                                    title: "SMALL BLIND",
                                    labelColor: .white.opacity(0.8)
                                ) {
                                    TextField("$1", text: $smallBlind)
                                        .font(.system(size: 16, design: .rounded))
                                        .keyboardType(.decimalPad)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                }
                                GlassyInputField(
                                    icon: "dollarsign.circle.fill",
                                    title: "BIG BLIND",
                                    labelColor: .white.opacity(0.8)
                                ) {
                                    TextField("$2", text: $bigBlind)
                                        .font(.system(size: 16, design: .rounded))
                                        .keyboardType(.decimalPad)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        
                        // Scrollable content area
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 32) {
                                    Text("What you get")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.top, 40)
                                    VStack(alignment: .leading, spacing: 24) {
                                        Text("• Manage buy-ins and cash-outs")
                                            .font(.system(size: 22, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                        Text("• Access ledger and optimized settlement")
                                            .font(.system(size: 22, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                        Text("• Invite in-app users instantly")
                                            .font(.system(size: 22, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                        Text("• Share web link for off-app users")
                                            .font(.system(size: 22, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 60)
                            }
                            .frame(minHeight: UIScreen.main.bounds.height - 300)
                        }
                        
                        // Fixed create button at bottom
                        Button(action: createGame) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Create Game")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                gameTitle.isEmpty || isCreating
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(16)
                        }
                        .disabled(gameTitle.isEmpty || isCreating)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                    .ignoresSafeArea(.keyboard)
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .navigationBarTitle("Create Home Game", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .foregroundColor(.white)
                }
            )
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(error ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                checkForExistingGames()
            }
        }
    }
    
    private func checkForExistingGames() {
        guard let currentUser = Auth.auth().currentUser else {
            isCheckingForExistingGames = false
            return
        }
        
        isCheckingForExistingGames = true
        
        Task {
            do {
                // Check for ANY active games created by this user (both group and standalone)
                let activeGames = try await homeGameService.fetchActiveGames(createdBy: currentUser.uid)
                
                await MainActor.run {
                    if let firstActiveGame = activeGames.first {
                        existingActiveGame = firstActiveGame
                    } else {
                        existingActiveGame = nil
                    }
                    isCheckingForExistingGames = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to check for existing games: \(error.localizedDescription)"
                    showError = true
                    isCheckingForExistingGames = false
                }
            }
        }
    }
    
    private func createGame() {
        guard !gameTitle.isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                guard let currentUser = Auth.auth().currentUser else {
                    // Handle not authenticated
                    isCreating = false
                    return
                }

                // Double-check for existing active games created by this user (both group and standalone)
                let activeGames = try await homeGameService.fetchActiveGames(createdBy: currentUser.uid)
                if !activeGames.isEmpty {
                    await MainActor.run {
                        existingActiveGame = activeGames.first
                        isCreating = false
                        // Refresh the UI to show the existing game message
                        isCheckingForExistingGames = true // Trigger re-check which will show the message
                        checkForExistingGames()
                    }
                    return
                }

                // Fetch creator's name
                let userDoc = try await Firestore.firestore().collection("users").document(currentUser.uid).getDocument()
                let creatorName = userDoc.data()?["displayName"] as? String ?? userDoc.data()?["username"] as? String ?? "Unknown"
                
                let creatorInfo = HomeGameService.PlayerInfo(userId: currentUser.uid, displayName: creatorName)

                // Create the game in Firestore (groupId can be nil here)
                let newGame = try await homeGameService.createHomeGame(
                    title: gameTitle,
                    creatorId: currentUser.uid,
                    creatorName: creatorName,
                    initialPlayers: [creatorInfo],
                    smallBlind: parseStakesValue(smallBlind),
                    bigBlind: parseStakesValue(bigBlind),
                    groupId: groupId
                )
                
                // Call the completion handler with the new game if provided
                await MainActor.run {
                    onGameCreated?(newGame)
                    
                    // Post a notification to update the standalone game bar
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RefreshStandaloneHomeGame"),
                        object: nil
                    )
                    
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to create game: \(error.localizedDescription)"
                    showError = true
                    isCreating = false
                }
            }
        }
    }
    
    private func parseStakesValue(_ stakes: String) -> Double? {
        let cleanedStakes = stakes.replacingOccurrences(of: "$", with: "")
        return Double(cleanedStakes)
    }
}

// Helper extension for placeholder text
extension View {
    func placeholders<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholders: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholders().opacity(shouldShow ? 1 : 0)
            self
        }
    }
} 
