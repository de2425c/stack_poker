import SwiftUI
import FirebaseAuth

// Model for a home game
struct HomeGame: Identifiable, Codable {
    var id: String
    var title: String
    var createdAt: Date
    var creatorId: String
    var creatorName: String
    var groupId: String
    var status: GameStatus
    var players: [Player]
    var buyInRequests: [BuyInRequest]
    var cashOutRequests: [CashOutRequest]
    var gameHistory: [GameEvent]
    
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
}

struct HomeGameView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var userService: UserService
    @StateObject private var homeGameService = HomeGameService()
    
    let groupId: String
    let onGameCreated: (HomeGame) -> Void
    
    @State private var gameTitle = ""
    @State private var isCreating = false
    @State private var error: String?
    @State private var showError = false
    @State private var existingActiveGame: HomeGame?
    @State private var isCheckingForExistingGames = true
    
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
                    VStack(spacing: 24) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .padding(.top, 40)
                        
                        Text("Active Game Exists")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("There is already an active game in this group: \"\(activeGame.title)\"")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Text("Only one active game can run at a time. Please wait until the current game is completed before creating a new one.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
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
                } else {
                    // Normal game creation view
                    VStack(spacing: 24) {
                        // Game title input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GAME TITLE")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 4)
                            
                            TextField("", text: $gameTitle)
                                .placeholders(when: gameTitle.isEmpty) {
                                    Text("Enter game title").foregroundColor(.gray.opacity(0.7))
                                }
                                .font(.system(size: 17))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.1),
                                                    Color.clear,
                                                    Color.clear,
                                                    Color.clear
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .foregroundColor(.white)
                        }
                        
                        // Game rules explanation
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Home Game Rules")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "1.circle.fill")
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .font(.system(size: 20))
                                
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
                                Image(systemName: "2.circle.fill")
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .font(.system(size: 20))
                                
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
                                Image(systemName: "3.circle.fill")
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .font(.system(size: 20))
                                
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
                                Image(systemName: "4.circle.fill")
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .font(.system(size: 20))
                                
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
                        
                        Spacer()
                        
                        // Create button
                        Button(action: createGame) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Create Game")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                gameTitle.isEmpty || isCreating
                                    ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                    : Color(red: 123/255, green: 255/255, blue: 99/255)
                            )
                            .cornerRadius(16)
                        }
                        .disabled(gameTitle.isEmpty || isCreating)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
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
                // Double-check for existing active games
                let activeGames = try await homeGameService.fetchActiveGamesForGroup(groupId: groupId)
                
                if !activeGames.isEmpty {
                    // There's already an active game, show error
                    await MainActor.run {
                        existingActiveGame = activeGames.first
                        isCreating = false
                        checkForExistingGames() // Refresh the UI
                    }
                    return
                }
                
                // Create the game in Firestore
                let newGame = try await homeGameService.createHomeGame(title: gameTitle, groupId: groupId)
                
                // Call the completion handler with the new game
                await MainActor.run {
                    onGameCreated(newGame)
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
