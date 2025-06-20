import SwiftUI

struct BankrollChallengeSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var challengeService: ChallengeService
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject var userService: UserService
    @StateObject private var bankrollStore: BankrollStore
    
    let userId: String
    
    @State private var targetBankroll = ""
    @State private var challengeTitle = ""
    @State private var hasDeadline = false
    @State private var deadlineAmount = "30"
    @State private var deadlineUnit: DeadlineUnit = .days
    @State private var isPublic = true
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isTargetBankrollFocused: Bool
    @FocusState private var isDeadlineAmountFocused: Bool
    
    init(challengeService: ChallengeService, sessionStore: SessionStore, userId: String) {
        self.challengeService = challengeService
        self.sessionStore = sessionStore
        self.userId = userId
        self._bankrollStore = StateObject(wrappedValue: BankrollStore(userId: userId))
    }
    
    enum DeadlineUnit: String, CaseIterable {
        case days = "days"
        case weeks = "weeks"
        case months = "months"
        
        var displayName: String {
            return self.rawValue
        }
    }
    
    private var currentBankroll: Double {
        let sessionProfit = sessionStore.sessions.reduce(0) { $0 + $1.profit }
        return sessionProfit + bankrollStore.bankrollSummary.currentTotal
    }
    
    private var targetBankrollValue: Double {
        return Double(targetBankroll) ?? 0
    }
    
    private var isValidInput: Bool {
        return !challengeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               targetBankrollValue > 0 &&
               targetBankrollValue > currentBankroll
    }
    
    private var calculatedDeadline: Date {
        let amount = Int(deadlineAmount) ?? 30
        let calendar = Calendar.current
        
        switch deadlineUnit {
        case .days:
            return calendar.date(byAdding: .day, value: amount, to: Date()) ?? Date()
        case .weeks:
            return calendar.date(byAdding: .weekOfYear, value: amount, to: Date()) ?? Date()
        case .months:
            return calendar.date(byAdding: .month, value: amount, to: Date()) ?? Date()
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                    }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.green)
                                
                                Text("Bankroll Challenge")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            
                            Text("Set a bankroll target and track your progress as you play sessions.")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Current Bankroll Display
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Bankroll")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text("$\(Int(currentBankroll).formattedWithCommas)")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(currentBankroll >= 0 ? .green : .red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        
                        // Challenge Setup Form
                        VStack(spacing: 16) {
                            // Challenge Title
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Challenge Title")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                TextField("e.g., Hit $10,000 bankroll", text: $challengeTitle)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black.opacity(0.3))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            // Target Bankroll
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Target Bankroll")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                HStack {
                                    Text("$")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    TextField("10000", text: $targetBankroll)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .keyboardType(.numberPad)
                                        .focused($isTargetBankrollFocused)
                                        .toolbar {
                                            ToolbarItemGroup(placement: .keyboard) {
                                                Spacer()
                                                Button("Done") {
                                                    isTargetBankrollFocused = false
                                                }
                                                .foregroundColor(.blue)
                                            }
                                        }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(targetBankrollValue > currentBankroll && targetBankrollValue > 0 ? 
                                                       Color.green.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                
                                if targetBankrollValue > 0 {
                                    Text("Target: \(targetBankrollValue > currentBankroll ? "+" : "")\(Int(targetBankrollValue - currentBankroll).formattedWithCommas) to reach goal")
                                        .font(.system(size: 14))
                                        .foregroundColor(targetBankrollValue > currentBankroll ? .green : .orange)
                                }
                            }
                            
                            // Deadline Toggle
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Set Deadline")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: $hasDeadline)
                                        .labelsHidden()
                                        .tint(.green)
                                }
                                
                                if hasDeadline {
                                    VStack(spacing: 16) {
                                        // Amount and Unit Input in one line
                                        HStack(spacing: 12) {
                                            TextField("30", text: $deadlineAmount)
                                                .font(.system(size: 16))
                                                .foregroundColor(.white)
                                                .keyboardType(.numberPad)
                                                .focused($isDeadlineAmountFocused)
                                                .frame(width: 60)
                                                .padding(12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.black.opacity(0.3))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                                        )
                                                )
                                                .toolbar {
                                                    ToolbarItemGroup(placement: .keyboard) {
                                                        Spacer()
                                                        Button("Done") {
                                                            isDeadlineAmountFocused = false
                                                        }
                                                        .foregroundColor(.blue)
                                                    }
                                                }
                                            
                                            Picker("", selection: $deadlineUnit) {
                                                ForEach(DeadlineUnit.allCases, id: \.self) { unit in
                                                    Text(unit.displayName)
                                                        .tag(unit)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            Spacer()
                                        }
                                        
                                        deadlineDisplayView
                                        
                                        quickPresetsView
                                    }
                                }
                            }
                            
                            // Public Toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Make Public")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("Others can see your challenge on your profile")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isPublic)
                                    .labelsHidden()
                                    .tint(.green)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        
                        // Create Button
                        Button(action: createChallenge) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                
                                Text(isCreating ? "Creating..." : "Create Challenge")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isValidInput ? Color.green : Color.gray.opacity(0.3))
                            )
                        }
                        .disabled(!isValidInput || isCreating)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onTapGesture {
                 hideKeyboard()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func createChallenge() {
        guard isValidInput else { return }
        
        isCreating = true
        
        let challenge = Challenge(
            userId: userId,
            type: .bankroll,
            title: challengeTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: "Reach $\(Int(targetBankrollValue).formattedWithCommas) bankroll",
            targetValue: targetBankrollValue,
            currentValue: currentBankroll,
            endDate: hasDeadline ? calculatedDeadline : nil,
            isPublic: isPublic,
            startingBankroll: currentBankroll
        )
        
        Task {
            do {
                try await challengeService.createChallenge(challenge)
                
                await MainActor.run {
                    isCreating = false
                    // Dismiss this view immediately after creating challenge
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func quickPresetButton(_ title: String, amount: Int, unit: DeadlineUnit) -> some View {
        Button(action: {
            deadlineAmount = String(amount)
            deadlineUnit = unit
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var deadlineDisplayView: some View {
        let daysFromToday = Calendar.current.dateComponents([.day], from: Date(), to: calculatedDeadline).day ?? 0
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text("\(daysFromToday) days from today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
                Spacer()
            }
            
            Text("Deadline: \(dateFormatter.string(from: calculatedDeadline))")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }
    
    private var quickPresetsView: some View {
        VStack(spacing: 8) {
            Text("Quick Presets")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                quickPresetButton("1 Week", amount: 1, unit: .weeks)
                quickPresetButton("1 Month", amount: 1, unit: .months)
                quickPresetButton("3 Months", amount: 3, unit: .months)
            }
            
            HStack(spacing: 8) {
                quickPresetButton("6 Months", amount: 6, unit: .months)
                quickPresetButton("1 Year", amount: 12, unit: .months)
                Spacer()
            }
        }
    }
} 