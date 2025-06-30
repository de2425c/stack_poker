import SwiftUI

struct BankrollAdjustmentSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bankrollStore: BankrollStore
    let currentTotalBankroll: Double
    
    @State private var selectedOperation: BankrollOperation = .add
    @State private var amountText: String = ""
    @State private var noteText: String = ""
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    enum BankrollOperation: String, CaseIterable {
        case add = "Add"
        case subtract = "Subtract"
        
        var icon: String {
            switch self {
            case .add: return "plus.circle.fill"
            case .subtract: return "minus.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .add: return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
            case .subtract: return .red
            }
        }
    }
    
    private var isValidAmount: Bool {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: "")),
              amount > 0 else {
            return false
        }
        return true
    }
    
    private var formattedAmount: Double {
        return Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0.0
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with current bankroll
                        VStack(spacing: 8) {
                            Text("Current Bankroll")
                                .font(.plusJakarta(.subheadline, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text("$\(Int(currentTotalBankroll))")
                                .font(.plusJakarta(.largeTitle, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 20)
                        
                        // Operation selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Operation")
                                .font(.plusJakarta(.subheadline, weight: .medium))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                ForEach(BankrollOperation.allCases, id: \.self) { operation in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedOperation = operation
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: operation.icon)
                                                .font(.system(size: 16, weight: .semibold))
                                            Text(operation.rawValue)
                                                .font(.plusJakarta(.body, weight: .semibold))
                                        }
                                        .foregroundColor(selectedOperation == operation ? .white : .gray)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Material.ultraThinMaterial)
                                                    .opacity(selectedOperation == operation ? 0.3 : 0.1)
                                                
                                                if selectedOperation == operation {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(operation.color, lineWidth: 1.5)
                                                }
                                            }
                                        )
                                    }
                                    .buttonStyle(ScalePressButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Amount input
                        GlassyInputField(
                            icon: "dollarsign.circle.fill",
                            title: "Amount",
                            glassOpacity: 0.01,
                            labelColor: .gray,
                            materialOpacity: 0.2
                        ) {
                            HStack(spacing: 8) {
                                Text("$")
                                    .font(.plusJakarta(.title2, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                TextField("0", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.plusJakarta(.title2, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(height: 50)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Note input
                        GlassyInputField(
                            icon: "note.text",
                            title: "Note (Optional)",
                            glassOpacity: 0.01,
                            labelColor: .gray,
                            materialOpacity: 0.2
                        ) {
                            TextField("Add a note...", text: $noteText)
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white)
                                .frame(height: 50)
                        }
                        .padding(.horizontal, 20)
                        
                        // Preview
                        if isValidAmount {
                            VStack(spacing: 8) {
                                Text("Preview")
                                    .font(.plusJakarta(.subheadline, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                let newTotal = selectedOperation == .add ? 
                                    currentTotalBankroll + formattedAmount :
                                    currentTotalBankroll - formattedAmount
                                
                                HStack {
                                    Text("New Bankroll:")
                                        .font(.plusJakarta(.body, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Spacer()
                                    
                                    Text("$\(Int(newTotal))")
                                        .font(.plusJakarta(.title3, weight: .bold))
                                        .foregroundColor(newTotal >= 0 ? 
                                                       Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                                       .red)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Material.ultraThinMaterial)
                                        .opacity(0.2)
                                )
                            }
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        Spacer(minLength: 60)
                    }
                    .padding(.bottom, 100) // Space for the save button
                }
            }
            .navigationTitle("Adjust Bankroll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .overlay(
                // Save button
                VStack {
                    Spacer()
                    
                    Button(action: saveBankrollAdjustment) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                                Text("Saving...")
                                    .font(.plusJakarta(.body, weight: .bold))
                                    .foregroundColor(.black)
                            } else {
                                Image(systemName: selectedOperation.icon)
                                    .font(.system(size: 16, weight: .bold))
                                Text("\(selectedOperation.rawValue) $\(Int(formattedAmount))")
                                    .font(.plusJakarta(.body, weight: .bold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
                    }
                    .disabled(!isValidAmount || isLoading)
                    .opacity(!isValidAmount || isLoading ? 0.6 : 1.0)
                    .buttonStyle(ScalePressButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveBankrollAdjustment() {
        guard isValidAmount else { return }
        
        isLoading = true
        
        let amount = selectedOperation == .add ? formattedAmount : -formattedAmount
        let note = noteText.isEmpty ? nil : noteText
        
        Task {
            do {
                try await bankrollStore.adjustBankroll(amount: amount, note: note)
                
                await MainActor.run {
                    // Add haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
} 