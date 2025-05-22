import SwiftUI
import FirebaseFirestore
import FirebaseAuth

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
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.gray)
                        Text("Buy in")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    }
                    
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
                        .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Enhanced Cashout field
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.gray)
                    Text("Cashout")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    }
                    
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
                        .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
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
    
    @StateObject private var cashGameService = CashGameService(userId: Auth.auth().currentUser?.uid ?? "")
    
    private let gameTypes = ["CASH GAME", "TOURNAMENT", "EXPENSE"]
    
    // Colors & Font
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94) // Light cream for high contrast
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84) // Slightly darker cream
    private let glassOpacity = 0.01 // Ultra-low opacity for extreme transparency
    private let materialOpacity = 0.2 // Lower material opacity
    
    init(userId: String) {
        self.userId = userId
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
    
    private func formatStakes(game: CashGame) -> String {
        var stakes = "$\(Int(game.smallBlind))/$\(Int(game.bigBlind))"
        if let straddle = game.straddle, straddle > 0 {
            stakes += " $\(Int(straddle))"
        }
        return stakes
    }
    
    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ZStack {
                    // Background
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Content
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 20) {
                                Spacer()
                                    .frame(height: 64)
                                    
                                // Game Selection Section
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Game")
                                        .font(.plusJakarta(.headline, weight: .medium))
                                        .foregroundColor(primaryTextColor)
                                        .padding(.leading, 6)
                                        .padding(.bottom, 2)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(cashGameService.cashGames) { game in
                                                let stakes = formatStakes(game: game)
                                                GameCard(
                                                    stakes: stakes,
                                                    name: game.name,
                                                    isSelected: selectedGame?.name == game.name && selectedGame?.stakes == stakes,
                                                    titleColor: primaryTextColor,
                                                    subtitleColor: secondaryTextColor,
                                                    glassOpacity: glassOpacity,
                                                    materialOpacity: materialOpacity
                                                )
                                                .onTapGesture {
                                                    selectedGame = GameOption(
                                                        name: game.name,
                                                        stakes: stakes
                                                    )
                                                }
                                            }
                                            // Add Game Button
                                            AddGameButton(
                                                textColor: primaryTextColor,
                                                glassOpacity: glassOpacity,
                                                materialOpacity: materialOpacity
                                            )
                                            .onTapGesture {
                                                showingAddGame = true
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding(.horizontal)
                                
                                // Time & Duration Section
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Time & Duration")
                                        .font(.plusJakarta(.headline, weight: .medium))
                                        .foregroundColor(primaryTextColor)
                                        .padding(.leading, 6)
                                        .padding(.bottom, 2)
                                    
                                    // Date and Time Grid
                                    VStack(spacing: 12) {
                                        // First row
                                        HStack(spacing: 12) {
                                            // Start Date
                                            GlassyInputField(
                                                icon: "calendar",
                                                title: "Start Date",
                                                content: AnyGlassyContent(DatePickerContent(date: $startDate, displayMode: .date)),
                                                glassOpacity: glassOpacity,
                                                labelColor: secondaryTextColor,
                                                materialOpacity: materialOpacity
                                            )
                                            
                                            // Start Time
                                            GlassyInputField(
                                                icon: "clock",
                                                title: "Start Time",
                                                content: AnyGlassyContent(DatePickerContent(date: $startTime, displayMode: .hourAndMinute)),
                                                glassOpacity: glassOpacity,
                                                labelColor: secondaryTextColor,
                                                materialOpacity: materialOpacity
                                            )
                                        }
                                        
                                        // Second row
                                        HStack(spacing: 12) {
                                            // Hours Played
                                            GlassyInputField(
                                                icon: "timer",
                                                title: "Hours Played",
                                                content: AnyGlassyContent(TextFieldContent(text: Binding.constant(calculatedHoursPlayed), keyboardType: .decimalPad, isReadOnly: true, textColor: primaryTextColor)),
                                                glassOpacity: glassOpacity,
                                                labelColor: secondaryTextColor,
                                                materialOpacity: materialOpacity
                                            )
                                            
                                            // End Time
                                            GlassyInputField(
                                                icon: "clock",
                                                title: "End Time",
                                                content: AnyGlassyContent(DatePickerContent(date: $endTime, displayMode: .hourAndMinute)),
                                                glassOpacity: glassOpacity,
                                                labelColor: secondaryTextColor,
                                                materialOpacity: materialOpacity
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                
                                // Game Info Section
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Game Info")
                                        .font(.plusJakarta(.headline, weight: .medium))
                                        .foregroundColor(primaryTextColor)
                                        .padding(.leading, 6)
                                        .padding(.bottom, 2)
                                    
                                    VStack(spacing: 12) {
                                        // Buy In
                                        GlassyInputField(
                                            icon: "dollarsign.circle",
                                            title: "Buy in",
                                            content: AnyGlassyContent(TextFieldContent(text: $buyIn, keyboardType: .decimalPad, prefix: "$", textColor: primaryTextColor, prefixColor: secondaryTextColor)),
                                            glassOpacity: glassOpacity,
                                            labelColor: secondaryTextColor,
                                            materialOpacity: materialOpacity
                                        )
                                        
                                        // Cashout
                                        GlassyInputField(
                                            icon: "dollarsign.circle",
                                            title: "Cashout",
                                            content: AnyGlassyContent(TextFieldContent(text: $cashout, keyboardType: .decimalPad, prefix: "$", textColor: primaryTextColor, prefixColor: secondaryTextColor)),
                                            glassOpacity: glassOpacity,
                                            labelColor: secondaryTextColor,
                                            materialOpacity: materialOpacity
                                        )
                                    }
                                }
                                .padding(.horizontal)
                                
                                Spacer()
                            }
                        }
                        
                        // Add Session Button
                        VStack {
                            Button(action: addSession) {
                                HStack {
                                    Text("Add Session")
                                        .font(.plusJakarta(.body, weight: .bold))
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .padding(.leading, 8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.gray.opacity(0.7))
                                .foregroundColor(primaryTextColor)
                                .cornerRadius(27)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 34)
                        }
                        .background(Color.clear)
                        .padding(.bottom, 50)
                    }
                    .frame(width: geometry.size.width)
                }
                .navigationTitle("Past Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white) // Keep back button white
                        }
                    }
                    ToolbarItem(placement: .principal) { // For NavigationTitle font
                        Text("Past Session")
                            .font(.plusJakarta(.headline, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("Done") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            .font(.plusJakarta(.body, weight: .medium))
                            .foregroundColor(primaryTextColor)
                        }
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        .sheet(isPresented: $showingAddGame) {
            AddCashGameView(cashGameService: cashGameService)
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

// MARK: - Component Views

// Game card with stakes and name
struct GameCard: View {
    let stakes: String
    let name: String
    let isSelected: Bool
    var titleColor: Color = Color(white: 0.25)
    var subtitleColor: Color = Color(white: 0.4)
    var glassOpacity: Double = 0.01
    var materialOpacity: Double = 0.2
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stakes)
                .font(.plusJakarta(.title3, weight: .bold))
                .foregroundColor(titleColor)
            
            Text(name)
                .font(.plusJakarta(.caption, weight: .medium))
                .foregroundColor(subtitleColor)
        }
        .frame(width: 130)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                // Ultra-transparent glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                // Almost invisible white overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Add game button
struct AddGameButton: View {
    var textColor: Color = Color(white: 0.25)
    var glassOpacity: Double = 0.01
    var materialOpacity: Double = 0.2
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 24)) // System font for icon
                .foregroundColor(textColor)
            
            Text("Add")
                .font(.plusJakarta(.body, weight: .medium))
                .foregroundColor(textColor)
        }
        .frame(width: 130)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                // Ultra-transparent glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                // Almost invisible white overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Protocol for glass content
protocol GlassyContent {
    associatedtype ContentView: View
    @ViewBuilder var body: ContentView { get }
}

// Type-erased wrapper for GlassyContent
struct AnyGlassyContent: View {
    private let content: AnyView
    
    init<T: GlassyContent>(_ content: T) {
        self.content = AnyView(content.body)
    }
    
    var body: some View {
        content
    }
}

struct DatePickerContent: GlassyContent {
    @Binding var date: Date
    let displayMode: DatePickerComponents
    
    var body: some View {
        DatePicker("", selection: $date, displayedComponents: displayMode)
            .labelsHidden()
            .colorScheme(.dark)
            .scaleEffect(0.95)
            .frame(height: 35)
    }
}

struct TextFieldContent: GlassyContent {
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var prefix: String? = nil
    var isReadOnly: Bool = false
    var textColor: Color = Color(white: 0.25)
    var prefixColor: Color = Color(white: 0.4)
    
    var body: some View {
        HStack {
            if let prefix = prefix {
                Text(prefix)
                    .font(.plusJakarta(.body, weight: .semibold))
                    .foregroundColor(prefixColor)
            }
            
            if isReadOnly {
                Text(text)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(textColor)
            } else {
                TextField("", text: $text)
                    .keyboardType(keyboardType)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(textColor)
            }
        }
        .frame(height: 35)
    }
}

// Glassy input field with consistent styling
struct GlassyInputField<Content: View>: View {
    let icon: String
    let title: String
    let content: Content
    var glassOpacity: Double = 0.01
    var labelColor: Color = Color(white: 0.4)
    var materialOpacity: Double = 0.2
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14)) // System font for icon
                    .foregroundColor(labelColor)
                Text(title)
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(labelColor)
            }
            
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Ultra-transparent glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                // Almost invisible white overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
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
                .fill(Color.white.opacity(0.5))
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
                .fill(Color.white.opacity(0.5))
        )
    }
} 
