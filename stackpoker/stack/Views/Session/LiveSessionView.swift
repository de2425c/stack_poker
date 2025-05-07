import SwiftUI
import FirebaseFirestore

struct LiveSessionView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    let userId: String
    @ObservedObject var sessionStore: SessionStore
    private let db = Firestore.firestore()
    
    // Form Data
    @State private var selectedGame: GameOption?
    @State private var buyIn = ""
    @State private var cashout = ""
    @State private var isLoading = false
    @State private var showingAddGame = false
    @State private var showingRebuyAlert = false
    @State private var rebuyAmount = ""
    @State private var showingExitAlert = false
    @State private var showingCashoutPrompt = false
    @State private var sessionMode: SessionMode = .setup
    
    enum SessionMode {
        case setup     // Initial game selection and buy-in
        case active    // Session is running
        case paused    // Session is paused
        case ending    // Session has ended, entering cashout
    }
    
    @StateObject private var gameService: CustomGameService
    
    init(userId: String, sessionStore: SessionStore) {
        self.userId = userId
        self.sessionStore = sessionStore
        _gameService = StateObject(wrappedValue: CustomGameService(userId: userId))
    }
    
    private var formattedElapsedTime: (hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = Int(sessionStore.liveSession.elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return (hours, minutes, seconds)
    }
    
    private var formattedHours: String {
        let hours = sessionStore.liveSession.elapsedTime / 3600
        return String(format: "%.1f", hours)
    }
    
    var setupSectionView: some View {
        VStack(spacing: 24) {
            // Game Selection Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Select Game")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.leading, 2)
                    
                    Spacer()
                    
                    Button(action: { showingAddGame = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    }
                }
                
                if gameService.customGames.isEmpty {
                    Text("No games added yet. Tap + to add a game.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(gameService.customGames) { game in
                                GameOptionCards(
                                    game: GameOption(name: game.name, stakes: game.stakes),
                                    isSelected: selectedGame?.name == game.name && selectedGame?.stakes == game.stakes,
                                    action: { selectedGame = GameOption(name: game.name, stakes: game.stakes) }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
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
                    .padding(.leading, 2)
                
                VStack(spacing: 16) {
                    // Enhanced Buy-in field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Buy In")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                        
                        HStack {
                            Text("$")
                                .foregroundColor(.gray)
                                .font(.system(size: 18, weight: .semibold))
                            
                            TextField("0.00", text: $buyIn)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .font(.system(size: 20, weight: .medium))
                                .frame(height: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    var timerSectionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session Timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading, 2)
            
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
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                .padding(.leading, 2)
            
            VStack(spacing: 16) {
                // Enhanced Buy-in display (non-editable)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Buy In")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text(String(format: "%.2f", sessionStore.liveSession.buyIn))
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                
                // Enhanced Cashout field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cashout")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.gray)
                            .font(.system(size: 18, weight: .semibold))
                        
                        TextField("0.00", text: $cashout)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 44)
                        
                        // Show profit/loss preview if cashout has a value
                        if let cashoutValue = Double(cashout) {
                            let profit = cashoutValue - sessionStore.liveSession.buyIn
                            let isProfit = profit >= 0
                            
                            Text(String(format: "%@$%.2f", isProfit ? "+" : "", profit))
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
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
                    .padding(.leading, 2)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionStore.liveSession.gameName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(sessionStore.liveSession.stakes)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
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
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                    .padding(.leading, 2)
                
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
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Different content based on session mode
                        switch sessionMode {
                        case .setup:
                            setupSectionView
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
                        .disabled(selectedGame == nil || buyIn.isEmpty)
                        .opacity((selectedGame == nil || buyIn.isEmpty) ? 0.6 : 1)
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
                    case .active, .paused:
                        // No bottom button needed, actions are in the active view
                        EmptyView()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 34)
            }
            .navigationTitle(
                sessionMode == .setup ? "New Session" : 
                sessionMode == .ending ? "End Session" : 
                "Live Session"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { 
                        if sessionMode == .active {
                            showingExitAlert = true
                        } else if sessionMode == .ending {
                            // Go back to active session
                            withAnimation {
                                sessionMode = .active
                                sessionStore.resumeLiveSession()
                            }
                        } else {
                            dismiss() 
                        }
                    }) {
                        Image(systemName: sessionMode == .ending ? "chevron.left" : "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                if sessionMode == .active {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Minimize") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .alert("End Session?", isPresented: $showingExitAlert) {
                Button("Cancel", role: .cancel) { }
                Button("End Without Saving", role: .destructive) {
                    sessionStore.clearLiveSession()
                    dismiss()
                }
            } message: {
                Text("Your live session is still running. Do you want to end it without saving?")
            }
            .alert("Add Rebuy", isPresented: $showingRebuyAlert) {
                TextField("Amount", text: $rebuyAmount)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { 
                    rebuyAmount = ""
                }
                Button("Add") {
                    addRebuy()
                }
            } message: {
                Text("Enter rebuy amount")
            }
            .alert("End Session", isPresented: $showingCashoutPrompt) {
                Button("Cancel", role: .cancel) {
                    // Stay in active mode
                }
                Button("End Session", role: .destructive) {
                    endSession()
                }
            } message: {
                Text("Do you want to end your session and enter your cashout amount?")
            }
            .sheet(isPresented: $showingAddGame) {
                AddCustomGameView(gameService: gameService)
            }
            .onAppear {
                // Check if there's a live session already running
                if sessionStore.liveSession.isActive || sessionStore.showLiveSessionBar {
                    sessionMode = sessionStore.liveSession.isActive ? .active : .paused
                }
            }
            .onChange(of: sessionStore.liveSession.isActive) { isActive in
                withAnimation {
                    sessionMode = isActive ? .active : .paused
                }
            }
            .onDisappear {
                // Safety check: If we're in ending mode and the view disappears without saving,
                // we should clear the session state to prevent it from reappearing
                if sessionMode == .ending {
                    sessionStore.clearLiveSession()
                }
            }
        }
        .interactiveDismissDisabled(sessionMode == .active)
    }
    
    private func startSession() {
        guard let game = selectedGame, let buyInValue = Double(buyIn) else { return }
        
        // Start session in session store
        sessionStore.startLiveSession(
            gameName: game.name,
            stakes: game.stakes,
            buyIn: buyInValue
        )
        
        // Update local UI
        withAnimation {
            sessionMode = .active
        }
    }
    
    private func pauseSession() {
        sessionStore.pauseLiveSession()
        withAnimation { sessionMode = .paused }
    }
    
    private func resumeSession() {
        sessionStore.resumeLiveSession()
        withAnimation { sessionMode = .active }
    }
    
    private func endSession() {
        // Go directly to cashout mode, do not pause first
        sessionStore.stopLiveSessionTimer() // Stop timer, but do not pause (so isActive stays true until save)
        withAnimation {
            sessionMode = .ending
        }
    }
    
    private func addRebuy() {
        // Get the rebuy amount from the input field
        if let rebuyValue = Double(rebuyAmount), rebuyValue > 0 {
            // Update the session store with the new buy-in
            sessionStore.updateLiveSessionBuyIn(amount: rebuyValue)
        }
        
        // Reset the rebuy amount field
        rebuyAmount = ""
    }
    
    private func saveSession() {
        guard let cashoutValue = Double(cashout) else { return }
        isLoading = true
        
        // Store important session data locally before clearing
        let gameName = sessionStore.liveSession.gameName
        let stakes = sessionStore.liveSession.stakes
        let buyIn = sessionStore.liveSession.buyIn
        let startTime = sessionStore.liveSession.startTime
        let elapsedTime = sessionStore.liveSession.elapsedTime
        
        // Clear session state immediately to prevent race conditions
        sessionStore.clearLiveSession()
        
        // Create session data with the stored values
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "CASH GAME",
            "gameName": gameName,
            "stakes": stakes,
            "startDate": Timestamp(date: startTime),
            "startTime": Timestamp(date: startTime),
            "endTime": Timestamp(date: Date()),
            "hoursPlayed": elapsedTime / 3600,
            "buyIn": buyIn,
            "cashout": cashoutValue,
            "profit": cashoutValue - buyIn,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Save the session with our local data
        db.collection("sessions").addDocument(data: sessionData) { error in
            DispatchQueue.main.async {
                self.isLoading = false
                if error == nil {
                    // Session saved successfully
                    dismiss()
                } else {
                    // In a real app, you'd want to handle the error
                    print("Error saving session: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
}

// Update the GameOptionCard to match the past session view style
struct GameOptionCards: View {
    let game: GameOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.stakes)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text(game.name)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 120)
            .frame(maxWidth: .infinity)
            .aspectRatio(1.7, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? 
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                    Color.gray.opacity(0.3), 
                                    lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
    }
}

