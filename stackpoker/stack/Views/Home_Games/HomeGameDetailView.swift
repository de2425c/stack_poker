import SwiftUI
import FirebaseAuth
import PhotosUI // Keep if used elsewhere in the file
import Combine // Keep if used elsewhere in the file
import Foundation // Keep if used elsewhere in the file
import FirebaseFirestore // Add this import

// Simple Group model for invite functionality
struct SimpleGroup: Identifiable {
    let id: String
    let name: String
    let description: String?
    let createdAt: Date
    let createdBy: String
    let memberIds: [String]
}

// Update HomeGameDetailView to include functionality for the owner
struct HomeGameDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var sessionStore: SessionStore
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
    @State private var showCopiedMessage = false
    
    // Add new state variables for invite functionality
    @State private var showingInviteSheet = false
    @State private var showingInviteConfirmation = false
    @State private var inviteSuccessMessage: String?
    
    // Add new state variables for share prompt
    @State private var showSharePrompt = false
    @State private var hasShownSharePrompt = false
    
    // State for Save Session feature
    @State private var previousGame: HomeGame?
    @State private var justCashedOutPlayer: HomeGame.Player?
    @State private var showingSaveSessionAlert = false
    @State private var showingSaveSessionSheet = false
    @State private var showingManagePlayerSheet = false
    @State private var playerToManage: HomeGame.Player?
    
    // Add this property to store the activity items
    @State private var activityItems: [Any] = []
    
    // Helper to determine if current user is the game creator
    private var isGameCreator: Bool {
        return game.creatorId == Auth.auth().currentUser?.uid
    }
    
    // Helper to determine if current user is a player
    private var isCurrentPlayerActive: Bool {
        return (liveGame ?? game).players.contains(where: {
            $0.userId == Auth.auth().currentUser?.uid && $0.status == .active
        })
    }
    
    // Helper to determine if current user has a pending buy-in request
    private var hasPendingBuyInRequest: Bool {
        return (liveGame ?? game).buyInRequests.contains(where: {
            $0.userId == Auth.auth().currentUser?.uid && $0.status == .pending
        })
    }
    
    // Updated function to copy the link
    private func copyGameLink() {
        let gameId = (liveGame ?? game).id
        let shareURLString = "https://stackpoker.gg/games/\(gameId)"
        UIPasteboard.general.string = shareURLString
        
        // Show confirmation message briefly
        Task {
            await MainActor.run {
                showCopiedMessage = true
            }
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            await MainActor.run {
                showCopiedMessage = false
            }
        }
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom navigation header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("Back")
                                .font(.system(size: 17))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    let currentGame = liveGame ?? game
                    Text(currentGame.status == .completed ? "Game Summary" :
                            (isGameCreator ? "Game Management" : "Game Details"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if isGameCreator && (liveGame ?? game).status == .active {
                        HStack(spacing: 16) {
                            Button(action: {
                                showingInviteSheet = true
                            }) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            
                            Button(action: copyGameLink) {
                                Image(systemName: "link")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                        }
                    } else {
                        // Invisible spacer to balance the layout
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                
                if showCopiedMessage {
                    HStack {
                        Text("Link copied!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                    }
                    .transition(.opacity)
                    .animation(.easeInOut, value: showCopiedMessage)
                    .padding(.bottom, 8)
                }
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 25) {
                        // Use the most recent game data (liveGame if available, otherwise fallback to initial game)
                        let currentGame = liveGame ?? game
                        
                        if currentGame.status == .completed {
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
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    refreshGame()
                }
            }
            
            // Invite prompt overlay
            if showSharePrompt {
                ZStack {
                    Color.black.opacity(0.7)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation {
                                showSharePrompt = false
                            }
                        }
                    
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            
                            Text("Game Created!")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Invite players to join your game")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        
                        VStack(spacing: 12) {
                            // Invite Players button (primary action)
                            Button(action: {
                                withAnimation {
                                    showSharePrompt = false
                                }
                                showingInviteSheet = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 20))
                                        .foregroundColor(.black)
                                    
                                    Text("Invite Players")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                                )
                            }
                            
                            // Secondary options
                            HStack(spacing: 12) {
                                Button(action: {
                                    copyGameLink()
                                    withAnimation {
                                        showSharePrompt = false
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.system(size: 16))
                                        Text("Copy Link")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(UIColor(red: 50/255, green: 52/255, blue: 57/255, alpha: 1.0)))
                                    )
                                }
                                
                                Button(action: {
                                    shareGame()
                                    withAnimation {
                                        showSharePrompt = false
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16))
                                        Text("Share")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(UIColor(red: 50/255, green: 52/255, blue: 57/255, alpha: 1.0)))
                                    )
                                }
                            }
                        }
                        
                        Button(action: {
                            withAnimation {
                                showSharePrompt = false
                            }
                        }) {
                            Text("Skip for now")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.96)))
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
                    .padding(.horizontal, 32)
                }
                .zIndex(3)
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
            CashOutView(gameId: (liveGame ?? game).id, onComplete: {
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
            // Refresh game data immediately to get latest status
            refreshGame()
            setupLiveUpdates()
            
            // SAFEGUARD: If this game appears to be completed but was just created from an event,
            // force refresh to get the correct status
            if (liveGame ?? game).status == .completed {
                // Force refresh after a brief delay to ensure we have the latest data
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    refreshGame()
                }
            }
            
            // Show share prompt when view appears if it's the creator and hasn't been shown
            if isGameCreator && !hasShownSharePrompt && (liveGame ?? game).status == .active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        showSharePrompt = true
                        hasShownSharePrompt = true
                    }
                }
            }
        }
        .onDisappear {
            homeGameService.stopListeningForGameUpdates()
            // Let parent view know this view is disappearing
            onGameUpdated?()
        }
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
        .sheet(isPresented: $showingSaveSessionSheet) {
            if let player = justCashedOutPlayer,
               let cashoutTime = player.cashedOutAt {
                let pnl = player.currentStack - player.totalBuyIn
                let duration = cashoutTime.timeIntervalSince(player.joinedAt)
                
                SaveHomeGameSessionView(
                    pnl: pnl,
                    buyIn: player.totalBuyIn,
                    cashOut: player.currentStack,
                    duration: duration,
                    date: cashoutTime
                )
                .environmentObject(sessionStore)
            } else {
                Text("Error: Missing session data to save.")
            }
        }
        .sheet(isPresented: $showingManagePlayerSheet) {
            if let player = playerToManage {
                ManagePlayerSheet(
                    player: player,
                    gameId: (liveGame ?? game).id,
                    onComplete: {
                        // Refresh the game data after managing player
                        onGameUpdated?()
                    }
                )
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            InvitePlayersSheet(
                gameId: (liveGame ?? game).id,
                onComplete: { successMessage in
                    showingInviteSheet = false
                    if let message = successMessage {
                        inviteSuccessMessage = message
                        showingInviteConfirmation = true
                    }
                }
            )
            .environmentObject(sessionStore)
        }
        .alert("Invites Sent!", isPresented: $showingInviteConfirmation) {
            Button("OK") {
                inviteSuccessMessage = nil
            }
        } message: {
            Text(inviteSuccessMessage ?? "")
        }
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
                
                let previousStatus = self.previousGame?.players.first { $0.userId == userId }?.status
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
                            title: "STAKES",
                            value: game.stakesDisplay,
                            subtitle: "blinds"
                        )
                        
                        Divider()
                            .frame(width: 1)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 8)
                        
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
                            value: "$\(Int(getTotalBuyIns()))",
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
                                playerToManage = player
                                showingManagePlayerSheet = true
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
                    
                    // Stakes display if available
                    if game.smallBlind != nil || game.bigBlind != nil {
                        Text("Stakes: \(game.stakesDisplay)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    }
                    
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
                        HStack(spacing: 40) {
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
        
        private func getTotalBuyIns() -> Double {
            return game.players.reduce(0) { $0 + $1.totalBuyIn }
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
            LazyVStack(spacing: 24) {
                // Header with date only (title is in navigation)
                VStack(spacing: 8) {
                    Text(formatDate(game.createdAt))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 16)
                
                // Game Totals
                summaryTotalsCard
                
                // Settlement Plan
                settlementPlanSection
                
                // Player Ledger
                playerLedgerSection
                
                // Notes
                settlementNotesSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        
        private var summaryTotalsCard: some View {
            VStack(spacing: 16) {
                HStack {
                    Text("GAME TOTALS")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    Spacer()
                }
                
                let totalBuyIns = getTotalBuyIns()
                let totalCashOuts = getTotalCashOuts()
                let difference = totalCashOuts - totalBuyIns
                
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Buy-ins")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text(formatMoney(totalBuyIns))
                                .font(.title3.bold())
                                .foregroundColor(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Total Cash-outs")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text(formatMoney(totalCashOuts))
                                .font(.title3.bold())
                                .foregroundColor(.white)
                        }
                    }
                    
                    Divider()
                        .background(Color.secondary.opacity(0.3))
                    
                    HStack {
                        Text("Difference")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(difference >= 0 ? "+" : "")\(formatMoney(difference))")
                            .font(.title3.bold())
                            .foregroundColor(difference == 0 ? .white : (difference > 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6).opacity(0.1))
            )
        }
        
        private var settlementPlanSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settlement Plan")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text("Optimized for minimum transactions")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                }
                
                let settlements = game.settlementTransactions?.map { 
                    SettlementTransaction(fromPlayer: $0.fromPlayer, toPlayer: $0.toPlayer, amount: $0.amount)
                } ?? calculateOptimalSettlement()
                
                if settlements.isEmpty {
                    perfectBalanceView
                } else {
                    settlementTransactionsView(settlements: settlements)
                }
            }
        }
        
        private var perfectBalanceView: some View {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Perfect Balance")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("No settlements required")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.3), lineWidth: 1)
                    )
            )
        }
        
        private func settlementTransactionsView(settlements: [SettlementTransaction]) -> some View {
            VStack(spacing: 12) {
                HStack {
                    Text("\(settlements.count) transaction\(settlements.count == 1 ? "" : "s") needed")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    Spacer()
                    Text("Tap to copy amounts")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                ForEach(Array(settlements.enumerated()), id: \.offset) { index, settlement in
                    SimpleSettlementRow(transaction: settlement, index: index + 1)
                }
            }
        }
        
        private var playerLedgerSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Player Ledger")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                
                // Simple ledger without complex layouts
                VStack(spacing: 8) {
                    ForEach(getAllPlayers()) { player in
                        SimpleLedgerRow(player: player)
                    }
                }
            }
        }
        
        private var settlementNotesSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settlement Notes")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Use the settlement transactions above to minimize payments. Each transaction settles the maximum amount between winners and losers.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6).opacity(0.1))
            )
        }
        
        // Get all players that participated in the game
        private func getAllPlayers() -> [HomeGame.Player] {
            return game.players
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
        
        // Settlement Transaction structure
        struct SettlementTransaction {
            let fromPlayer: String
            let toPlayer: String
            let amount: Double
        }
        
        // Player balance for settlement calculation
        private struct PlayerBalance {
            let name: String
            var balance: Double
            let originalBalance: Double
            
            init(name: String, balance: Double) {
                self.name = name
                self.balance = balance
                self.originalBalance = balance
            }
        }
        
        // Calculate optimal settlement using minimum transaction algorithm
        // This uses a cycle elimination + optimal pairing approach that guarantees minimum transactions
        private func calculateOptimalSettlement() -> [SettlementTransaction] {
            // Calculate house difference (total buy-ins vs total cash-outs)
            let totalBuyIns = getTotalBuyIns()
            let totalCashOuts = getTotalCashOuts()
            let houseDifference = totalBuyIns - totalCashOuts
            
            // Calculate net profit/loss for each player
            var playerBalances: [PlayerBalance] = []
            
            for player in game.players {
                let netBalance = player.currentStack - player.totalBuyIn
                // Only include players with non-zero balances (within $1 tolerance)
                if abs(netBalance) > 1.0 {
                    playerBalances.append(PlayerBalance(name: player.displayName, balance: netBalance))
                }
            }
            
            // Handle house difference by adjusting winners' balances
            if abs(houseDifference) > 1.0 {
                playerBalances = adjustForHouseDifference(playerBalances, houseDifference: houseDifference)
            }
            
            // If no imbalances after adjustment, return empty
            guard !playerBalances.isEmpty else { return [] }
            
            // Use recursive backtracking to find minimum transactions
            return findMinimumTransactions(playerBalances: playerBalances)
        }
        
        // Adjust player balances to account for house difference
        private func adjustForHouseDifference(_ balances: [PlayerBalance], houseDifference: Double) -> [PlayerBalance] {
            var adjustedBalances = balances
            
            if houseDifference > 1.0 {
                // House kept money - reduce winners' profits proportionally
                let winners = adjustedBalances.filter { $0.balance > 1.0 }
                let totalWinnings = winners.reduce(0) { $0 + $1.balance }
                
                guard totalWinnings > 0 else { return adjustedBalances }
                
                for i in 0..<adjustedBalances.count {
                    if adjustedBalances[i].balance > 1.0 {
                        let proportionalLoss = (adjustedBalances[i].balance / totalWinnings) * houseDifference
                        adjustedBalances[i].balance -= proportionalLoss
                    }
                }
            } else if houseDifference < -1.0 {
                // House paid out more - increase winners' profits proportionally
                let winners = adjustedBalances.filter { $0.balance > 1.0 }
                let totalWinnings = winners.reduce(0) { $0 + $1.balance }
                
                guard totalWinnings > 0 else { return adjustedBalances }
                
                for i in 0..<adjustedBalances.count {
                    if adjustedBalances[i].balance > 1.0 {
                        let proportionalGain = (adjustedBalances[i].balance / totalWinnings) * abs(houseDifference)
                        adjustedBalances[i].balance += proportionalGain
                    }
                }
            }
            
            // Remove players with balances close to zero after adjustment
            return adjustedBalances.filter { abs($0.balance) > 1.0 }
        }
        
        // Recursive algorithm to find minimum number of transactions
        private func findMinimumTransactions(playerBalances: [PlayerBalance]) -> [SettlementTransaction] {
            var balances = playerBalances
            var transactions: [SettlementTransaction] = []
            
            // Step 1: Eliminate cycles (this can reduce transactions significantly)
            eliminateCycles(&balances, &transactions)
            
            // Step 2: Pair creditors with debtors optimally
            while let creditorIndex = balances.firstIndex(where: { $0.balance > 1.0 }),
                  let debtorIndex = balances.firstIndex(where: { $0.balance < -1.0 }) {
                
                let creditor = balances[creditorIndex]
                let debtor = balances[debtorIndex]
                
                // Use the smaller absolute amount to fully settle one party
                let settlementAmount = min(creditor.balance, abs(debtor.balance))
                
                // Create transaction
                transactions.append(SettlementTransaction(
                    fromPlayer: debtor.name,
                    toPlayer: creditor.name,
                    amount: settlementAmount
                ))
                
                // Update balances
                balances[creditorIndex].balance -= settlementAmount
                balances[debtorIndex].balance += settlementAmount
                
                // Remove players with zero balance
                balances.removeAll { abs($0.balance) <= 1.0 }
            }
            
            return transactions
        }
        
        // Cycle elimination to reduce total transactions needed
        private func eliminateCycles(_ balances: inout [PlayerBalance], _ transactions: inout [SettlementTransaction]) {
            // Look for groups of 3+ players that can settle among themselves
            // This is a simplified cycle detection - in practice, finding all cycles is complex
            // but this handles the most common cases that reduce transaction count
            
            var changed = true
            while changed {
                changed = false
                
                // Try to find triangular settlements (3-player cycles)
                for i in 0..<balances.count {
                    for j in (i+1)..<balances.count {
                        for k in (j+1)..<balances.count {
                            if tryTriangularSettlement(&balances, &transactions, i, j, k) {
                                changed = true
                                balances.removeAll { abs($0.balance) <= 1.0 }
                                break
                            }
                        }
                        if changed { break }
                    }
                    if changed { break }
                }
            }
        }
        
        // Try to create a triangular settlement between 3 players
        private func tryTriangularSettlement(_ balances: inout [PlayerBalance], 
                                           _ transactions: inout [SettlementTransaction],
                                           _ i: Int, _ j: Int, _ k: Int) -> Bool {
            let players = [balances[i], balances[j], balances[k]]
            
            // Check if we have one of each type or can form a beneficial cycle
            let positives = players.filter { $0.balance > 1.0 }
            let negatives = players.filter { $0.balance < -1.0 }
            
            // Must have at least one positive and one negative
            guard !positives.isEmpty && !negatives.isEmpty else { return false }
            
            // For a 3-player cycle, look for cases where we can reduce total transactions
            // This is a simplified heuristic - a full implementation would be more complex
            if positives.count == 1 && negatives.count == 2 {
                let creditor = positives[0]
                let debtors = negatives
                
                // See if the creditor's balance can be split between the two debtors
                let totalDebt = debtors.reduce(0) { $0 + abs($1.balance) }
                
                if creditor.balance <= totalDebt {
                    // We can settle the creditor completely
                    let debt1 = min(creditor.balance, abs(debtors[0].balance))
                    let debt2 = creditor.balance - debt1
                    
                    if debt2 > 0 && debt2 <= abs(debtors[1].balance) {
                        // Create transactions
                        transactions.append(SettlementTransaction(
                            fromPlayer: debtors[0].name,
                            toPlayer: creditor.name,
                            amount: debt1
                        ))
                        
                        transactions.append(SettlementTransaction(
                            fromPlayer: debtors[1].name,
                            toPlayer: creditor.name,
                            amount: debt2
                        ))
                        
                        // Update balances
                        if let idx = balances.firstIndex(where: { $0.name == creditor.name }) {
                            balances[idx].balance = 0
                        }
                        if let idx = balances.firstIndex(where: { $0.name == debtors[0].name }) {
                            balances[idx].balance += debt1
                        }
                        if let idx = balances.firstIndex(where: { $0.name == debtors[1].name }) {
                            balances[idx].balance += debt2
                        }
                        
                        return true
                    }
                }
            }
            
            return false
        }
        
        // Simplified settlement row component
        struct SimpleSettlementRow: View {
            let transaction: SettlementTransaction
            let index: Int
            @State private var showCopied = false
            
            var body: some View {
                Button(action: {
                    UIPasteboard.general.string = "\(Int(transaction.amount))"
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopied = false
                        }
                    }
                }) {
                    HStack(spacing: 16) {
                        Text("\(index)")
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(red: 123/255, green: 255/255, blue: 99/255)))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(transaction.fromPlayer)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text(transaction.toPlayer)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Payment amount")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        if showCopied {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                Text("Copied!")
                                    .font(.caption)
                            }
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        } else {
                            Text("$\(Int(transaction.amount))")
                                .font(.title3.bold())
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6).opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        
        // Simplified ledger row component
        struct SimpleLedgerRow: View {
            let player: HomeGame.Player
            
            private var playTime: String {
                let endTime = player.status == .cashedOut ? (player.cashedOutAt ?? Date()) : Date()
                let duration = endTime.timeIntervalSince(player.joinedAt)
                let minutes = Int(duration) / 60
                let hours = minutes / 60
                
                if hours > 0 {
                    return "\(hours)h \(minutes % 60)m"
                } else {
                    return "\(minutes)m"
                }
            }
            
            private var netAmount: Double {
                return player.currentStack - player.totalBuyIn
            }
            
            var body: some View {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.displayName)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Played \(playTime)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 16) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(Int(player.totalBuyIn))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Text("buy-in")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(player.status == .cashedOut ? "$\(Int(player.currentStack))" : "—")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(player.status == .cashedOut ? .white : .white.opacity(0.5))
                                Text("cash-out")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(player.status == .cashedOut ? "\(netAmount >= 0 ? "+" : "")\(Int(netAmount))" : "—")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(player.status == .cashedOut ? 
                                                    (netAmount >= 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red) : 
                                                    .white.opacity(0.5))
                                Text("net")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.1))
                )
            }
        }

        // Fix the shareGame function to ensure it works correctly
        private func shareGame() {
            let gameId = (liveGame ?? game).id
            let shareURLString = "https://stackpoker.gg/games/\(gameId)"
            let shareText = "Join my poker game on Stack Poker! "
            
            // Use main thread to present the share sheet
            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(
                    activityItems: [shareText, shareURLString],
                    applicationActivities: nil
                )
                
                // Find the top-most view controller to present from
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    // Find the presented view controller
                    var topController = rootViewController
                    while let presentedVC = topController.presentedViewController {
                        topController = presentedVC
                    }
                    
                    // Set source view for iPad
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = topController.view
                        popover.sourceRect = CGRect(x: topController.view.bounds.midX, 
                                                   y: topController.view.bounds.midY, 
                                                   width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    
                    topController.present(activityVC, animated: true, completion: nil)
                }
            }
        }
    }
    
    // MARK: - Invite Players Sheet
    struct InvitePlayersSheet: View {
        @Environment(\.presentationMode) var presentationMode
        @EnvironmentObject var sessionStore: SessionStore
        @StateObject private var homeGameService = HomeGameService()
        @StateObject private var userService = UserService()
        
        let gameId: String
        let onComplete: (String?) -> Void
        
        @State private var selectedTab = 0
        @State private var searchText = ""
        @State private var searchResults: [UserProfile] = []
        @State private var selectedUsers: Set<String> = []
        @State private var selectedGroups: Set<String> = []
        @State private var isSearching = false
        @State private var message = ""
        @State private var isInviting = false
        @State private var error: String?
        @State private var showError = false
        @State private var userGroups: [SimpleGroup] = []
        
        var body: some View {
            NavigationView {
                ZStack {
                    // Background for sheet - use a standard color instead of AppBackgroundView
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()
                    
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor(red: 20/255, green: 22/255, blue: 26/255, alpha: 1.0)),
                            Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0))
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Tab selector
                        HStack(spacing: 0) {
                            Button(action: { selectedTab = 0 }) {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person")
                                            .font(.system(size: 16))
                                        Text("Individual")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(selectedTab == 0 ? .white : .gray)
                                    
                                    Rectangle()
                                        .fill(selectedTab == 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            Button(action: { selectedTab = 1 }) {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.3")
                                            .font(.system(size: 16))
                                        Text("Groups")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(selectedTab == 1 ? .white : .gray)
                                    
                                    Rectangle()
                                        .fill(selectedTab == 1 ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        
                        if selectedTab == 0 {
                            individualInviteView
                        } else {
                            groupInviteView
                        }
                    }
                }
                .navigationBarTitle("Invite Players", displayMode: .inline)
                .navigationBarItems(
                    leading: Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white),
                    trailing: Button("Send") {
                        sendInvites()
                    }
                    .disabled(selectedUsers.isEmpty && selectedGroups.isEmpty || isInviting)
                    .foregroundColor((selectedUsers.isEmpty && selectedGroups.isEmpty) || isInviting ? .gray : Color(red: 123/255, green: 255/255, blue: 99/255))
                    .font(.system(size: 16, weight: .semibold))
                )
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(error ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                loadUserGroups()
            }
        }
        
        private var individualInviteView: some View {
            VStack(spacing: 0) {
                // Search bar section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search users...", text: $searchText)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .onChange(of: searchText) { newValue in
                                searchUsers(query: newValue)
                            }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                    )
                    
                    // Selected users
                    if !selectedUsers.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(selectedUsers), id: \.self) { userId in
                                    if let user = searchResults.first(where: { $0.id == userId }) {
                                        SelectedUserChip(user: user) {
                                            selectedUsers.remove(userId)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Search results section
                if isSearching {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Spacer()
                } else if !searchText.isEmpty && searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No users found")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else if !searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(searchResults) { user in
                                UserInviteRow(
                                    user: user,
                                    isSelected: selectedUsers.contains(user.id)
                                ) {
                                    if selectedUsers.contains(user.id) {
                                        selectedUsers.remove(user.id)
                                    } else {
                                        selectedUsers.insert(user.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 60)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Search for users to invite")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
            }
        }
        
        private var groupInviteView: some View {
            VStack(spacing: 0) {
                Text("Select groups to invite all members")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                
                if userGroups.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No groups found")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                        Text("You're not a member of any groups yet")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(userGroups) { group in
                                GroupInviteRow(
                                    group: group,
                                    isSelected: selectedGroups.contains(group.id)
                                ) {
                                    if selectedGroups.contains(group.id) {
                                        selectedGroups.remove(group.id)
                                    } else {
                                        selectedGroups.insert(group.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        
        private func searchUsers(query: String) {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedQuery.isEmpty {
                searchResults = []
                return
            }
            
            isSearching = true
            
            Task {
                do {
                    let results = try await userService.searchUsers(query: trimmedQuery, limit: 20)
                    await MainActor.run {
                        searchResults = results
                        isSearching = false
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        showError = true
                        isSearching = false
                    }
                }
            }
        }
        
        private func loadUserGroups() {
            guard let currentUserId = Auth.auth().currentUser?.uid else { 
                print("No current user found")
                return 
            }
            
            print("Loading groups for user: \(currentUserId)")
            
            Task {
                do {
                    // This assumes you have a method to fetch user's groups
                    // You might need to add this to GroupService or UserService
                    let groups = try await fetchUserGroups(userId: currentUserId)
                    print("Fetched \(groups.count) groups")
                    await MainActor.run {
                        userGroups = groups
                    }
                } catch {
                    print("Error loading groups: \(error)")
                    await MainActor.run {
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        
        private func fetchUserGroups(userId: String) async throws -> [SimpleGroup] {
            let db = Firestore.firestore()
            
            print("Querying user groups for user: \(userId)")
            
            // Use the same structure as GroupService - get groups from user's subcollection
            let userGroupsSnapshot = try await db.collection("users")
                .document(userId)
                .collection("groups")
                .getDocuments()
            
            print("Found \(userGroupsSnapshot.documents.count) groups in user's groups subcollection")
            
            var groups: [SimpleGroup] = []
            
            // For each group reference, fetch the actual group data
            for userGroupDoc in userGroupsSnapshot.documents {
                guard let groupId = userGroupDoc.data()["groupId"] as? String else { 
                    print("No groupId found in user group document")
                    continue 
                }
                
                do {
                    let groupDoc = try await db.collection("groups").document(groupId).getDocument()
                    
                    if let groupData = groupDoc.data(), groupDoc.exists {
                        print("Processing group document: \(groupId)")
                        print("Group data: \(groupData)")
                        
                        if let group = try? parseGroup(data: groupData, id: groupId) {
                            groups.append(group)
                            print("Successfully parsed group: \(group.name)")
                        } else {
                            print("Failed to parse group document: \(groupId)")
                        }
                    } else {
                        print("Group document \(groupId) doesn't exist")
                    }
                } catch {
                    print("Error fetching group \(groupId): \(error)")
                    continue
                }
            }
            
            print("Returning \(groups.count) parsed groups")
            return groups
        }
        
        private func parseGroup(data: [String: Any], id: String) throws -> SimpleGroup {
            // Parse using the same structure as GroupService
            print("Parsing group data: \(data)")
            
            guard let name = data["name"] as? String else {
                print("No name found in group data. Available keys: \(data.keys)")
                throw NSError(domain: "InviteService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid group data - no name found"])
            }
            
            let description = data["description"] as? String
            let createdBy = data["ownerId"] as? String ?? ""
            
            // Parse creation date
            var createdAt = Date()
            if let timestamp = data["createdAt"] as? Timestamp {
                createdAt = timestamp.dateValue()
            }
            
            // For member count, we'll use a placeholder since we're using this for invites
            // The actual member fetching will happen when sending group invites
            let memberCount = data["memberCount"] as? Int ?? 1
            
            print("Successfully parsed group: \(name) with \(memberCount) members")
            
            return SimpleGroup(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                createdBy: createdBy,
                memberIds: [] // We'll populate this when needed for invites
            )
        }
        
        private func sendInvites() {
            isInviting = true
            
            Task {
                do {
                    var inviteCount = 0
                    
                    // Send individual invites
                    for userId in selectedUsers {
                        if let user = searchResults.first(where: { $0.id == userId }) {
                            try await homeGameService.sendGameInvite(
                                gameId: gameId,
                                invitedUserId: userId,
                                invitedUserDisplayName: user.displayName ?? user.username,
                                message: message.isEmpty ? nil : message
                            )
                            inviteCount += 1
                        }
                    }
                    
                    // Send group invites
                    for groupId in selectedGroups {
                        if let group = userGroups.first(where: { $0.id == groupId }) {
                            try await homeGameService.sendGroupGameInvite(
                                gameId: gameId,
                                groupId: groupId,
                                groupName: group.name,
                                message: message.isEmpty ? nil : message
                            )
                            // Approximate count - actual count handled in service
                            inviteCount += 3 // Rough estimate since we don't have exact member count here
                        }
                    }
                    
                    await MainActor.run {
                        isInviting = false
                        let successMessage = inviteCount == 1 ? "1 invite sent!" : "\(inviteCount) invites sent!"
                        onComplete(successMessage)
                    }
                } catch {
                    await MainActor.run {
                        isInviting = false
                        self.error = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    // MARK: - Invite Components
    struct UserInviteRow: View {
        let user: UserProfile
        let isSelected: Bool
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 16) {
                    // User avatar placeholder
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(user.displayName?.first ?? user.username.first ?? "?").uppercased())
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName ?? user.username)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("@\(user.username)")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? Color(red: 123/255, green: 255/255, blue: 99/255) : .gray)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.1) : Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    struct GroupInviteRow: View {
        let group: SimpleGroup
        let isSelected: Bool
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 16) {
                    // Group avatar placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.3")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("Group members")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? Color(red: 123/255, green: 255/255, blue: 99/255) : .gray)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.1) : Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    struct SelectedUserChip: View {
        let user: UserProfile
        let onRemove: () -> Void
        
        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(user.displayName?.first ?? user.username.first ?? "?").uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                Text(user.displayName ?? user.username)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
            )
        }
    }
    
    // Enhanced owner-specific player row with more detailed info and controls
    struct OwnerPlayerRow: View {
        let player: HomeGame.Player
        let onManage: () -> Void
        
        private func formatMoney(_ amount: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
        }
        
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
                    
                    // Profit/Loss display
                    VStack(alignment: .trailing, spacing: 4) {
                        let profit = player.currentStack - player.totalBuyIn
                        Text("\(profit >= 0 ? "+" : "")\(formatMoney(profit))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(profit >= 0 ?
                                             Color(red: 123/255, green: 255/255, blue: 99/255) :
                                                Color.red)
                        
                        Text("P&L")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
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