import SwiftUI

struct AddCustomGameView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var gameService: CustomGameService
    @State private var gameName = ""
    @State private var stakes = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Add Custom Game")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(white: 0.92))
                        .padding(.top, 12)
                    
                    VStack(spacing: 16) {
                        CustomInputField(
                            title: "Game Name",
                            systemImage: "building.2",
                            text: $gameName,
                            keyboardType: .default
                        )
                        
                        CustomInputField(
                            title: "Stakes",
                            systemImage: "dollarsign.circle",
                            text: $stakes,
                            keyboardType: .default
                        )
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(UIColor(red: 18/255, green: 19/255, blue: 22/255, alpha: 0.98)))
                    )
                    .padding(.horizontal, 8)
                    
                    Spacer()
                    
                    Button(action: addGame) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                        } else {
                            Text("Add Game")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: gameName.isEmpty || stakes.isEmpty || isLoading ? 0.5 : 1))
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.green.opacity(0.10), radius: 6, y: 1)
                    .disabled(gameName.isEmpty || stakes.isEmpty || isLoading)
                    .padding(.horizontal)
                    .padding(.bottom, 34)
                }
                .padding(.top, 8)
                .padding(.horizontal, 14)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func addGame() {
        guard !gameName.isEmpty && !stakes.isEmpty else { return }
        isLoading = true
        
        Task {
            do {
                try await gameService.addCustomGame(name: gameName, stakes: stakes)
                // Force a refresh of the games list
                await MainActor.run {
                    gameService.fetchCustomGames()
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
} 