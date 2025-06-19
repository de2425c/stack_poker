import SwiftUI
import FirebaseAuth

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
    @EnvironmentObject var sessionStore: SessionStore
    
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
        .background(
            NavigationLink(
                destination: Group {
                    if let game = game {
                        HomeGameDetailView(game: game, onGameUpdated: {
                            // This callback will be triggered after game updates
                            setupLiveUpdates()  // Refresh the current preview when returning
                        })
                        .navigationBarBackButtonHidden(true)  // Hide default back button
                        .environmentObject(sessionStore)
                    }
                },
                isActive: $showingGameDetail
            ) {
                EmptyView()
            }
        )
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
                let profit = player.currentStack - player.totalBuyIn
                Text("\(profit >= 0 ? "+" : "")\(Int(profit))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(profit >= 0 ?
                                     Color(red: 123/255, green: 255/255, blue: 99/255) :
                                        Color.red)
                
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
                        // Add top spacing for navigation bar clearance
                        Color.clear.frame(height: 60)
                        
                        // Amount input using GlassyInputField
                        GlassyInputField(
                            icon: "dollarsign.circle.fill",
                            title: "REBUY AMOUNT",
                            labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
                        ) {
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
                            .padding(.vertical, 8)
                        }
                        
                        Text("Your rebuy request will be sent to the game creator for approval.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Submit button with bottom padding
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
                        .padding(.bottom, 60) // Added more bottom padding
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
                // Add tap to dismiss keyboard
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                // Fix keyboard movement issues
                .ignoresSafeArea(.keyboard)
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
        
        private var netProfitLoss: Double {
            return player.currentStack - player.totalBuyIn
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
                
                // Net profit/loss
                Text(player.status == .cashedOut ? 
                     "\(netProfitLoss >= 0 ? "+" : "")\(Int(netProfitLoss))" : "—")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(player.status == .cashedOut ?
                                     (netProfitLoss >= 0 ?
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
    
    // Settlement Transaction Row for optimal settlement display
    struct SettlementTransactionRow: View {
        let transaction: HomeGameDetailView.SettlementTransaction
        let index: Int
        
        var body: some View {
            HStack(spacing: 12) {
                // Transaction number
                ZStack {
                    Circle()
                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .frame(width: 28, height: 28)
                    
                    Text("\(index)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                }
                
                // Transaction details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transaction.fromPlayer)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        
                        Text(transaction.toPlayer)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Payment settles debt")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(Int(transaction.amount))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    
                    Text("amount")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
    
    // Modern Settlement Transaction Row with improved design
    struct ModernSettlementTransactionRow: View {
        let transaction: HomeGameDetailView.SettlementTransaction
        let index: Int
        @State private var showCopied = false
        
        var body: some View {
            Button(action: {
                // Copy amount to clipboard
                UIPasteboard.general.string = "\(Int(transaction.amount))"
                
                // Show feedback
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCopied = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showCopied = false
                    }
                }
            }) {
                HStack(spacing: 16) {
                    // Step indicator
                    ZStack {
                        Circle()
                            .fill(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.2))
                            .frame(width: 36, height: 36)
                        
                        Text("\(index)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    }
                    
                    // Transaction flow
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(transaction.fromPlayer)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text(transaction.toPlayer)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Debt settlement")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Amount with copy feedback
                    VStack(alignment: .trailing, spacing: 4) {
                        if showCopied {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                
                                Text("Copied!")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            }
                        } else {
                            Text("$\(Int(transaction.amount))")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor(red: 28/255, green: 30/255, blue: 34/255, alpha: 1.0)))
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
                .clipped()
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // CashOut view to request cashing out
    struct CashOutView: View {
        @Environment(\.presentationMode) var presentationMode
        @StateObject private var homeGameService = HomeGameService()
        
        let gameId: String
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
                        // Add top spacing for navigation bar clearance
                        Color.clear.frame(height: 60)
                        
                        // Amount input using GlassyInputField
                        GlassyInputField(
                            icon: "dollarsign.circle.fill",
                            title: "CASH OUT AMOUNT",
                            labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
                        ) {
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
                            .padding(.vertical, 8)
                        }
                        
                        Text("Your cash-out request will be sent to the host for processing.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Submit button with bottom padding
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
                        .padding(.bottom, 60) // Added more bottom padding
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
                // Add tap to dismiss keyboard
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                // Fix keyboard movement issues
                .ignoresSafeArea(.keyboard)
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
                        // Add top spacing for navigation bar clearance
                        Color.clear.frame(height: 60)
                        
                        // Amount input using GlassyInputField
                        GlassyInputField(
                            icon: "dollarsign.circle.fill",
                            title: "REBUY AMOUNT",
                            labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
                        ) {
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
                            .padding(.vertical, 8)
                        }
                        
                        Text("Your host rebuy request will be sent for approval.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Submit button with bottom padding
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
                        .padding(.bottom, 60) // Added more bottom padding
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .navigationBarTitle("Host Rebuy", displayMode: .inline)
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
                // Add tap to dismiss keyboard
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                // Fix keyboard movement issues
                .ignoresSafeArea(.keyboard)
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
                                // Add top spacing for navigation bar clearance
                                Color.clear.frame(height: 60)
                                
                                Text("End Game")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Set final cashout amounts for all active players")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                // Active players with GlassyInputField
                                if let game = game, !game.players.filter({ $0.status == .active }).isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text("Active Players")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        // Player cashout form rows
                                        ForEach(game.players.filter { $0.status == .active }) { player in
                                            PlayerCashoutRowWithGlassy(
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
                                
                                // End game button with bottom padding
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
                                .padding(.bottom, 60) // Added more bottom padding
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
                // Add tap to dismiss keyboard
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                // Fix keyboard movement issues
                .ignoresSafeArea(.keyboard)
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
    struct PlayerCashoutRowWithGlassy: View {
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
                    
                    // Cashout amount input using GlassyInputField
                    GlassyInputField(
                        icon: "dollarsign.circle",
                        title: "",
                        glassOpacity: 0.05,
                        materialOpacity: 0.4
                    ) {
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
                                .frame(width: 60)
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(width: 120)
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
                        // Add top spacing for navigation bar clearance
                        Color.clear.frame(height: 60)
                        
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
                .navigationBarTitle("Cash Out", displayMode: .inline)
                // Add tap to dismiss keyboard
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                // Fix keyboard movement issues
                .ignoresSafeArea(.keyboard)
            }
        }
    }


