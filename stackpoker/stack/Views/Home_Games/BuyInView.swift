import SwiftUI
import FirebaseAuth
import PhotosUI // Keep if used elsewhere in the file
import Combine // Keep if used elsewhere in the file
import Foundation // Keep if used elsewhere in the file
import FirebaseFirestore // Add this import

// BuyIn view to request joining a game
struct BuyInView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let gameId: String
    let onComplete: () -> Void
    
    @State private var buyInAmount: String = ""
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showError = false
        
        @StateObject private var homeGameService = HomeGameService()
        
        private var isHost: Bool {
            guard let game = game else { return false }
            return Auth.auth().currentUser?.uid == game.creatorId
        }
        
        @State private var game: HomeGame?
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Add top spacing for navigation bar clearance
                    Color.clear.frame(height: 60)
                    
                    // Amount input using GlassyInputField
                    GlassyInputField(
                        icon: "dollarsign.circle.fill",
                        title: "BUY-IN AMOUNT",
                        labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
                    ) {
                        HStack {
                            Text("$")
                                .foregroundColor(.white)
                                .font(.system(size: 17))
                            
                            TextField("", text: $buyInAmount)
                                .placeholder(when: buyInAmount.isEmpty) {
                                    Text("Enter amount").foregroundColor(.gray.opacity(0.7))
                                }
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .keyboardType(.numberPad)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Text("Your buy-in request will be sent to the game creator for approval.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    // Submit button with bottom padding
                    Button(action: submitBuyIn) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .frame(width: 20, height: 20)
                                    .padding(.horizontal, 10)
                            } else {
                                Text("Submit Request")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 54)
                        .background(
                            !isValidAmount() || isProcessing
                                ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                                : Color(red: 123/255, green: 255/255, blue: 99/255)
                        )
                        .cornerRadius(16)
                    }
                    .disabled(!isValidAmount() || isProcessing)
                    .padding(.bottom, 60) // Added more bottom padding
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .navigationBarTitle("Buy In", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .foregroundColor(.white)
                }
            )
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(error ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                fetchGame()
            }
            // Add tap to dismiss keyboard
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            // Fix keyboard movement issues
            .ignoresSafeArea(.keyboard)
        }
    }
    
    private func isValidAmount() -> Bool {
        guard let amount = Double(buyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
              amount > 0 else {
            return false
        }
        return true
    }
    
    private func submitBuyIn() {
        guard isValidAmount() else { return }
        guard let amount = Double(buyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        
        isProcessing = true
        
        Task {
            do {
                    // Check if user is host to use direct buy-in
                    if isHost {
                        try await homeGameService.hostBuyIn(gameId: gameId, amount: amount)
                    } else {
                try await homeGameService.requestBuyIn(gameId: gameId, amount: amount)
                    }
                
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
        
        // Add a function to fetch the game to check if user is host
        private func fetchGame() {
            Task {
                do {
                    self.game = try await homeGameService.fetchHomeGame(gameId: gameId)
                } catch {

            }
        }
    }
}