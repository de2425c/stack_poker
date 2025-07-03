import SwiftUI

// MARK: - Game Invites Components

struct GameInvitesBar: View {
    let invites: [HomeGame.GameInvite]
    let onTap: (HomeGame.GameInvite) -> Void
    let isFirstBar: Bool // Whether this is the first bar (no other bars above it)
    
    private var firstInvite: HomeGame.GameInvite? {
        invites.first
    }
    
    var body: some View {
        if let invite = firstInvite {
            Button(action: {
                print("🔥 GameInvitesBar button tapped!")
                onTap(invite)
            }) {
                HStack(spacing: 16) {
                    // Invite icon
                    Circle()
                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Game Invite")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            if invites.count > 1 {
                                Text("+\(invites.count - 1) more")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.2))
                                    )
                            }
                        }
                        
                        Text("\(invite.hostName) invited you to \"\(invite.gameTitle)\"")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.top, isFirstBar ? (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 0 : 0)
                .background(
                    Color(UIColor(red: 28/255, green: 30/255, blue: 34/255, alpha: 0.95))
                        .ignoresSafeArea(edges: isFirstBar ? .top : [])
                        .overlay(
                            Rectangle()
                                .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .frame(height: 1),
                            alignment: .bottom
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onTapGesture {
                print("🔥 FALLBACK: GameInvitesBar tapped via onTapGesture!")
                onTap(invite)
            }
        }
    }
}

// MARK: - New Floating Invite Popup (Replaces the problematic sheet)

struct FloatingInvitePopup: View {
    let invite: HomeGame.GameInvite
    let onAccept: (Double) -> Void
    let onDecline: () -> Void
    let onDismiss: () -> Void
    
    @State private var buyInAmount = ""
    @State private var isProcessing = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showPopup = false
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showPopup = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            
            // Popup content
            VStack(spacing: 0) {
                // Header with game info
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    
                    VStack(spacing: 8) {
                        Text("Game Invite")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(invite.gameTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("from \(invite.hostName)")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                        
                        if let message = invite.message, !message.isEmpty {
                            Text("\"\(message)\"")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .italic()
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                // Buy-in input section
                VStack(spacing: 16) {
                    Text("Enter your buy-in amount")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 12) {
                        Text("$")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        TextField("100", text: $buyInAmount)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor(red: 45/255, green: 47/255, blue: 52/255, alpha: 1.0)))
                            )
                    }
                    .frame(maxWidth: 200)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                
                // Action buttons
                VStack(spacing: 12) {
                    // Accept button
                    Button(action: handleAccept) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            }
                            Text(isProcessing ? "Joining..." : "Accept & Join")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(buyInAmount.isEmpty || isProcessing ? 
                                      Color.gray.opacity(0.5) : 
                                      Color(red: 123/255, green: 255/255, blue: 99/255))
                        )
                    }
                    .disabled(buyInAmount.isEmpty || isProcessing)
                    
                    // Decline button
                    Button(action: handleDecline) {
                        Text("Decline")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .disabled(isProcessing)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.98)))
            )
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(showPopup ? 1.0 : 0.7)
            .opacity(showPopup ? 1.0 : 0.0)
        }
        .onAppear {
            print("🚀 FloatingInvitePopup appeared for invite: \(invite.gameTitle)")
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showPopup = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleAccept() {
        guard let amount = Double(buyInAmount), amount > 0 else {
            errorMessage = "Please enter a valid amount"
            showError = true
            return
        }
        
        isProcessing = true
        
        // Animate out and call completion
        withAnimation(.easeInOut(duration: 0.3)) {
            showPopup = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAccept(amount)
        }
    }
    
    private func handleDecline() {
        isProcessing = true
        
        // Animate out and call completion
        withAnimation(.easeInOut(duration: 0.3)) {
            showPopup = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDecline()
        }
    }
}