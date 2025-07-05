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
    @State private var ante = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Minimal top padding
                            Spacer()
                                .frame(height: 8)
                            
                            // Game Name Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GAME NAME")
                                    .font(.plusJakarta(.caption, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                TextField("", text: $gameName)
                                    .placeholderss(when: gameName.isEmpty) {
                                        Text("Bellagio, Venetian, Wynn, etc.")
                                            .foregroundColor(.gray.opacity(0.7))
                                            .font(.plusJakarta(.body, weight: .regular))
                                    }
                                    .foregroundColor(.white)
                                    .font(.plusJakarta(.body, weight: .regular))
                                    .padding()
                                    .background(glassyBackground())
                            }
                            
                            // Game Type Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GAME TYPE")
                                    .font(.plusJakarta(.caption, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                HStack {
                                    ForEach(PokerVariant.allCases, id: \.self) { variant in
                                        Button(action: {
                                            selectedGameType = variant
                                        }) {
                                            Text(variant.displayName)
                                                .font(.plusJakarta(.caption, weight: .medium))
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
                            VStack(alignment: .leading, spacing: 12) {
                                Text("STAKES")
                                    .font(.plusJakarta(.caption, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                HStack(spacing: 12) {
                                    // Small Blind
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Small Blind")
                                            .font(.plusJakarta(.caption2, weight: .medium))
                                            .foregroundColor(.gray)
                                        
                                        HStack {
                                            Text("$")
                                                .foregroundColor(.gray)
                                                .font(.plusJakarta(.body, weight: .regular))
                                            TextField("", text: $smallBlind)
                                                .keyboardType(.decimalPad)
                                                .font(.plusJakarta(.body, weight: .regular))
                                                .placeholderss(when: smallBlind.isEmpty) {
                                                    Text("1")
                                                        .foregroundColor(.gray.opacity(0.7))
                                                        .font(.plusJakarta(.body, weight: .regular))
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
                                            .font(.plusJakarta(.caption2, weight: .medium))
                                            .foregroundColor(.gray)
                                        
                                        HStack {
                                            Text("$")
                                                .foregroundColor(.gray)
                                                .font(.plusJakarta(.body, weight: .regular))
                                            TextField("", text: $bigBlind)
                                                .keyboardType(.decimalPad)
                                                .font(.plusJakarta(.body, weight: .regular))
                                                .placeholderss(when: bigBlind.isEmpty) {
                                                    Text("2")
                                                        .foregroundColor(.gray.opacity(0.7))
                                                        .font(.plusJakarta(.body, weight: .regular))
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
                                        .font(.plusJakarta(.caption2, weight: .medium))
                                        .foregroundColor(.gray)
                                    
                                    HStack {
                                        Text("$")
                                            .foregroundColor(.gray)
                                            .font(.plusJakarta(.body, weight: .regular))
                                        TextField("", text: $straddle)
                                            .keyboardType(.decimalPad)
                                            .font(.plusJakarta(.body, weight: .regular))
                                            .placeholderss(when: straddle.isEmpty) {
                                                Text("5")
                                                    .foregroundColor(.gray.opacity(0.7))
                                                    .font(.plusJakarta(.body, weight: .regular))
                                            }
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(glassyBackground())
                                }
                                
                                // Optional Ante
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ante (Optional)")
                                        .font(.plusJakarta(.caption2, weight: .medium))
                                        .foregroundColor(.gray)
                                    
                                    HStack {
                                        Text("$")
                                            .foregroundColor(.gray)
                                            .font(.plusJakarta(.body, weight: .regular))
                                        TextField("", text: $ante)
                                            .keyboardType(.decimalPad)
                                            .font(.plusJakarta(.body, weight: .regular))
                                            .placeholderss(when: ante.isEmpty) {
                                                Text("1")
                                                    .foregroundColor(.gray.opacity(0.7))
                                                    .font(.plusJakarta(.body, weight: .regular))
                                            }
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(glassyBackground())
                                }
                            }
                            
                            // Save Button - Right after ante field
                            Button(action: saveGame) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                                } else {
                                    Text("Add Game")
                                        .font(.plusJakarta(.body, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 27)
                                    .fill(Color.gray.opacity(isFormValid ? 0.7 : 0.3))
                            )
                            .disabled(!isFormValid || isLoading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 500) // Limit the maximum width
                        .frame(maxWidth: .infinity) // Center in available space
                    }
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .navigationTitle("Add New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Add New Game")
                        .font(.plusJakarta(.headline, weight: .semibold))
                        .foregroundColor(.white)
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
        
        if !ante.isEmpty {
            guard let anteValue = Double(ante),
                  anteValue > 0 else {
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
                let anteValue = ante.isEmpty ? nil : Double(ante)
                
                try await cashGameService.addCashGame(
                    name: gameName,
                    smallBlind: sb,
                    bigBlind: bb,
                    straddle: str,
                    ante: anteValue,
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
    private func glassyBackground(glassOpacity: Double = 0.03, materialOpacity: Double = 0.25) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThinMaterial)
                .opacity(materialOpacity)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(glassOpacity))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
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
