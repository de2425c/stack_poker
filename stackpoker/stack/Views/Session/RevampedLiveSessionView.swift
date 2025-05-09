import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RevampedLiveSessionView: View {
    @Environment(\.dismiss) var dismiss
    let userId: String
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var cashGameService = CashGameService(userId: Auth.auth().currentUser?.uid ?? "")
    @StateObject private var gameService = CustomGameService(userId: Auth.auth().currentUser?.uid ?? "")
    
    // Form Data
    @State private var selectedGame: CashGame?
    @State private var buyIn = ""
    @State private var cashout = ""
    @State private var isLoading = false
    @State private var showingAddGame = false
    @State private var showingRebuyAlert = false
    @State private var rebuyAmount = ""
    @State private var showingExitAlert = false
    @State private var showingCashoutPrompt = false
    @State private var selectedTab: PokerGameType = .cash
    @State private var sessionMode: SessionMode = .setup
    
    enum SessionMode {
        case setup     // Initial game selection and buy-in
        case active    // Session is running
        case paused    // Session is paused
        case ending    // Session has ended, entering cashout
    }
    
    // Initialize correct session mode based on live session state
    private func initializeSessionMode() {
        // If there's an active live session, show the active/paused view instead of setup
        if sessionStore.liveSession.buyIn > 0 {
            if sessionStore.liveSession.isActive {
                sessionMode = .active
            } else if sessionStore.liveSession.lastPausedAt != nil {
                sessionMode = .paused
            }
            print("Initialized session mode to: \(sessionMode)")
        } else {
            print("No active session, showing setup")
            sessionMode = .setup
        }
    }
    
    private var formattedElapsedTime: (hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = Int(sessionStore.liveSession.elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return (hours, minutes, seconds)
    }
    
    var setupCashGameView: some View {
        VStack(spacing: 24) {
            // Game Selection Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Select Game")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showingAddGame = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    }
                }
                
                if cashGameService.cashGames.isEmpty {
                    Text("No games added yet. Tap + to add a game.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(cashGameService.cashGames) { game in
                                CashGameCard(
                                    game: game,
                                    isSelected: selectedGame?.id == game.id,
                                    action: { selectedGame = game }
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal)
            
            // Game Info Section - Buy-in
            VStack(alignment: .leading, spacing: 12) {
                Text("Game Info")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                VStack(spacing: 16) {
                    // Enhanced Buy-in field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BUY IN")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .padding(.leading, 4)
                        
                        HStack {
                            Text("$")
                                .foregroundColor(.gray)
                                .font(.system(size: 18, weight: .semibold))
                            
                            TextField("0", text: $buyIn)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .font(.system(size: 20, weight: .medium))
                                .frame(height: 44)
                        }
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    var setupTournamentView: some View {
        VStack {
            // Placeholder for tournament setup - will be implemented later
            Text("Tournament tracking coming soon")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
        .padding(.horizontal)
    }
    
    var timerSectionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session Timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                // Hours
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hours")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(formattedElapsedTime.hours)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                
                // Minutes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minutes")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(formattedElapsedTime.minutes)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                
                // Seconds
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seconds")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(formattedElapsedTime.seconds)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal)
    }
    
    var cashoutSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Info")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                // Enhanced Buy-in display (non-editable)
                VStack(alignment: .leading, spacing: 6) {
                    Text("BUY IN")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .padding(.leading, 4)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text(String(format: "%.0f", sessionStore.liveSession.buyIn))
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 44)
                    }
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                
                // Enhanced Cashout field
                VStack(alignment: .leading, spacing: 6) {
                    Text("CASHOUT")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .padding(.leading, 4)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 18, weight: .semibold))
                        
                        TextField("0", text: $cashout)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 44)
                        
                        // Show profit/loss preview if cashout has a value
                        if let cashoutValue = Double(cashout) {
                            let profit = cashoutValue - sessionStore.liveSession.buyIn
                            let isProfit = profit >= 0
                            
                            Text(String(format: "%@$%.0f", isProfit ? "+" : "", profit))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isProfit ? 
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                    Color.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isProfit ? 
                                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.2)) : 
                                            Color.red.opacity(0.2))
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal)
    }
    
    var activeSessionView: some View {
        VStack(spacing: 24) {
            // Game Summary Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Game Info")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionStore.liveSession.gameName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(sessionStore.liveSession.stakes)
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Buy In")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Text("$\(Int(sessionStore.liveSession.buyIn))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            
            // Timer Section
            timerSectionView
            
            // Action Buttons
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    // Rebuy Button
                    Button(action: { showingRebuyAlert = true }) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            
                            Text("Rebuy")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.2, green: 0.2, blue: 0.6).opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                        )
                    }
                    
                    // Pause/Resume Button
                    Button(action: { sessionMode == .paused ? resumeSession() : pauseSession() }) {
                        VStack(spacing: 8) {
                            Image(systemName: sessionMode == .paused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            
                            Text(sessionMode == .paused ? "Resume" : "Pause")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(sessionMode == .paused ? 
                                      Color(red: 0.2, green: 0.6, blue: 0.2).opacity(0.8) : 
                                      Color(red: 0.6, green: 0.4, blue: 0.1).opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(sessionMode == .paused ?
                                        Color.green.opacity(0.4) :
                                        Color.orange.opacity(0.4), lineWidth: 1)
                        )
                    }
                    
                    // End Button
                    Button(action: { showingCashoutPrompt = true }) {
                        VStack(spacing: 8) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            
                            Text("End")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.6, green: 0.1, blue: 0.1).opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                
                VStack(spacing: 0) {
                    if sessionMode == .setup {
                        // Game Type Tabs
                        HStack(spacing: 0) {
                            ForEach(PokerGameType.allCases, id: \.self) { tab in
                                Button(action: { 
                                    selectedTab = tab
                                    selectedGame = nil
                                }) {
                                    Text(tab.rawValue)
                                        .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                                        .foregroundColor(selectedTab == tab ? .white : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            selectedTab == tab ?
                                                Color(red: 30/255, green: 33/255, blue: 36/255) :
                                                Color.clear
                                        )
                                }
                            }
                        }
                        .background(Color(red: 25/255, green: 28/255, blue: 32/255))
                    }
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            // Different content based on session mode and selected tab
                            switch sessionMode {
                            case .setup:
                                if selectedTab == .cash {
                                    setupCashGameView
                                } else {
                                    setupTournamentView
                                }
                            case .active, .paused:
                                activeSessionView
                            case .ending:
                                cashoutSectionView
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 100) // Extra padding for the button at bottom
                    }
                    
                    // Bottom Button
                    VStack {
                        Spacer()
                        
                        switch sessionMode {
                        case .setup:
                            Button(action: startSession) {
                                Text("Start Session")
                                    .font(.system(size: 17, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .foregroundColor(.black)
                                    .cornerRadius(27)
                            }
                            .disabled(selectedGame == nil || buyIn.isEmpty || (selectedTab == .tournament))
                            .opacity(selectedGame == nil || buyIn.isEmpty || (selectedTab == .tournament) ? 0.6 : 1)
                            .padding(.horizontal)
                            .padding(.bottom, 34)
                        case .ending:
                            Button(action: saveSession) {
                                HStack {
                                    Text("Save Session")
                                        .font(.system(size: 17, weight: .bold))
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .padding(.leading, 8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .foregroundColor(.black)
                                .cornerRadius(27)
                            }
                            .disabled(cashout.isEmpty)
                            .opacity(cashout.isEmpty ? 0.6 : 1)
                            .padding(.horizontal)
                            .padding(.bottom, 34)
                        case .active, .paused:
                            // No bottom button needed, actions are in the active view
                            EmptyView()
                        }
                    }
                }
            }
            .navigationTitle(
                sessionMode == .setup ? "Log Live Session" : 
                sessionMode == .ending ? "End Session" : "Live Session"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(sessionMode == .setup ? "Log Live Session" : 
                         sessionMode == .ending ? "End Session" : "Live Session")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .navigationBarItems(
                leading: Button(action: {
                    if sessionMode == .setup {
                        dismiss()
                    } else if sessionMode == .ending {
                        sessionMode = sessionStore.liveSession.isActive ? .active : .paused
                    } else {
                        showingExitAlert = true
                    }
                }) {
                    Image(systemName: sessionMode == .setup ? "xmark" : "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                },
                
                // Add a trailing minimize button when in active mode
                trailing: sessionMode == .active || sessionMode == .paused ? 
                    Button(action: {
                        // Minimize the session and return to the main app
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Text("Minimize")
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.3))
                        )
                    } : nil
            )
        }
        .accentColor(.white)
        .sheet(isPresented: $showingAddGame) {
            if selectedTab == .cash {
                AddCashGameView(cashGameService: cashGameService)
            } else {
                // Placeholder for adding tournament games in the future
                AddCustomGameView(gameService: gameService)
            }
        }
        .alert("Add Rebuy", isPresented: $showingRebuyAlert) {
            TextField("Rebuy amount", text: $rebuyAmount)
                .keyboardType(.decimalPad)
            
            Button("Cancel", role: .cancel) {
                rebuyAmount = ""
            }
            
            Button("Add") {
                if let amount = Double(rebuyAmount), amount > 0 {
                    sessionStore.updateLiveSessionBuyIn(amount: amount)
                }
                rebuyAmount = ""
            }
        } message: {
            Text("Enter the amount you want to rebuy for.")
        }
        .alert("Ready to Cashout?", isPresented: $showingCashoutPrompt) {
            Button("Cancel", role: .cancel) { }
            Button("End Session") {
                sessionMode = .ending
            }
        } message: {
            Text("Are you ready to end your session and record your cashout amount?")
        }
        .alert("Exit Session?", isPresented: $showingExitAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Exit Without Saving", role: .destructive) {
                dismiss()
            }
            Button("End & Save") {
                sessionMode = .ending
            }
        } message: {
            Text("What would you like to do with your active session?")
        }
        .onAppear {
            // Initialize the correct view mode based on live session state
            print("RevampedLiveSessionView appeared")
            print("Current live session: active=\(sessionStore.liveSession.isActive), buyIn=\(sessionStore.liveSession.buyIn), game=\(sessionStore.liveSession.gameName)")
            initializeSessionMode()
        }
    }
    
    private func startSession() {
        guard let game = selectedGame, let buyInAmount = Double(buyIn), buyInAmount > 0 else { return }
        
        // Start the session
        sessionStore.startLiveSession(
            gameName: game.name,
            stakes: game.stakes,
            buyIn: buyInAmount
        )
        
        // Update mode
        sessionMode = .active
    }
    
    private func pauseSession() {
        sessionStore.pauseLiveSession()
        sessionMode = .paused
    }
    
    private func resumeSession() {
        sessionStore.resumeLiveSession()
        sessionMode = .active
    }
    
    private func saveSession() {
        guard let cashoutAmount = Double(cashout) else { return }
        isLoading = true
        
        Task {
            // End the live session and convert it to a saved session
            if let error = await sessionStore.endLiveSessionAsync(cashout: cashoutAmount) {
                // Handle error
                await MainActor.run {
                    isLoading = false
                    print("Error saving session: \(error.localizedDescription)")
                    // Could show an alert here
                }
            } else {
                // Success - dismiss the view
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    RevampedLiveSessionView(
        userId: "preview",
        sessionStore: SessionStore(userId: "preview")
    )
} 