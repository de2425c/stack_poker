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
    
    // Real-time validation states
    @State private var emailIsValid = false
    @State private var passwordIsValid = false
    @State private var passwordsMatch = false
    @State private var hasInteracted = false
    @State private var agreesToTerms = false
    @State private var showingLegalDocs = false
    
    // Computed property for form validity
    private var isFormValid: Bool {
        emailIsValid && passwordIsValid && passwordsMatch
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea(.all)
                    
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
                                // Email Field with real-time validation
                                GlassyInputField(
                                    icon: "envelope", 
                                    title: "EMAIL", 
                                    labelColor: emailValidationColor
                                ) {
                                    TextField("", text: $email)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .textContentType(.emailAddress)
                                        .onChange(of: email) { newValue in
                                            validateEmail(newValue)
                                            if !hasInteracted { hasInteracted = true }
                                        }
                                }
                                
                                // Password Field with real-time validation
                                GlassyInputField(
                                    icon: "lock", 
                                    title: "PASSWORD", 
                                    labelColor: passwordValidationColor
                                ) {
                                    SecureField("", text: $password)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .textContentType(.newPassword)
                                        .onChange(of: password) { newValue in
                                            validatePassword(newValue)
                                            validatePasswordMatch()
                                            if !hasInteracted { hasInteracted = true }
                                        }
                                }
                                
                                // Confirm Password Field with real-time validation
                                GlassyInputField(
                                    icon: "lock.shield", 
                                    title: "CONFIRM PASSWORD", 
                                    labelColor: confirmPasswordValidationColor
                                ) {
                                    SecureField("", text: $confirmPassword)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .textContentType(.newPassword)
                                        .onChange(of: confirmPassword) { newValue in
                                            validatePasswordMatch()
                                            if !hasInteracted { hasInteracted = true }
                                        }
                                }
                                
                                // Terms and Conditions
                                HStack(alignment: .center, spacing: 12) {
                                    Button(action: {
                                        withAnimation {
                                            agreesToTerms.toggle()
                                        }
                                    }) {
                                        Image(systemName: agreesToTerms ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 24))
                                            .foregroundColor(agreesToTerms ? Color.blue : .gray)
                                    }

                                    (
                                        Text("I agree to the ")
                                            .foregroundColor(.white.opacity(0.7))
                                        +
                                        Text("Terms & Conditions")
                                            .foregroundColor(.blue)
                                            .underline()
                                    )
                                    .font(.plusJakarta(.caption))
                                    .onTapGesture {
                                        showingLegalDocs = true
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                // Optimized Create Account Button
                                Button(action: {
                                    // Add haptic feedback for immediate response
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    signUp()
                                }) {
                                    ZStack {
                                        HStack {
                                            if isLoading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                    .scaleEffect(0.8)
                                                Text("Creating Account...")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            } else {
                                                Text("Create Account")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                                                    Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
                                                ]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .scaleEffect(isLoading ? 0.98 : 1.0)
                                        .animation(.easeInOut(duration: 0.1), value: isLoading)
                                )
                                .disabled(isLoading || (!isFormValid && hasInteracted) || !agreesToTerms)
                                .opacity(buttonOpacity)
                                .animation(.easeInOut(duration: 0.2), value: isFormValid)
                                .contentShape(Rectangle())
                            }
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 80) // HARDCODED: Ensure buttons are never blocked by bottom padding
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
                .ignoresSafeArea(.keyboard)
            }
            .navigationBarHidden(true)
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
        .sheet(isPresented: $showingLegalDocs) {
            LegalDocsView()
        }
    }
    
    // MARK: - Validation Methods
    private func validateEmail(_ email: String) {
        emailIsValid = email.contains("@") && email.contains(".") && email.count > 5
    }
    
    private func validatePassword(_ password: String) {
        passwordIsValid = password.count >= 6
    }
    
    private func validatePasswordMatch() {
        passwordsMatch = password == confirmPassword && !confirmPassword.isEmpty
    }
    
    // MARK: - Computed Properties for UI States
    private var emailValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return emailIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
    }
    
    private var passwordValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return passwordIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
    }
    
    private var confirmPasswordValidationColor: Color {
        if !hasInteracted || confirmPassword.isEmpty { return Color.white.opacity(0.6) }
        return passwordsMatch ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
    }
    
    private var buttonBackgroundColor: Color {
        if isLoading {
            return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8))
        }
        return isFormValid && agreesToTerms || !hasInteracted ? 
            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
            Color.gray.opacity(0.6)
    }
    
    private var buttonOpacity: Double {
        if isLoading { return 0.8 }
        return (isFormValid && agreesToTerms || !hasInteracted) ? 1.0 : 0.6
    }
    
    // MARK: - Sign Up Method
    private func signUp() {
        // Prevent double submission
        guard !isLoading else { return }
        
        // Final validation before submission
        guard isFormValid else {
            if !emailIsValid {
                errorMessage = "Please enter a valid email address"
            } else if !passwordIsValid {
                errorMessage = "Password must be at least 6 characters long"
            } else if !passwordsMatch {
                errorMessage = "Passwords don't match"
            }
            showingError = true
            return
        }

        guard agreesToTerms else {
            errorMessage = "Please agree to the Terms & Conditions to continue."
            showingError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                try await authService.signUpWithEmail(email: email, password: password)
                
                await MainActor.run {
                    // Add success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    showingEmailVerification = true
                    isLoading = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    // Add error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
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
                await MainActor.run {
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
                    errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
} 
