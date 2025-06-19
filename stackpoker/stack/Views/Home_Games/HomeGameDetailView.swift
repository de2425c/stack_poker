import SwiftUI
import FirebaseAuth
import PhotosUI // Keep if used elsewhere in the file
import Combine // Keep if used elsewhere in the file
import Foundation // Keep if used elsewhere in the file
import FirebaseFirestore // Add this import

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
    
    // Add this property to store the activity items
    @State private var activityItems: [Any] = []
    
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
            
            if showCopiedMessage {
                VStack {
                    Spacer().frame(height: 4)
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
                .zIndex(2)
                .transition(.opacity)
                .animation(.easeInOut, value: showCopiedMessage)
            }
            
            ScrollView {
                // Add top spacing for navigation bar clearance
                Color.clear.frame(height: 80)
                
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
            .refreshable {
                refreshGame()
            }
            // Fix keyboard movement issues
            .ignoresSafeArea(.keyboard)
            
            // Share prompt overlay
            if showSharePrompt {
                ZStack {
                    Color.black.opacity(0.7)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation {
                                showSharePrompt = false
                            }
                        }
                    
                    VStack(spacing: 20) {
                        Text("Game Created!")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Share this game with your friends so they can join!")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                copyGameLink()
                                withAnimation {
                                    showSharePrompt = false
                                }
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "link.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    
                                    Text("Copy Link")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 100, height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                )
                            }
                            
                            Button(action: {
                                shareGame()
                                withAnimation {
                                    showSharePrompt = false
                                }
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    
                                    Text("Share")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 100, height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                )
                            }
                        }
                        
                        Button(action: {
                            withAnimation {
                                showSharePrompt = false
                            }
                        }) {
                            Text("Not Now")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.95)))
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, 40)
                }
                .zIndex(3)
                .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                let currentGame = liveGame ?? game
                Text(currentGame.status == .completed ? "Game Summary" :
                        (isGameCreator ? "Game Management" : "Game Details"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.white)
                }
            }
            
            if isGameCreator && (liveGame ?? game).status == .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: copyGameLink) {
                        Image(systemName: "link")
                            .foregroundColor(.white)
                    }
                    .help("Copy game link")
                    .accessibilityLabel("Copy game link")
                }
            }
        }
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
            // Refresh game data immediately to get latest status
            refreshGame()
            setupLiveUpdates()
            
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