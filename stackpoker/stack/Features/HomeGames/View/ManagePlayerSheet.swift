import SwiftUI
import FirebaseAuth
import Foundation
import FirebaseFirestore

// MARK: - ManagePlayerSheet
struct ManagePlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var homeGameService = HomeGameService()
    
    let player: HomeGame.Player
    let gameId: String
    let onComplete: () -> Void
    
    @State private var totalBuyIn: String = ""
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // Beautiful background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        playerInfoSection
                        currentValueSection
                        editSection
                        updateButtonSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(error ?? "An unknown error occurred")
        }
        .onAppear {
            setupInitialValues()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.white)
            .font(.system(size: 17))
            
            Spacer()
            
            Text("Manage Player")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Invisible button for spacing
            Button("") { }
                .foregroundColor(.clear)
                .disabled(true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
    
    // MARK: - Player Info Section
    private var playerInfoSection: some View {
        VStack(spacing: 20) {
            // Player avatar and name
            VStack(spacing: 12) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Text(String(player.displayName.first ?? "?").uppercased())
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                }
                
                Text(player.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Joined \(formatDateTime(player.joinedAt))")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Status badge
            HStack(spacing: 8) {
                Circle()
                    .fill(player.status == .active ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red)
                    .frame(width: 8, height: 8)
                
                Text(player.status == .active ? "Active Player" : "Cashed Out")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Current Value Section
    private var currentValueSection: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Text("CURRENT VALUES")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Spacer()
            }
            
            // Total Buy-In Display
            VStack(spacing: 12) {
                Text("Total Buy-In")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("$\(Int(player.totalBuyIn))")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.clear,
                                        Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
    }
    
    // MARK: - Edit Section
    private var editSection: some View {
        VStack(spacing: 24) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Text("EDIT BUY-IN")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Spacer()
            }
            
            // Buy-In Input using GlassyInputField
            GlassyInputField(
                icon: "dollarsign.circle.fill",
                title: "TOTAL BUY-IN",
                labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
            ) {
                HStack {
                    Text("$")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    
                    TextField("\(Int(player.totalBuyIn))", text: $totalBuyIn)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.vertical, 6)
            }
            
            // Helper text
            Text("Adjust the total amount this player has bought in for")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, -8)
        }
    }
    
    // MARK: - Update Button Section
    private var updateButtonSection: some View {
        Button(action: updatePlayer) {
            HStack(spacing: 12) {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                    
                    Text("Update Buy-In")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(hasChanges() ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.white.opacity(0.3))
                    .shadow(
                        color: hasChanges() ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.3) : Color.clear,
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            )
        }
        .disabled(!hasChanges() || isProcessing)
        .animation(.easeInOut(duration: 0.2), value: hasChanges())
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
    }
    
    // MARK: - Helper Methods
    private func setupInitialValues() {
        totalBuyIn = "\(Int(player.totalBuyIn))"
    }
    
    private func hasChanges() -> Bool {
        let newTotalBuyIn = parseAmount(totalBuyIn)
        return newTotalBuyIn != player.totalBuyIn && newTotalBuyIn > 0
    }
    
    private func parseAmount(_ text: String) -> Double {
        let cleanText = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return Double(cleanText) ?? 0
    }
    
    private func updatePlayer() {
        guard hasChanges() else { return }
        
        let newTotalBuyIn = parseAmount(totalBuyIn)
        
        // Validate values
        guard newTotalBuyIn > 0 else {
            error = "Please enter a valid buy-in amount"
            showError = true
            return
        }
        
        isProcessing = true
        
        Task {
            do {
                try await homeGameService.updatePlayerValues(
                    gameId: gameId,
                    playerId: player.id,
                    newCurrentStack: player.currentStack, // Keep current stack unchanged
                    newTotalBuyIn: newTotalBuyIn
                )
                
                await MainActor.run {
                    isProcessing = false
                    onComplete()
                    dismiss()
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
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}



