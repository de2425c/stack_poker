import SwiftUI
import FirebaseFirestore

struct GameOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let stakes: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Game Type Section
struct GameTypeSelector: View {
    let gameTypes: [String]
    @Binding var selectedGameType: Int
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<gameTypes.count, id: \.self) { index in
                Button(action: { selectedGameType = index }) {
                    Text(gameTypes[index])
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedGameType == index ? .white : .gray)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Game Selection Section
struct GameSelectionSection: View {
    let gameOptions: [GameOption]
    @Binding var selectedGame: GameOption?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Game")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading, 2)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(gameOptions) { game in
                        GameOptionCard(
                            game: game,
                            isSelected: selectedGame?.id == game.id,
                            action: { selectedGame = game }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Time and Duration Section
struct TimeAndDurationSection: View {
    @Binding var startDate: Date
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var hoursPlayed: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time & Duration")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading, 2)
            
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    DateInputField(
                        title: "Start Date",
                        systemImage: "calendar",
                        date: $startDate,
                        displayMode: .date
                    )
                    DateInputField(
                        title: "Start Time",
                        systemImage: "clock",
                        date: $startTime,
                        displayMode: .hourAndMinute
                    )
                }
                
                GridRow {
                    CustomInputField(
                        title: "Hours Played",
                        systemImage: "timer",
                        text: $hoursPlayed,
                        keyboardType: .decimalPad
                    )
                    DateInputField(
                        title: "End Time",
                        systemImage: "clock",
                        date: $endTime,
                        displayMode: .hourAndMinute
                    )
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Game Info Section
struct GameInfoSection: View {
    @Binding var buyIn: String
    @Binding var cashout: String
    
    var body: some View {
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
                        
                        // Show profit/loss preview if both fields have values
                        if let buyInValue = Double(buyIn), let cashoutValue = Double(cashout) {
                            let profit = cashoutValue - buyInValue
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
}

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss
    let userId: String
    
    // Form Data
    @State private var selectedGameType = 0
    @State private var selectedGame: GameOption?
    @State private var startDate = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var hoursPlayed = ""
    @State private var buyIn = ""
    @State private var cashout = ""
    @State private var isLoading = false
    @State private var showingAddGame = false
    
    @StateObject private var gameService: CustomGameService
    
    private let gameTypes = ["CASH GAME", "TOURNAMENT", "EXPENSE"]
    
    init(userId: String) {
        self.userId = userId
        _gameService = StateObject(wrappedValue: CustomGameService(userId: userId))
    }
    
    private var calculatedHoursPlayed: String {
        let calendar = Calendar.current
        let startDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                        minute: calendar.component(.minute, from: startTime),
                                        second: 0,
                                        of: startDate) ?? startDate
        
        var endDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                      minute: calendar.component(.minute, from: endTime),
                                      second: 0,
                                      of: startDate) ?? startDate
        
        // If end time is before start time, it means the session went into the next day
        if endDateTime < startDateTime {
            endDateTime = calendar.date(byAdding: .day, value: 1, to: endDateTime) ?? endDateTime
        }
        
        let components = calendar.dateComponents([.minute], from: startDateTime, to: endDateTime)
        let totalMinutes = Double(components.minute ?? 0)
        let hours = totalMinutes / 60.0
        return String(format: "%.1f", hours)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        GameTypeSelector(gameTypes: gameTypes, selectedGameType: $selectedGameType)
                        
                        if selectedGameType == 0 { // Cash Game
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
                                                GameOptionCard(
                                                    game: GameOption(name: game.name, stakes: game.stakes),
                                                    isSelected: selectedGame?.name == game.name && selectedGame?.stakes == game.stakes,
                                                    action: { selectedGame = GameOption(name: game.name, stakes: game.stakes) }
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 2)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            TimeAndDurationSection(
                                startDate: $startDate,
                                startTime: $startTime,
                                endTime: $endTime,
                                hoursPlayed: .constant(calculatedHoursPlayed)
                            )
                            GameInfoSection(buyIn: $buyIn, cashout: $cashout)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: selectedGameType == 1 ? "trophy.fill" : "dollarsign.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text(selectedGameType == 1 ? "Tournament tracking coming soon!" : "Expense tracking coming soon!")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                Text("We're working hard to bring you comprehensive\ntracking for all your poker activities.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.8))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }
                    }
                    .padding(.top, 12)
                }
                
                // Add Session Button
                VStack {
                    Spacer()
                    if selectedGameType == 0 {
                        Button(action: addSession) {
                            HStack {
                                Text("Add Session")
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
                        .padding(.horizontal)
                        .padding(.bottom, 34)
                    }
                }
            }
            .navigationTitle("Past Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingAddGame) {
                AddCustomGameView(gameService: gameService)
            }
        }
    }
    
    private func addSession() {
        guard let game = selectedGame else { return }
        isLoading = true
        
        let calendar = Calendar.current
        let startDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                        minute: calendar.component(.minute, from: startTime),
                                        second: 0,
                                        of: startDate) ?? startDate
        
        var endDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                      minute: calendar.component(.minute, from: endTime),
                                      second: 0,
                                      of: startDate) ?? startDate
        
        // If end time is before start time, it means the session went into the next day
        if endDateTime < startDateTime {
            endDateTime = calendar.date(byAdding: .day, value: 1, to: endDateTime) ?? endDateTime
        }
        
        let db = Firestore.firestore()
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": gameTypes[selectedGameType],
            "gameName": game.name,
            "stakes": game.stakes,
            "startDate": Timestamp(date: startDateTime),
            "startTime": Timestamp(date: startDateTime),
            "endTime": Timestamp(date: endDateTime),
            "hoursPlayed": Double(calculatedHoursPlayed) ?? 0,
            "buyIn": Double(buyIn) ?? 0,
            "cashout": Double(cashout) ?? 0,
            "profit": (Double(cashout) ?? 0) - (Double(buyIn) ?? 0),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        print("Creating session with dates:")
        print("Start DateTime: \(startDateTime)")
        print("End DateTime: \(endDateTime)")
        print("Hours Played: \(calculatedHoursPlayed)")
        
        db.collection("sessions").addDocument(data: sessionData) { error in
            DispatchQueue.main.async {
                isLoading = false
                if error == nil {
                    dismiss()
                }
            }
        }
    }
}

struct GameOptionCard: View {
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
            .frame(width: 120, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

struct DateInputField: View {
    let title: String
    let systemImage: String
    @Binding var date: Date
    let displayMode: DatePickerComponents
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            DatePicker("", selection: $date, displayedComponents: displayMode)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
        )
    }
}

struct CustomInputField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            TextField("", text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
        )
    }
} 
