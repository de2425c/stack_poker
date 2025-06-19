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
                                
                                Text("There is already an active game in this group: \"\(activeGame.title)\"")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                Text("Only one active game can run at a time. Please wait until the current game is completed before creating a new one.")
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
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Top spacer for navigation bar clearance - ADD MORE PADDING
                            Color.clear.frame(height: 80)
                            
                            VStack(alignment: .leading, spacing: 24) {
                                // Game title input using GlassyInputField
                                GlassyInputField(
                                    icon: "gamecontroller.fill",
                                    title: "GAME TITLE",
                                    labelColor: .white.opacity(0.8)
                                ) {
                                    TextField("", text: $gameTitle)
                                        .placeholders(when: gameTitle.isEmpty) {
                                            Text("Enter game title").foregroundColor(.gray.opacity(0.7))
                                        }
                                        .font(.system(size: 17))
                                        .padding(.vertical, 10)
                                        .foregroundColor(.white)
                                }
                                
                                // Stakes input section using GlassyInputField
                                HStack(spacing: 12) {
                                    // Small Blind
                                    GlassyInputField(
                                        icon: "dollarsign.circle.fill",
                                        title: "SMALL BLIND",
                                        labelColor: .white.opacity(0.8)
                                    ) {
                                        TextField("", text: $smallBlind)
                                            .placeholders(when: smallBlind.isEmpty) {
                                                Text("$1").foregroundColor(.gray.opacity(0.7))
                                            }
                                            .font(.system(size: 16))
                                            .keyboardType(.decimalPad)
                                            .foregroundColor(.white)
                                            .padding(.vertical, 10)
                                    }
                                    
                                    // Big Blind
                                    GlassyInputField(
                                        icon: "dollarsign.circle.fill",
                                        title: "BIG BLIND",
                                        labelColor: .white.opacity(0.8)
                                    ) {
                                        TextField("", text: $bigBlind)
                                            .placeholders(when: bigBlind.isEmpty) {
                                                Text("$2").foregroundColor(.gray.opacity(0.7))
                                            }
                                            .font(.system(size: 16))
                                            .keyboardType(.decimalPad)
                                            .foregroundColor(.white)
                                            .padding(.vertical, 10)
                                    }
                                }
                                
                                // Stakes preview (minimal styling)
                                if !smallBlind.isEmpty && !bigBlind.isEmpty,
                                   let sb = Double(smallBlind.replacingOccurrences(of: "$", with: "")),
                                   let bb = Double(bigBlind.replacingOccurrences(of: "$", with: "")) {
                                    Text("Stakes: $\(Int(sb))/$\(Int(bb))")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.top, 8)
                                }
                                
                                // Game rules explanation (minimal styling)
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("How it works")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("1")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                            .frame(width: 24, alignment: .center)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Create the game")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text("Give your game a descriptive title")
                                                .font(.system(size: 14))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("2")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                            .frame(width: 24, alignment: .center)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Players join")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text("Group members can request to join and buy in")
                                                .font(.system(size: 14))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("3")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                            .frame(width: 24, alignment: .center)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Track chips and cashouts")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text("Manage buy-ins and cashouts for each player")
                                                .font(.system(size: 14))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("4")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                            .frame(width: 24, alignment: .center)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Game summary")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text("When everyone cashes out, a summary is posted")
                                                .font(.system(size: 14))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                Spacer(minLength: 40)
                                
                                // Create button (minimal styling)
                                Button(action: createGame) {
                                    HStack {
                                        if isCreating {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .frame(width: 20, height: 20)
                                                .padding(.horizontal, 10)
                                        } else {
                                            Text("Create Game")
                                                .font(.system(size: 17, weight: .semibold))
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
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 60)  // Add bottom padding to button
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                        .padding(.top, 16)
                        .frame(minHeight: UIScreen.main.bounds.height - 100)
                    }
                    .ignoresSafeArea(.keyboard)  // Ensure keyboard doesn't push content
                    .onTapGesture {  // Add tap to dismiss keyboard
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
                if let currentGroupId = groupId {
                    checkForExistingGames(groupId: currentGroupId)
                } else {
                    // For standalone games (groupId is nil), no group-specific check needed.
                    isCheckingForExistingGames = false
                    existingActiveGame = nil
                }
            }
        }
    }
    
    private func checkForExistingGames(groupId: String) {
        isCheckingForExistingGames = true
        
        Task {
            do {
                let activeGames = try await homeGameService.fetchActiveGamesForGroup(groupId: groupId)
                
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

                // If part of a group, double-check for existing active games in that group
                if let currentGroupId = groupId {
                    let activeGames = try await homeGameService.fetchActiveGamesForGroup(groupId: currentGroupId)
                    if !activeGames.isEmpty {
                        await MainActor.run {
                            existingActiveGame = activeGames.first
                            isCreating = false
                            // Refresh the UI to show the existing game message
                            isCheckingForExistingGames = true // Trigger re-check which will show the message
                            checkForExistingGames(groupId: currentGroupId)
                        }
                        return
                    }
                } // For standalone games, this check is skipped.

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
