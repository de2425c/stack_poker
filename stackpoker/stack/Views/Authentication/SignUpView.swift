import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingEmailVerification = false
    @StateObject private var authService = AuthService()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Create Account")
                                .font(.custom("PlusJakartaSans-Bold", size: 32))
                                .foregroundColor(.white)
                                .padding(.top, 85)
                            
                            Text("Sign up to get started")
                                .font(.custom("PlusJakartaSans-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 4)
                            
                            // Registration Form
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
                                
                                GlassyInputField(icon: "lock.shield", title: "CONFIRM PASSWORD", labelColor: Color.white.opacity(0.6)) {
                                    SecureField("", text: $confirmPassword)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                }
                                
                                Button(action: signUp) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Create Account")
                                            .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .foregroundColor(.black)
                                .cornerRadius(12)
                                .disabled(isLoading)
                            }
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Close button
                    VStack {
                        HStack {
                            Button(action: { 
                                if !showingEmailVerification {
                                    dismiss()
                                }
                            }) {
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
                .ignoresSafeArea(.keyboard) // Ignore the keyboard safe area
            }
            .navigationBarHidden(true) // Hide the navigation bar since we have our own close button
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
                .font(.custom("PlusJakartaSans-Medium", size: 16))
        }
        .fullScreenCover(isPresented: $showingEmailVerification) {
            EmailVerificationView()
                .environmentObject(authViewModel)
        }
    }
    
    private func signUp() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            showingError = true
            return
        }
        
        // Validate password length
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters long"
            showingError = true
            return
        }
        
        // Validate email format (simple check)
        guard email.contains("@") && email.contains(".") else {
            errorMessage = "Please enter a valid email address"
            showingError = true
            return
        }
        
        isLoading = true
        Task {
            do {
                try await authService.signUpWithEmail(email: email, password: password)
                DispatchQueue.main.async {
                    showingEmailVerification = true
                    isLoading = false
                }
            } catch let error as AuthError {
                DispatchQueue.main.async {
                    // Check specifically for email already in use error
                    if case .emailInUse = error {
                        errorMessage = "This email is already registered. Please sign in or use a different email."
                    } else {
                        errorMessage = error.message
                    }
                    showingError = true
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
} 
