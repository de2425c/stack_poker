import SwiftUI
import FirebaseAuth

struct SignInView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var authService = AuthService()
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSignUp = false
    @State private var showingEmailVerification = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign In")
                                .font(.custom("PlusJakartaSans-Bold", size: 32))
                                .foregroundColor(.white)
                                .padding(.top, 85)
                            
                            Text("Enter your email and password")
                                .font(.custom("PlusJakartaSans-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 4)
                            
                            // Login Form
                            VStack(spacing: 16) {
                                GlassyInputField(icon: "envelope", title: "EMAIL", labelColor: Color.white.opacity(0.6)) {
                                    TextField("", text: $email)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                }
                                
                                GlassyInputField(icon: "lock", title: "PASSWORD", labelColor: Color.white.opacity(0.6)) {
                                    SecureField("", text: $password)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                }
                                
                                Button(action: signIn) {
                                    ZStack {
                                        Text("Sign In")
                                            .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                            .foregroundColor(.black)
                                            .opacity(isLoading ? 0 : 1)

                                        if isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                .scaleEffect(0.8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                }
                                .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .cornerRadius(12)
                                .disabled(isLoading)
                                .contentShape(Rectangle())
                                
                                // Sign up button
                                Button(action: { showingSignUp = true }) {
                                    Text("Don\'t have an account? Sign up")
                                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                }
                                .padding(.top, 8)
                                .contentShape(Rectangle())
                            }
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Close button
                    VStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            .padding(.leading, 16)
                            .padding(.top, 25)
                            
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationBarHidden(true)
        }
        .alert("Error", isPresented: $showingError) {
            if errorMessage == AuthError.emailNotVerified.message {
                Button("Verify Now") {
                    showingEmailVerification = true
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: {
            Text(errorMessage)
                .font(.custom("PlusJakartaSans-Medium", size: 16))
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
                .environmentObject(authViewModel)
        }
        .fullScreenCover(isPresented: $showingEmailVerification) {
            EmailVerificationView()
                .environmentObject(authViewModel)
        }
    }
    
    private func signIn() {
        isLoading = true
        Task {
            do {
                try await authService.signInWithEmail(email: email, password: password)
                DispatchQueue.main.async {
                    // The AuthViewModel listener will detect the sign-in and update the UI.
                    dismiss()
                }
            } catch let error as AuthError {
                DispatchQueue.main.async {
                    errorMessage = error.message
                    showingError = true
                    isLoading = false
                    
                    // If email is not verified, we'll show a special alert with an option to verify
                    if case .emailNotVerified = error {
                        // The alert will have a "Verify Now" button that will trigger showingEmailVerification
                    }
                }
            }
        }
    }
} 
