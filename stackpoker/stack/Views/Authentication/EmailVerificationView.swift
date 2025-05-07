import SwiftUI
import FirebaseAuth

struct EmailVerificationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var authService = AuthService()
    
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingProfileSetup = false
    @State private var resendDisabled = false
    @State private var resendCountdown = 30
    @State private var timer: Timer?
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                
                VStack(spacing: 32) {
                    // Email verification icon
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 80))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .padding(.top, 50)
                    
                    VStack(spacing: 16) {
                        Text("Verify Your Email")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("We've sent a verification link to\n\(Auth.auth().currentUser?.email ?? "your email")")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Text("Please check your inbox and verify your email before continuing.")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    
                    // Action buttons
                    VStack(spacing: 16) {
                        Button(action: checkVerification) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Text("I've Verified My Email")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .disabled(isLoading)
                        
                        Button(action: resendVerification) {
                            if resendDisabled {
                                Text("Resend Email in \(resendCountdown)s")
                                    .font(.system(size: 17, weight: .semibold))
                            } else {
                                Text("Resend Verification Email")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(resendDisabled ? .gray : .white)
                        .cornerRadius(12)
                        .disabled(resendDisabled || isLoading)
                        
                        Button(action: signOut) {
                            Text("Cancel")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.top, 32)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showingProfileSetup) {
            ProfileSetupView(isNewUser: true)
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func checkVerification() {
        isLoading = true
        
        Task {
            do {
                let isVerified = try await authService.reloadUser()
                
                DispatchQueue.main.async {
                    if isVerified {
                        showingProfileSetup = true
                    } else {
                        errorMessage = "Your email is not verified yet. Please check your email and click the verification link."
                        showingError = true
                        isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = (error as? AuthError)?.message ?? "Failed to check verification status"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func resendVerification() {
        Task {
            do {
                try await authService.sendEmailVerification()
                
                DispatchQueue.main.async {
                    // Start the countdown timer for resend button
                    startResendCountdown()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = (error as? AuthError)?.message ?? "Failed to resend verification email"
                    showingError = true
                }
            }
        }
    }
    
    private func startResendCountdown() {
        resendDisabled = true
        resendCountdown = 30
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                resendDisabled = false
                timer?.invalidate()
            }
        }
    }
    
    private func signOut() {
        do {
            try authService.signOut()
            dismiss()
        } catch {
            errorMessage = (error as? AuthError)?.message ?? "Failed to sign out"
            showingError = true
        }
    }
} 