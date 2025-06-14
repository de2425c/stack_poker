import SwiftUI
import FirebaseAuth

struct AddCashGameView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var cashGameService: CashGameService
    
    @State private var gameName = ""
    @State private var selectedGameType: PokerVariant = .nlh
    @State private var smallBlind = ""
    @State private var bigBlind = ""
    @State private var straddle = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Add top padding for transparent navigation bar
                            Spacer()
                                .frame(height: 50)
                            
                            // Game Name Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GAME NAME")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                TextField("", text: $gameName)
                                    .placeholderss(when: gameName.isEmpty) {
                                        Text("Bellagio, Venetian, Wynn, etc.")
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(glassyBackground())
                            }
                            
                            // Game Type Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GAME TYPE")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                HStack {
                                    ForEach(PokerVariant.allCases, id: \.self) { variant in
                                        Button(action: {
                                            selectedGameType = variant
                                        }) {
                                            Text(variant.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(selectedGameType == variant ? .white : .gray)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(selectedGameType == variant ? Color.white.opacity(0.2) : Color.clear)
                                                )
                                        }
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(glassyBackground())
                            }
                            
                            // Stakes Fields
                            VStack(alignment: .leading, spacing: 16) {
                                Text("STAKES")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                HStack(spacing: 12) {
                                    // Small Blind
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Small Blind")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                        
                                        HStack {
                                            Text("$")
                                                .foregroundColor(.gray)
                                            TextField("", text: $smallBlind)
                                                .keyboardType(.decimalPad)
                                                .placeholderss(when: smallBlind.isEmpty) {
                                                    Text("1")
                                                        .foregroundColor(.gray.opacity(0.7))
                                                }
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(glassyBackground())
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    // Big Blind
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Big Blind")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                        
                                        HStack {
                                            Text("$")
                                                .foregroundColor(.gray)
                                            TextField("", text: $bigBlind)
                                                .keyboardType(.decimalPad)
                                                .placeholderss(when: bigBlind.isEmpty) {
                                                    Text("2")
                                                        .foregroundColor(.gray.opacity(0.7))
                                                }
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(glassyBackground())
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .padding(.horizontal, 0)
                                
                                // Optional Straddle
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Straddle (Optional)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    
                                    HStack {
                                        Text("$")
                                            .foregroundColor(.gray)
                                        TextField("", text: $straddle)
                                            .keyboardType(.decimalPad)
                                            .placeholderss(when: straddle.isEmpty) {
                                                Text("5")
                                                    .foregroundColor(.gray.opacity(0.7))
                                            }
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(glassyBackground())
                                }
                            }
                            
                            Spacer(minLength: 40)
                            
                            // Save Button
                            Button(action: saveGame) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                                } else {
                                    Text("Add Game")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 27)
                                    .fill(Color.gray.opacity(isFormValid ? 0.4 : 0.2))
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 27))
                            )
                            .disabled(!isFormValid || isLoading)
                        }
                        .padding(24)
                        .frame(maxWidth: 500) // Limit the maximum width
                        .frame(maxWidth: .infinity) // Center in available space
                        .frame(minHeight: geometry.size.height, alignment: .top) // Ensure content starts from top
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // Position ScrollView at top
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .frame(width: geometry.size.width, height: .infinity, alignment: .top) // Position ZStack at top
            }
            .navigationTitle("Add New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
    
    private var isFormValid: Bool {
        guard !gameName.isEmpty,
              !smallBlind.isEmpty,
              !bigBlind.isEmpty,
              let sb = Double(smallBlind),
              let bb = Double(bigBlind),
              sb > 0,
              bb > 0,
              bb >= sb else {
            return false
        }
        
        if !straddle.isEmpty {
            guard let str = Double(straddle),
                  str > bb else {
                return false
            }
        }
        
        return true
    }
    
    private func saveGame() {
        isLoading = true
        
        Task {
            do {
                let sb = Double(smallBlind) ?? 0
                let bb = Double(bigBlind) ?? 0
                let str = straddle.isEmpty ? nil : Double(straddle)
                
                try await cashGameService.addCashGame(
                    name: gameName,
                    smallBlind: sb,
                    bigBlind: bb,
                    straddle: str,
                    gameType: selectedGameType
                )
                
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false

                    // Could show an alert here
                }
            }
        }
    }
    
    // Helper for glassy background styling
    private func glassyBackground(glassOpacity: Double = 0.01, materialOpacity: Double = 0.2) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThinMaterial)
                .opacity(materialOpacity)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(glassOpacity))
        }
    }
}

extension View {
    func placeholderss<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholderss: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholderss().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    AddCashGameView(cashGameService: CashGameService(userId: "preview"))
} 
