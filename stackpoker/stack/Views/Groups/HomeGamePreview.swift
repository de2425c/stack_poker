import SwiftUI
import FirebaseAuth
import PhotosUI // Keep if used elsewhere in the file
import Combine // Keep if used elsewhere in the file
import Foundation // Keep if used elsewhere in the file
import FirebaseFirestore // Add this import

struct HomeGamePreview: View {
    let gameId: String
    let ownerId: String
    let groupId: String
    
    @State private var game: HomeGame?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showError = false
    @State private var showingGameDetail = false
    @State private var showingBuyInSheet = false
    @State private var buyInAmount: String = ""
    @State private var showingHostRebuySheet = false
    @State private var showingEndGameSheet = false
    @State private var selectedPlayer: HomeGame.Player?
    @State private var liveGame: HomeGame?
    @State private var showingCashOutSheet = false
    @State private var isProcessingAction = false
    
    @StateObject private var homeGameService = HomeGameService()
    
    // Helper to determine if current user is the game creator
    private var isGameCreator: Bool {
        return ownerId == Auth.auth().currentUser?.uid
    }
    
    // Helper to determine if current user is already a player
    private var isCurrentPlayerActive: Bool {
        guard let game = game else { return false }
        return game.players.contains(where: { 
            $0.userId == Auth.auth().currentUser?.uid && $0.status == .active 
        })
    }
    
    // Helper to determine if current user has a pending buy-in request
    private var hasPendingBuyInRequest: Bool {
        guard let game = game else { return false }
        return game.buyInRequests.contains(where: { 
            $0.userId == Auth.auth().currentUser?.uid && $0.status == .pending 
        })
    }
    
    // Format currency helper
    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
    
    private func setupLiveUpdates() {
        isLoading = true
        
        homeGameService.listenForGameUpdates(gameId: gameId) { updatedGame in
            DispatchQueue.main.async {
                self.game = updatedGame
                self.isLoading = false
            }
        }
    }
    
    private func requestCashOut(amount: Double) {
        isProcessingAction = true
        error = nil
        
        Task {
            do {
                try await homeGameService.requestCashOut(gameId: gameId, amount: amount)
                await MainActor.run {
                    isProcessingAction = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to request cash out: \(error.localizedDescription)"
                    isProcessingAction = false
                }
            }
        }
    }
    
    var body: some View {
        Button(action: {
            showingGameDetail = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                } else if let game = game {
                    // Game header with title and status
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Created by \(game.creatorName)")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Status badge
                        Text(game.status == .active ? "ACTIVE" : "FINISHED")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(game.status == .active ? 
                                          Color(red: 123/255, green: 255/255, blue: 99/255) : 
                                          Color.gray)
                            )
                    }
                    
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    // Players section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("PLAYERS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Text("\(game.players.filter { $0.status == .active }.count) active")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        if game.players.filter({ $0.status == .active }).isEmpty {
                            Text("No active players")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .padding(.vertical, 4)
                        } else {
                            // Show up to 3 players, with a "+X more" if needed
                            let activePlayers = game.players.filter { $0.status == .active }
                            let displayPlayers = Array(activePlayers.prefix(3))
                            
                            ForEach(displayPlayers) { player in
                                HStack {
                                    Text(player.displayName)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text(formatMoney(player.currentStack))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                }
                                .padding(.vertical, 2)
                            }
                            
                            if activePlayers.count > 3 {
                                Text("+ \(activePlayers.count - 3) more players")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    
                    // Status text based on game state and user role
                    HStack {
                        // Short status text
                            if isCurrentPlayerActive {
                            Text("You're playing")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            } else if hasPendingBuyInRequest {
                            Text("Buy-in pending")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                        } else if isGameCreator {
                            Text("You're the host")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        } else if game.status == .completed {
                            Text("Game finished")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            } else {
                            Text("Tap to join")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                        
                        Spacer()
                        
                        // Chevron to indicate interactive element
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 4)
                } else {
                    Text(error ?? "Game not available")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1),
                                Color.clear,
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingGameDetail) {
            if let game = game {
                HomeGameDetailView(game: game, onGameUpdated: {
                    // This will be handled by the listener now
                })
            }
        }
        .sheet(isPresented: $showingBuyInSheet) {
            BuyInView(gameId: gameId, onComplete: {
                // This will be handled by the listener now
            })
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(error ?? "An unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            setupLiveUpdates()
        }
        .onDisappear {
            homeGameService.stopListeningForGameUpdates(gameId: gameId)
        }
        .sheet(isPresented: $showingCashOutSheet) {
            if let game = game,
               let player = game.players.first(where: { $0.userId == Auth.auth().currentUser?.uid && $0.status == .active }) {
                PlayerCashoutView(player: player) { amount in
                    requestCashOut(amount: amount)
                }
            }
        }
    }
}

// BuyIn view to request joining a game
struct BuyInView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let gameId: String
    let onComplete: () -> Void
    
    @State private var buyInAmount: String = ""
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showError = false
        
        @StateObject private var homeGameService = HomeGameService()
        
        private var isHost: Bool {
            guard let game = game else { return false }
            return Auth.auth().currentUser?.uid == game.creatorId
        }
        
