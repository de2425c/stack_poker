import SwiftUI
import FirebaseAuth
import PhotosUI // Keep if used elsewhere in the file
import Combine // Keep if used elsewhere in the file
import Foundation // Keep if used elsewhere in the file
import FirebaseFirestore // Add this import

// MARK: - ManagePlayerSheet
struct ManagePlayerSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var homeGameService = HomeGameService()
    
    let player: HomeGame.Player
    let gameId: String
    let onComplete: () -> Void
    
    @State private var currentStack: String = ""
    @State private var totalBuyIn: String = ""
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Top spacer for navigation bar clearance
                        Color.clear.frame(height: 20)
                        
                        // Player info header
                        VStack(spacing: 16) {
                            Text("Manage Player")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            VStack(spacing: 8) {
                                Text(player.displayName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Joined \(formatTime(player.joinedAt))")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        // Current values display
                        VStack(spacing: 16) {
                            Text("CURRENT VALUES")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            
                            HStack(spacing: 20) {
                                VStack(spacing: 8) {
                                    Text("$\(Int(player.currentStack))")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Current Stack")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack(spacing: 8) {
                                    Text("$\(Int(player.totalBuyIn))")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Total Buy-In")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack(spacing: 8) {
                                    let profit = player.currentStack - player.totalBuyIn
                                    Text("\(profit >= 0 ? "+" : "")\(Int(profit))")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(profit >= 0 ? .green : .red)
                                    
                                    Text("Profit/Loss")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor(red: 35/255, green: 37/255, blue: 42/255, alpha: 1.0)))
                        )
                        .padding(.horizontal, 16)
                        
                        // Edit fields
                        VStack(spacing: 16) {
                            Text("EDIT VALUES")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            
                            // Current Stack input
                            GlassyInputField(
                                icon: "creditcard.fill",
                                title: "CURRENT STACK",
                                labelColor: .white.opacity(0.8)
                            ) {
                                TextField("", text: $currentStack)
                                    .placeholders(when: currentStack.isEmpty) {
                                        Text("$\(Int(player.currentStack))").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                            }
                            
                            // Total Buy-In input
                            GlassyInputField(
                                icon: "dollarsign.circle.fill",
                                title: "TOTAL BUY-IN",
                                labelColor: .white.opacity(0.8)
                            ) {
                                TextField("", text: $totalBuyIn)
                                    .placeholders(when: totalBuyIn.isEmpty) {
                                        Text("$\(Int(player.totalBuyIn))").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Update button
                        Button(action: updatePlayer) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Update Player")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(hasChanges() && !isProcessing ? 
                                          Color.white.opacity(0.1) : 
                                          Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .disabled(!hasChanges() || isProcessing)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .foregroundColor(.white)
                },
                trailing: EmptyView()
            )
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(error ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                // Initialize with current values
                currentStack = "\(Int(player.currentStack))"
                totalBuyIn = "\(Int(player.totalBuyIn))"
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    private func hasChanges() -> Bool {
        let newCurrentStack = Double(currentStack.replacingOccurrences(of: "$", with: "")) ?? player.currentStack
        let newTotalBuyIn = Double(totalBuyIn.replacingOccurrences(of: "$", with: "")) ?? player.totalBuyIn
        
        return newCurrentStack != player.currentStack || newTotalBuyIn != player.totalBuyIn
    }
    
    private func updatePlayer() {
        guard hasChanges() else { return }
        
        let newCurrentStack = Double(currentStack.replacingOccurrences(of: "$", with: "")) ?? player.currentStack
        let newTotalBuyIn = Double(totalBuyIn.replacingOccurrences(of: "$", with: "")) ?? player.totalBuyIn
        
        isProcessing = true
        
        Task {
            do {
                try await homeGameService.updatePlayerValues(
                    gameId: gameId,
                    playerId: player.id,
                    newCurrentStack: newCurrentStack,
                    newTotalBuyIn: newTotalBuyIn
                )
                
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}