        @State private var game: HomeGame?
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Request Buy-In")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Amount input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BUY-IN AMOUNT")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .padding(.leading, 4)
                        
                        HStack {
                            Text("$")
                                .foregroundColor(.white)
                                .font(.system(size: 17))
                            
                            TextField("", text: $buyInAmount)
                                .placeholder(when: buyInAmount.isEmpty) {
                                    Text("Enter amount").foregroundColor(.gray.opacity(0.7))
                                }
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .keyboardType(.numberPad)
                        }
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
                    }
                    
                    Text("Your buy-in request will be sent to the game creator for approval.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    // Submit button
                    Button(action: submitBuyIn) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .frame(width: 20, height: 20)
                                    .padding(.horizontal, 10)
                            } else {
                                Text("Submit Request")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 54)
                        .background(
                            !isValidAmount() || isProcessing
                                ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                : Color(red: 123/255, green: 255/255, blue: 99/255)
                        )
                        .cornerRadius(16)
                    }
                    .disabled(!isValidAmount() || isProcessing)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .navigationBarTitle("Buy In", displayMode: .inline)
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
                    fetchGame()
            }
        }
    }
    
    private func isValidAmount() -> Bool {
        guard let amount = Double(buyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
              amount > 0 else {
            return false
        }
        return true
    }
    
    private func submitBuyIn() {
        guard isValidAmount() else { return }
        guard let amount = Double(buyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        
        isProcessing = true
        
        Task {
            do {
                    // Check if user is host to use direct buy-in
                    if isHost {
                        try await homeGameService.hostBuyIn(gameId: gameId, amount: amount)
                    } else {
                try await homeGameService.requestBuyIn(gameId: gameId, amount: amount)
                    }
                
                await MainActor.run {
                    isProcessing = false
                    onComplete()
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    self.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
        
        // Add a function to fetch the game to check if user is host
        private func fetchGame() {
            Task {
                do {
                    self.game = try await homeGameService.fetchHomeGame(gameId: gameId)
                } catch {
                    print("Error fetching game: \(error.localizedDescription)")
            }
        }
    }
}

// Update HomeGameDetailView to include functionality for the owner
struct HomeGameDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var sessionStore: SessionStore // Inject SessionStore
    @StateObject private var homeGameService = HomeGameService()
    
    let game: HomeGame
    var onGameUpdated: (() -> Void)? = nil
    
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showError = false
    @State private var showingEndGameConfirmation = false
    @State private var showingRebuySheet = false
    @State private var showingBuyInSheet = false
    @State private var showingCashOutSheet = false
    @State private var showingHostRebuySheet = false
    @State private var showingEndGameSheet = false
    @State private var selectedPlayer: HomeGame.Player?
    @State private var liveGame: HomeGame?
    @State private var showCopiedMessage = false // Keep this for confirmation
    
    // State for Save Session feature
    @State private var previousGame: HomeGame? // To detect status change
    @State private var justCashedOutPlayer: HomeGame.Player? // To hold data for saving
    @State private var showingSaveSessionAlert = false
    @State private var showingSaveSessionSheet = false
    
    // Helper to determine if current user is the game creator
    private var isGameCreator: Bool {
        return game.creatorId == Auth.auth().currentUser?.uid
    }
    
    // Helper to determine if current user is a player
    private var isCurrentPlayerActive: Bool {
        return game.players.contains(where: {
            $0.userId == Auth.auth().currentUser?.uid && $0.status == .active
        })
    }
    
    // Helper to determine if current user has a pending buy-in request
    private var hasPendingBuyInRequest: Bool {
        guard let liveGame = liveGame else { return false }
        return liveGame.buyInRequests.contains(where: {
            $0.userId == Auth.auth().currentUser?.uid && $0.status == .pending
        })
    }
    

    
    // Add this property to store the activity items
    @State private var activityItems: [Any] = []
    
    // Updated function to copy the link
    private func copyGameLink() {
        let gameId = (liveGame ?? game).id
        let shareURLString = "https://stackpoker.gg/games/\(gameId)"
        UIPasteboard.general.string = shareURLString
        
        // Show confirmation message briefly
        Task {
            await MainActor.run { // Explicitly run on main thread
                showCopiedMessage = true
            }
            // Hide after 2 seconds
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) 
            await MainActor.run { // Explicitly run on main thread
                showCopiedMessage = false
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                        if game.status == .completed {
                            // Show game summary for completed games
                            gameSummaryView
                        } else if isGameCreator {
                            // Show owner management view for active games
                            ownerView
                        } else {
                            // Show player view for active games
                            playerView
                        }
                    }
                    .refreshable {
                        refreshGame()
                    }
                }
                .navigationBarTitle(
                    game.status == .completed ? "Game Summary" :
                        (isGameCreator ? "Game Management" : "Game Details"),
                    displayMode: .inline
                )
                .navigationBarItems(
                    leading: Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Close")
                            .foregroundColor(.white)
                    },
                    trailing: isGameCreator && game.status == .active ? 
                        Button(action: copyGameLink) { // Changed action here
                            Image(systemName: "link") // Changed icon to 'link'
                                .foregroundColor(.white)
                        }
                        .help("Copy game link")
                        .accessibilityLabel("Copy game link") : nil
                )
                .alert(isPresented: $showError) {
                    Alert(
                        title: Text("Error"),
                        message: Text(error ?? "An unknown error occurred"),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .alert("End Game?", isPresented: $showingEndGameConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("End Game", role: .destructive) {
                        endGame()
                    }
                } message: {
                    Text("This will end the current game for all players. Any players who haven't cashed out will need to be handled manually. This action cannot be undone.")
                }
                .sheet(isPresented: $showingRebuySheet) {
                    RebuyView(gameId: (liveGame ?? game).id, onComplete: {
                        refreshGame()
                    })
                }
                .sheet(isPresented: $showingBuyInSheet) {
                    BuyInView(gameId: (liveGame ?? game).id, onComplete: {
                        refreshGame()
                    })
                }
                .sheet(isPresented: $showingCashOutSheet) {
                    CashOutView(gameId: (liveGame ?? game).id, currentStack: (liveGame ?? game).players.first(where: { $0.userId == Auth.auth().currentUser?.uid })?.currentStack ?? 0, onComplete: {
                        refreshGame()
                    })
                }
                .sheet(isPresented: $showingHostRebuySheet) {
                    HostRebuyView(gameId: (liveGame ?? game).id, onComplete: {
                        refreshGame()
                    })
                }
                .sheet(isPresented: $showingEndGameSheet) {
                    GameEndView(gameId: (liveGame ?? game).id, onComplete: {
                        refreshGame()
                    })
                }
                .onAppear {
                    setupLiveUpdates()
                }
                .onDisappear {
                    // Clean up listeners when view disappears
                    homeGameService.stopListeningForGameUpdates()
                }
                // ADD Alert modifier HERE
                .alert("Session Complete", isPresented: $showingSaveSessionAlert, presenting: justCashedOutPlayer) { player in
                     Button("Save Session") {
                         showingSaveSessionAlert = false
                         showingSaveSessionSheet = true 
                     }
                     Button("Dismiss", role: .cancel) { 
                         justCashedOutPlayer = nil
                         showingSaveSessionAlert = false
                     }
                } message: { player in
                     let pnl = player.currentStack - player.totalBuyIn
                     let duration = player.cashedOutAt?.timeIntervalSince(player.joinedAt) ?? 0
                     let formattedPNL = formatMoney(pnl)
                     let formattedDuration = formatDuration(duration)
                     
                     Text("You cashed out!\nDuration: \(formattedDuration)\nProfit/Loss: \(formattedPNL)\n\nWould you like to save this session?")
                }
                // ADD Sheet modifier HERE
                .sheet(isPresented: $showingSaveSessionSheet) {
                    if let player = justCashedOutPlayer,
                       let cashoutTime = player.cashedOutAt {
                        let pnl = player.currentStack - player.totalBuyIn
                        let duration = cashoutTime.timeIntervalSince(player.joinedAt)
                        
                        // Pass data to the saving view, including buyIn and cashOut separately
                        SaveHomeGameSessionView(
                            pnl: pnl,
                            buyIn: player.totalBuyIn,
                            cashOut: player.currentStack,
                            duration: duration,
                            date: cashoutTime
                        )
                        .environmentObject(sessionStore)
                    } else {
                        // Fallback view if data is missing
                        Text("Error: Missing session data to save.")
                    }
                }
            } // End NavigationView
        }
        
        private func setupLiveUpdates() {
            // Initialize previousGame state on setup
            self.previousGame = liveGame ?? game
            
            // Start listening for updates to the game
            homeGameService.listenForGameUpdates(gameId: game.id) { updatedGame in
                DispatchQueue.main.async {
                    self.liveGame = updatedGame
                    // Call the completion handler to update parent views if needed
                    self.onGameUpdated?()
                    
                    // Check if the current user just cashed out
                    guard let userId = Auth.auth().currentUser?.uid else { return }
                    
                    let previousStatus = previousGame?.players.first { $0.userId == userId }?.status
                    let currentStatus = updatedGame.players.first { $0.userId == userId }?.status
                    
                    if previousStatus == .active && currentStatus == .cashedOut {
                        if let player = updatedGame.players.first(where: { $0.userId == userId }) {
                            self.justCashedOutPlayer = player
                            self.showingSaveSessionAlert = true
                        }
                    }
                    
                    // Update previousGame state for the next comparison
                    self.previousGame = updatedGame
                }
            }
        }
        
        private func refreshGame() {
            Task {
                do {
                    if let refreshedGame = try await homeGameService.fetchHomeGame(gameId: game.id) {
                        await MainActor.run {
                            liveGame = refreshedGame
                            onGameUpdated?()
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        
        // OWNER VIEW - Game management interface
        private var ownerView: some View {
            VStack(spacing: 25) {
                // Game header with management controls
                VStack(spacing: 16) {
                    // Game status header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Created \(formatDate(game.createdAt))")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                            
                        Spacer()
                        
                                // Status badge
                                Text(game.status == .active ? "ACTIVE" : "FINISHED")
                            .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(game.status == .active ? 
                                                  Color(red: 123/255, green: 255/255, blue: 99/255) : 
                                                  Color.gray)
                                    )
                    }
                    .padding(.horizontal, 16)
                    
                    // Game summary stats
                    HStack(spacing: 0) {
                        statBox(
                            title: "PLAYERS",
                            value: "\(game.players.filter { $0.status == .active }.count)",
                            subtitle: "active"
                        )
                        
                        Divider()
                            .frame(width: 1)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 8)
                        
                        statBox(
                            title: "BUY-INS",
                            value: "$\(getTotalBuyIns())",
                            subtitle: "total"
                        )
                        
                        Divider()
                            .frame(width: 1)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 8)
                        
                        statBox(
                            title: "TIME",
                            value: getGameDuration(),
                            subtitle: "duration"
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                    )
                        .padding(.horizontal, 16)
                        
                    // Owner actions row
                    HStack(spacing: 20) {
                        // Self buy-in button (if owner hasn't joined yet)
                        if !game.players.contains(where: { $0.userId == Auth.auth().currentUser?.uid }) && game.status == .active {
                            Button(action: {
                                showingBuyInSheet = true
                            }) {
                                Text("Buy In")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                        } else if game.players.contains(where: {
                            $0.userId == Auth.auth().currentUser?.uid &&
                            $0.status == .active
                        }) && game.status == .active {
                            // Host rebuy button
                            Button(action: {
                                showingHostRebuySheet = true
                            }) {
                                Text("Add Chips")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                            .disabled(isProcessing)
                        }
                        
                        // End game button (if active)
                        if game.status == .active {
                            Button(action: {
                                showingEndGameSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "flag.checkered")
                                    .font(.system(size: 16))
                                    
                                    Text("End Game")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.red.opacity(0.7))
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                // Pending requests section
                if game.status == .active && !game.buyInRequests.filter({ $0.status == .pending }).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pending Buy-In Requests")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                
                                ForEach(game.buyInRequests.filter { $0.status == .pending }) { request in
                                    BuyInRequestRow(
                                        request: request, 
                                        isProcessing: isProcessing,
                                        onApprove: { 
                                            approveBuyIn(requestId: request.id)
                                        },
                                        onDecline: { 
                                    declineBuyIn(requestId: request.id)
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                
                // Pending cash-out requests section
                if game.status == .active && !game.cashOutRequests.filter({ $0.status == .pending }).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pending Cash-Out Requests")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                        
                        ForEach(game.cashOutRequests.filter { $0.status == .pending }) { request in
                            CashOutRequestRow(
                                request: request,
                                isProcessing: isProcessing,
                                onProcess: {
                                    processCashOut(requestId: request.id)
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                
                // Active players section (with detailed controls for owner)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Players")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                    
                    if game.players.filter({ $0.status == .active }).isEmpty {
                        Text("No active players")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(game.players.filter { $0.status == .active }) { player in
                            OwnerPlayerRow(player: player, onManage: {
                                // Handle player management here instead of using showingGameDetail
                                // This could open a sheet or perform another action
                            })
                        }
                    }
                }
                .padding(.top, 8)
                        
                        // Game history section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Game History")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                            
                            ForEach(game.gameHistory.sorted(by: { $0.timestamp > $1.timestamp })) { event in
                                GameEventRow(event: event)
                            }
                        }
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        
        // PLAYER VIEW - Simplified game info and personal actions
        private var playerView: some View {
            VStack(spacing: 24) {
                // Game header
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Created by \(game.creatorName)")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    
                    HStack {
                        // Status badge
                        Text(game.status == .active ? "ACTIVE" : "FINISHED")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(game.status == .active ?
                                          Color(red: 123/255, green: 255/255, blue: 99/255) :
                                            Color.gray)
                            )
                        
                        Spacer()
                        
                        // Date
                        Text(formatDate(game.createdAt))
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                
                // Player's own status (if participating)
                if let currentPlayer = game.players.first(where: { $0.userId == Auth.auth().currentUser?.uid }) {
                    VStack(spacing: 16) {
                        // Your status header
                        Text("YOUR STATUS")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        
                        // Main stats
                        HStack(spacing: 30) {
                            VStack(spacing: 8) {
                                Text("$\(Int(currentPlayer.currentStack))")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Current Stack")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            VStack(spacing: 8) {
                                Text("$\(Int(currentPlayer.totalBuyIn))")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Total Buy-In")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            VStack(spacing: 8) {
                                let profit = currentPlayer.currentStack - currentPlayer.totalBuyIn
                                Text("\(profit >= 0 ? "+" : "")\(formatMoney(profit))")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(profit >= 0 ?
                                                     Color(red: 123/255, green: 255/255, blue: 99/255) :
                                                        Color.red)
                                
                                Text("Profit/Loss")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        // Action buttons (if active player)
                        if game.status == .active && currentPlayer.status == .active {
                            HStack(spacing: 20) {
                                // Rebuy button
                                Button(action: {
                                    showingRebuySheet = true
                                }) {
                                    Text("Rebuy")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                                .padding(.vertical, 12)
                                .frame(width: 120)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                                )
                                .disabled(isProcessing || hasPendingBuyInRequest)
                                
                                // Cash out button
                                Button(action: {
                                    showingCashOutSheet = true
                                }) {
                                    VStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 24))
                                        Text("Cash Out")
                                            .font(.system(size: 12))
                                    }
                        .foregroundColor(.white)
                }
                                .padding(.vertical, 12)
                                .frame(width: 120)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(UIColor(red: 50/255, green: 50/255, blue: 55/255, alpha: 1.0)))
                                )
                                .disabled(isProcessing)
                            }
                        } else if currentPlayer.status == .cashedOut {
                            Text("You have cashed out")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        
                        // Show pending rebuy request if applicable
                        if let pendingRequest = game.buyInRequests.first(where: {
                            $0.userId == Auth.auth().currentUser?.uid && $0.status == .pending
                        }) {
                            HStack {
                                Image(systemName: "hourglass")
                                    .foregroundColor(.orange)
                                
                                Text("Pending rebuy: $\(Int(pendingRequest.amount))")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                    )
                    .padding(.horizontal, 16)
                } else if game.status == .active &&
                            !game.buyInRequests.contains(where: { $0.userId == Auth.auth().currentUser?.uid && $0.status == .pending }) {
                    // Join game button (if not already participating or pending)
                    Button(action: {
                        showingBuyInSheet = true
                    }) {
                        Text("Join Game")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                    }
                    .padding(.horizontal, 16)
                } else if let pendingRequest = game.buyInRequests.first(where: {
                    $0.userId == Auth.auth().currentUser?.uid && $0.status == .pending
                }) {
                    // Show pending request status
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Buy-In Request Pending")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Requested: $\(Int(pendingRequest.amount))")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            
                            Text("Waiting for approval")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Spinner or status icon
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                    )
                    .padding(.horizontal, 16)
                }
                
                // Active players section (simplified for player view)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Players")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                    
                    if game.players.filter({ $0.status == .active }).isEmpty {
                        Text("No active players")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(game.players.filter { $0.status == .active }) { player in
                            PlayerRow(player: player)
                        }
                    }
                }
                
                // Game history section (simplified for player view)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Activity")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                    
                    // Only show last 5 events for players
                    ForEach(Array(game.gameHistory.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5))) { event in
                        GameEventRow(event: event)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        
        // Helper UI components
        private func statBox(title: String, value: String, subtitle: String) -> some View {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        
        // Helper methods
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
        private func formatMoney(_ amount: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
        }
        
        private func getTotalBuyIns() -> Int {
            let total = game.players.reduce(0) { $0 + $1.totalBuyIn }
            return Int(total)
        }
        
        private func getGameDuration() -> String {
            let now = Date()
            let duration = now.timeIntervalSince(game.createdAt)
            
            let hours = Int(duration) / 3600
            if hours > 0 {
                return "\(hours)h"
            } else {
                let minutes = Int(duration) / 60
                return "\(minutes)m"
            }
        }
        
        // Owner-specific actions
    private func approveBuyIn(requestId: String) {
        isProcessing = true
        
        Task {
            do {
                try await homeGameService.approveBuyIn(gameId: game.id, requestId: requestId)
                
                await MainActor.run {
                    isProcessing = false
                    onGameUpdated?()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    self.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
        
        private func declineBuyIn(requestId: String) {
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.declineBuyIn(gameId: game.id, requestId: requestId)
                    
                    await MainActor.run {
                        isProcessing = false
                        refreshGame()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        
        private func processCashOut(requestId: String) {
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.processCashOut(gameId: game.id, requestId: requestId)
                    
                    await MainActor.run {
                        isProcessing = false
                        onGameUpdated?()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        
        private func endGame() {
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.endGame(gameId: game.id)
                    
                    await MainActor.run {
                        isProcessing = false
                        onGameUpdated?()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        
        // Player-specific actions
        private func requestCashOut(amount: Double) {
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.requestCashOut(gameId: game.id, amount: amount)
                    
                    await MainActor.run {
                        isProcessing = false
                        onGameUpdated?()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        
        // Game summary ledger (shown for completed games)
        private var gameSummaryView: some View {
            VStack(spacing: 20) {
                Text("Game Summary")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
                
                // Game totals card
                VStack(spacing: 16) {
                    HStack {
                        Text("GAME TOTALS")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        
                        Spacer()
                        
                        Text(formatDate(game.createdAt))
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    // Summary stats
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Buy-ins")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            
                            Text(formatMoney(getTotalBuyIns()))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Total Cash-outs")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            
                            Text(formatMoney(getTotalCashOuts()))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    // Differences (should be zero in an ideal game)
                    let difference = getTotalCashOuts() - getTotalBuyIns()
                    HStack {
                        Text("Difference")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text("\(difference >= 0 ? "+" : "")\(formatMoney(difference))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(difference == 0 ? .white : (difference > 0 ? .green : .red))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                )
                .padding(.horizontal, 16)
                
                // Player ledger
                VStack(alignment: .leading, spacing: 12) {
                    Text("Player Ledger")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                    
                    // Column headers
                    HStack {
                        Text("PLAYER")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(width: 100, alignment: .leading)
                        
                        Spacer()
                        
                        Text("TIME")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(width: 70, alignment: .trailing)
                        
                        Text("BUY-IN")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(width: 80, alignment: .trailing)
                        
                        Text("CASH-OUT")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    
                    // Player rows
                    ForEach(getAllPlayers()) { player in
                        LedgerPlayerRow(player: player, gameStartTime: game.createdAt)
                    }
                }
                .padding(.top, 8)
                
                // Final settlement instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settlement Notes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Players should settle accounts directly with each other based on the above ledger. The game operator should verify that the total money in equals the total money out.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        
        // Get all players that participated in the game
        private func getAllPlayers() -> [HomeGame.Player] {
            return game.players
        }
        
        // Calculate total buy-ins
        private func getTotalBuyIns() -> Double {
            return game.players.reduce(0) { $0 + $1.totalBuyIn }
        }
        
        // Calculate total cash-outs
        private func getTotalCashOuts() -> Double {
            return game.players.reduce(0) { currentTotal, player in
                if player.status == .cashedOut {
                    return currentTotal + player.currentStack
                } else {
                    // For any players who didn't cash out (shouldn't happen in a completed game)
                    return currentTotal
                }
            }
        }
    }
    
    // Enhanced owner-specific player row with more detailed info and controls
    struct OwnerPlayerRow: View {
        let player: HomeGame.Player
        let onManage: () -> Void
        
        var body: some View {
            VStack(spacing: 12) {
                HStack {
                    // Player name and status
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Joined \(formatTime(player.joinedAt))")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Current stack
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$\(Int(player.currentStack))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        
                        let profit = player.currentStack - player.totalBuyIn
                        Text("\(profit >= 0 ? "+" : "")\(Int(profit))")
                            .font(.system(size: 12))
                            .foregroundColor(profit >= 0 ?
                                             Color(red: 123/255, green: 255/255, blue: 99/255) :
                                                Color.red)
                    }
                }
                
                // Buy-in history and manage button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOTAL BUY-IN")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text("$\(Int(player.totalBuyIn))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Owner controls - manage player
                    Button(action: onManage) {
                        Text("Manage")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(UIColor(red: 60/255, green: 60/255, blue: 70/255, alpha: 1.0)))
                            )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
            )
            .padding(.horizontal, 16)
        }
        
        private func formatTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    // Cash out request row for owner view
    struct CashOutRequestRow: View {
        let request: HomeGame.CashOutRequest
        let isProcessing: Bool
        let onProcess: () -> Void
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.displayName)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    
                    Text("Requesting cash-out of $\(Int(request.amount))")
                        .font(.system(size: 14))
                        .foregroundColor(Color.orange)
                }
                
                Spacer()
                
                // Action button
                Button(action: onProcess) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Process")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isProcessing ?
                              Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5) :
                                Color(red: 123/255, green: 255/255, blue: 99/255))
                )
                .disabled(isProcessing)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
            )
            .padding(.horizontal, 16)
    }
}

// Helper components for the HomeGameDetailView
struct PlayerRow: View {
    let player: HomeGame.Player
    
    var body: some View {
        HStack {
            Text(player.displayName)
                .font(.system(size: 16))
                .foregroundColor(.white)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Current: $\(Int(player.currentStack))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Text("Buy-in: $\(Int(player.totalBuyIn))")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
        )
        .padding(.horizontal, 16)
    }
}

struct BuyInRequestRow: View {
    let request: HomeGame.BuyInRequest
    let isProcessing: Bool
    let onApprove: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.displayName)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                
                Text("$\(Int(request.amount))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: onApprove) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Approve")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isProcessing ? 
                              Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5) : 
                              Color(red: 123/255, green: 255/255, blue: 99/255))
                )
                .disabled(isProcessing)
                
                Button(action: onDecline) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 16, height: 16)
                        } else {
                    Text("Decline")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor(red: 50/255, green: 50/255, blue: 55/255, alpha: 1.0)))
                )
                .disabled(isProcessing)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
        )
        .padding(.horizontal, 16)
    }
}

struct GameEventRow: View {
    let event: HomeGame.GameEvent
    
    var body: some View {
        HStack(spacing: 16) {
            // Event icon
            ZStack {
                Circle()
                    .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    .frame(width: 36, height: 36)
                
                Image(systemName: iconForEventType(event.eventType))
                    .font(.system(size: 16))
                    .foregroundColor(colorForEventType(event.eventType))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.description)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                
                Text(formatTime(event.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Amount if present
            if let amount = event.amount {
                Text(formatAmount(amount, eventType: event.eventType))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorForEventType(event.eventType))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
    
    private func iconForEventType(_ type: HomeGame.GameEvent.EventType) -> String {
        switch type {
        case .gameCreated: return "flag.fill"
        case .gameEnded: return "checkmark.circle.fill"
        case .playerJoined: return "person.fill.badge.plus"
        case .playerLeft: return "person.fill.badge.minus"
        case .buyIn: return "arrow.down.circle.fill"
        case .cashOut: return "arrow.up.circle.fill"
        }
    }
    
    private func colorForEventType(_ type: HomeGame.GameEvent.EventType) -> Color {
        switch type {
        case .gameCreated, .buyIn: return Color(red: 123/255, green: 255/255, blue: 99/255)
        case .gameEnded: return Color.blue
        case .playerJoined: return Color.yellow
        case .playerLeft, .cashOut: return Color.red
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatAmount(_ amount: Double, eventType: HomeGame.GameEvent.EventType) -> String {
        if eventType == .buyIn {
            return "+$\(Int(amount))"
        } else if eventType == .cashOut {
            return "-$\(Int(amount))"
        } else {
            return "$\(Int(amount))"
        }
    }
} 
    
    // Rebuy view for players to request additional chips
    struct RebuyView: View {
        @Environment(\.presentationMode) var presentationMode
        @StateObject private var homeGameService = HomeGameService()
        
        let gameId: String
        let onComplete: () -> Void
        
        @State private var rebuyAmount: String = ""
        @State private var isProcessing = false
        @State private var error: String?
        @State private var showError = false
        
        var body: some View {
            NavigationView {
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Text("Request Rebuy")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Amount input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REBUY AMOUNT")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 4)
                            
                            HStack {
                                Text("$")
                                    .foregroundColor(.white)
                                    .font(.system(size: 17))
                                
                                TextField("", text: $rebuyAmount)
                                    .placeholder(when: rebuyAmount.isEmpty) {
                                        Text("Enter amount").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                            }
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
                        }
                        
                        Text("Your rebuy request will be sent to the game creator for approval.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Submit button
                        Button(action: submitRebuy) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Submit Request")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                !isValidAmount() || isProcessing
                                ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                : Color(red: 123/255, green: 255/255, blue: 99/255)
                            )
                            .cornerRadius(16)
                        }
                        .disabled(!isValidAmount() || isProcessing)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .navigationBarTitle("Request Rebuy", displayMode: .inline)
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
            }
        }
        
        private func isValidAmount() -> Bool {
            guard let amount = Double(rebuyAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
                  amount > 0 else {
                return false
            }
            return true
        }
        
        private func submitRebuy() {
            guard isValidAmount() else { return }
            guard let amount = Double(rebuyAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.requestBuyIn(gameId: gameId, amount: amount)
                    
                    await MainActor.run {
                        isProcessing = false
                        onComplete()
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    // Ledger row for individual player in the game summary
    struct LedgerPlayerRow: View {
        let player: HomeGame.Player
        let gameStartTime: Date
        
        private var playTime: TimeInterval {
            let endTime = player.status == .cashedOut ? (player.cashedOutAt ?? Date()) : Date()
            return endTime.timeIntervalSince(player.joinedAt)
        }
        
        private var formattedPlayTime: String {
            let hours = Int(playTime) / 3600
            let minutes = (Int(playTime) % 3600) / 60
            
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
        
        var body: some View {
            HStack {
                // Player name
                Text(player.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                
                Spacer()
                
                // Time played
                Text(formattedPlayTime)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(width: 70, alignment: .trailing)
                
                // Buy-in amount
                Text("$\(Int(player.totalBuyIn))")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 80, alignment: .trailing)
                
                // Cash-out amount
                Text(player.status == .cashedOut ? "$\(Int(player.currentStack))" : "—")
                    .font(.system(size: 14))
                    .foregroundColor(player.status == .cashedOut ?
                                     (player.currentStack >= player.totalBuyIn ?
                                      Color(red: 123/255, green: 255/255, blue: 99/255) : .red) : .gray)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
            )
            .padding(.horizontal, 16)
        }
    }
    
    // CashOut view to request cashing out
    struct CashOutView: View {
        @Environment(\.presentationMode) var presentationMode
        @StateObject private var homeGameService = HomeGameService()
        
        let gameId: String
        let currentStack: Double
        let onComplete: () -> Void
        
        @State private var cashOutAmount: String = ""
        @State private var isProcessing = false
        @State private var error: String?
        @State private var showError = false
        
        var body: some View {
            NavigationView {
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Text("Request Cash Out")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Stack information
                        HStack {
                            Text("Current Stack:")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Text("$\(Int(currentStack))")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                        .padding(.horizontal, 4)
                        
                        // Amount input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CASH OUT AMOUNT")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 4)
                            
                            HStack {
                                Text("$")
                                    .foregroundColor(.white)
                                    .font(.system(size: 17))
                                
                                TextField("", text: $cashOutAmount)
                                    .placeholder(when: cashOutAmount.isEmpty) {
                                        Text("Enter amount").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                            }
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
                        }
                        
                        
                        Text("Your cash-out request will be sent to the host for processing.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Submit button
                        Button(action: submitCashOut) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Submit Request")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                !isValidAmount() || isProcessing
                                ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                : Color(red: 123/255, green: 255/255, blue: 99/255)
                            )
                            .cornerRadius(16)
                        }
                        .disabled(!isValidAmount() || isProcessing)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .navigationBarTitle("Cash Out", displayMode: .inline)
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
            }
        }
        
        private func isValidAmount() -> Bool {
            return true
        }
        
        private func submitCashOut() {
            guard isValidAmount() else { return }
            guard let amount = Double(cashOutAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.requestCashOut(gameId: gameId, amount: amount)
                    
                    await MainActor.run {
                        isProcessing = false
                        onComplete()
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    // HostRebuy view for the host to request additional chips
    struct HostRebuyView: View {
        @Environment(\.presentationMode) var presentationMode
        @StateObject private var homeGameService = HomeGameService()
        
        let gameId: String
        let onComplete: () -> Void
        
        @State private var rebuyAmount: String = ""
        @State private var isProcessing = false
        @State private var error: String?
        @State private var showError = false
        
        var body: some View {
            NavigationView {
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Text("Request Host Rebuy")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Amount input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REBUY AMOUNT")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 4)
                            
                            HStack {
                                Text("$")
                                    .foregroundColor(.white)
                                    .font(.system(size: 17))
                                
                                TextField("", text: $rebuyAmount)
                                    .placeholder(when: rebuyAmount.isEmpty) {
                                        Text("Enter amount").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                            }
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
                        }
                        
                        Text("Your host rebuy request will be sent for approval.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Submit button
                        Button(action: submitHostRebuy) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Submit Request")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                !isValidAmount() || isProcessing
                                ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                : Color(red: 123/255, green: 255/255, blue: 99/255)
                            )
                            .cornerRadius(16)
                        }
                        .disabled(!isValidAmount() || isProcessing)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .navigationBarTitle("Request Host Rebuy", displayMode: .inline)
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
            }
        }
        
        private func isValidAmount() -> Bool {
            guard let amount = Double(rebuyAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
                  amount > 0 else {
                return false
            }
            return true
        }
        
        private func submitHostRebuy() {
            guard isValidAmount() else { return }
            guard let amount = Double(rebuyAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            
            isProcessing = true
            
            Task {
                do {
                    try await homeGameService.hostBuyIn(gameId: gameId, amount: amount)
                    
                    await MainActor.run {
                        isProcessing = false
                        onComplete()
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    // GameEndView to confirm the end of the game and set final cashout amounts
    struct GameEndView: View {
        @Environment(\.presentationMode) var presentationMode
        @StateObject private var homeGameService = HomeGameService()
        
        let gameId: String
        let onComplete: () -> Void
        
        @State private var game: HomeGame?
        @State private var playerCashouts: [String: String] = [:]  // userId -> amount
        @State private var isLoading = true
        @State private var isProcessing = false
        @State private var error: String?
        @State private var showError = false
        
        var body: some View {
            NavigationView {
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                Text("End Game")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Set final cashout amounts for all active players")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                // Active players
                                if let game = game, !game.players.filter({ $0.status == .active }).isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text("Active Players")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        // Player cashout form rows
                                        ForEach(game.players.filter { $0.status == .active }) { player in
                                            PlayerCashoutRow(
                                                player: player,
                                                cashoutAmount: Binding(
                                                    get: { self.playerCashouts[player.userId] ?? "\(Int(player.currentStack))" },
                                                    set: { self.playerCashouts[player.userId] = $0 }
                                                )
                                            )
                                        }
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                                    )
                                    .padding(.horizontal, 16)
                                } else {
                                    Text("No active players to cash out")
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 30)
                                }
                                
                                // Warning message
                                Text("This will end the game for all players. Cashed out players will not be affected.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                
                                Spacer()
                                
                                // End game button
                                Button(action: confirmEndGame) {
                                    HStack {
                                        if isProcessing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                .frame(width: 20, height: 20)
                                                .padding(.horizontal, 10)
                                        } else {
                                            Text("End Game")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 20)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .frame(height: 54)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.red.opacity(0.7))
                                    )
                                }
                                .disabled(isProcessing)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                }
                .navigationBarTitle("End Game", displayMode: .inline)
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
                    fetchGame()
                }
            }
        }
        
        private func fetchGame() {
            isLoading = true
            
            Task {
                do {
                    if let fetchedGame = try await homeGameService.fetchHomeGame(gameId: gameId) {
                        // Pre-populate the cashout amounts with current stacks
                        var cashouts: [String: String] = [:]
                        for player in fetchedGame.players.filter({ $0.status == .active }) {
                            cashouts[player.userId] = "\(Int(player.currentStack))"
                        }
                        
                        await MainActor.run {
                            game = fetchedGame
                            playerCashouts = cashouts
                            isLoading = false
                        }
                    } else {
                        await MainActor.run {
                            error = "Game not found"
                            showError = true
                            isLoading = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        showError = true
                        isLoading = false
                    }
                }
            }
        }
        
        private func confirmEndGame() {
            isProcessing = true
            
            Task {
                do {
                    if let game = game {
                        // For each active player, create a cashout request with the specified amount
                        for player in game.players.filter({ $0.status == .active }) {
                            if let cashoutStr = playerCashouts[player.userId], let cashoutAmount = Double(cashoutStr) {
                                // REMOVE condition: Allow processing even if cashoutAmount is 0
                                // if cashoutAmount > 0 {
                                    // Process each cashout
                                    try await homeGameService.processCashoutForGameEnd(
                                        gameId: gameId,
                                        playerId: player.id,
                                        userId: player.userId,
                                        amount: cashoutAmount
                                    )
                                // }
                            }
                        }
                    }
                    
                    // End the game after processing all cashouts
                    try await homeGameService.endGame(gameId: gameId)
                    
                    await MainActor.run {
                        isProcessing = false
                        onComplete()
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    // Row for player cashout in the end game view
    struct PlayerCashoutRow: View {
        let player: HomeGame.Player
        @Binding var cashoutAmount: String
        
        var body: some View {
            VStack(spacing: 8) {
                HStack {
                    // Player name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Current: $\(Int(player.currentStack))")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Cashout amount input
                    HStack {
                        Text("$")
                            .foregroundColor(.white)
                            .font(.system(size: 15))
                        
                        TextField("", text: $cashoutAmount)
                            .placeholder(when: cashoutAmount.isEmpty) {
                                Text("Amount").foregroundColor(.gray.opacity(0.7))
                            }
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(UIColor(red: 50/255, green: 50/255, blue: 55/255, alpha: 1.0)))
                            )
                    }
                }
                
                if !isValidAmount(amount: cashoutAmount) {
                    Text("Please enter a valid amount")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor(red: 40/255, green: 42/255, blue: 48/255, alpha: 1.0)))
            )
        }
        
        private func isValidAmount(amount: String) -> Bool {
            guard let value = Double(amount) else { return false }
            return value >= 0
        }
    }
    
    // Player cashout sheet
    struct PlayerCashoutView: View {
        @Environment(\.presentationMode) var presentationMode
        
        let player: HomeGame.Player
        let onComplete: (Double) -> Void
        
        @State private var cashoutAmount: String = ""
        @State private var isProcessing = false
        
        private func isValidAmount() -> Bool {
            guard let value = Double(cashoutAmount), value > 0 else {
                return false
            }
            return true
        }
        
        var body: some View {
            NavigationView {
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Text("Cash Out")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Amount input
                        VStack(spacing: 8) {
                            Text("Cashout Amount")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack {
                                Text("$")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                                
                                TextField("", text: $cashoutAmount)
                                    .placeholder(when: cashoutAmount.isEmpty) {
                                        Text("Enter amount").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                                    .padding(.vertical, 12)
                            }
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor(red: 28/255, green: 30/255, blue: 34/255, alpha: 1.0)))
                        )
                        
                        Spacer()
                        
                        // Cashout button
                        Button(action: {
                            if isValidAmount() {
                                isProcessing = true
                                if let amount = Double(cashoutAmount) {
                                    onComplete(amount)
                                }
                                presentationMode.wrappedValue.dismiss()
                            }
                        }) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Confirm Cashout")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isValidAmount() ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.gray)
                            )
                        }
                        .disabled(!isValidAmount() || isProcessing)
                        .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 24)
                    .navigationBarItems(leading: Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    })
                }
            }
        }
    }

// Helper function to format duration (TimeInterval) into Hh Mm format
private func formatDuration(_ duration: TimeInterval) -> String {
    guard duration > 0 else { return "0m" }
    
    let totalMinutes = Int(duration / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}

// MARK: - Save Home Game Session View

struct SaveHomeGameSessionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var sessionStore: SessionStore

    let pnl: Double
    let buyIn: Double
    let cashOut: Double
    let duration: TimeInterval
    let date: Date

    @State private var sessionName: String = ""
    @State private var sessionStakes: String = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var showErrorAlert = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 0) {
                // Custom navigation bar
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer()
                    
                    Text("Save Home Game")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: saveSession) {
                        Text("Save")
                            .foregroundColor(.black)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                Capsule()
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                    }
                    .disabled(sessionName.isEmpty || sessionStakes.isEmpty || isSaving)
                    .opacity((sessionName.isEmpty || sessionStakes.isEmpty || isSaving) ? 0.6 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Scroll content
                ScrollView {
                    VStack(spacing: 24) {
                        // Session Details Card
                        VStack(spacing: 20) {
                            // Section header
                            HStack {
                                Text("SESSION DETAILS")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                Spacer()
                            }
                            .padding(.bottom, 4)
                            
                            // Details with dividers
                            detailRow(label: "Profit/Loss", value: formatMoney(pnl), 
                                      valueColor: pnl >= 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red)
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Buy-in", value: formatMoney(buyIn))
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Cash Out", value: formatMoney(cashOut))
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Duration", value: formatDuration(duration))
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Date", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear,
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal, 16)
                        
                        // Session Info Input Card
                        VStack(spacing: 20) {
                            // Section header
                            HStack {
                                Text("SESSION INFO")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                Spacer()
                            }
                            .padding(.bottom, 4)
                            
                            // Name input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SESSION NAME")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                TextField("", text: $sessionName)
                                    .placeholder(when: sessionName.isEmpty) {
                                        Text("e.g., Friday Night Game").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .foregroundColor(.white)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.1),
                                                        Color.clear,
                                                        Color.clear
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            
                            // Stakes input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("STAKES")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                TextField("", text: $sessionStakes)
                                    .placeholder(when: sessionStakes.isEmpty) {
                                        Text("e.g., 1/2 NLH").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .foregroundColor(.white)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.1),
                                                        Color.clear,
                                                        Color.clear
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear,
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal, 16)
                        
                        // Save button for larger screens
                        Button(action: saveSession) {
                            HStack {
                                Text("Save Session")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill((sessionName.isEmpty || sessionStakes.isEmpty || isSaving) ? 
                                          Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5) : 
                                          Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                        }
                        .disabled(sessionName.isEmpty || sessionStakes.isEmpty || isSaving)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 16)
                }
            }
            
            // Loading overlay
            if isSaving {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                        .scaleEffect(1.5)
                    
                    Text("Saving Session...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.95)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            }
        }
        .alert("Error Saving Session", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(error ?? "An unknown error occurred.")
        }
        .statusBar(hidden: false)
    }
    
    // Helper function to create consistent detail rows
    private func detailRow(label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(valueColor)
        }
    }
    
    // Helper function to format money (copied for self-containment)
    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    // Helper function to format duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "0m" }
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func saveSession() {
        isSaving = true
        error = nil
        
        // Get current user ID directly from Auth
        guard let userId = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.error = "Failed to get user ID"
                self.showErrorAlert = true
                self.isSaving = false
            }
            return
        }
        
        // Create the dictionary for SessionStore with accurate buyIn and cashOut values
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "Home Game",
            "gameName": sessionName,
            "stakes": sessionStakes,
            "startDate": Timestamp(date: date.addingTimeInterval(-duration)),
            "startTime": Timestamp(date: date.addingTimeInterval(-duration)),
            "endTime": Timestamp(date: date),
            "hoursPlayed": duration / 3600,
            "buyIn": buyIn,
            "cashout": cashOut,
            "profit": pnl,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Call the SessionStore method with completion handler
        sessionStore.addSession(sessionData) { saveError in
            DispatchQueue.main.async {
                self.isSaving = false
                if let saveError = saveError {
                    self.error = "Failed to save session: \(saveError.localizedDescription)"
                    self.showErrorAlert = true
                } else {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}



