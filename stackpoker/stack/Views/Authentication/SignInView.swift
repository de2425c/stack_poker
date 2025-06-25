import SwiftUI
import FirebaseAuth

struct SignInView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var authService = AuthService()
    @State private var emailOrPhone = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSignUp = false
    @State private var showingPhoneVerification = false
    @State private var showingEmailVerification = false
    @State private var showingForgotPassword = false
    @State private var resetEmail = ""
    @State private var showingPasswordResetSuccess = false
    
    // Real-time validation states
    @State private var emailOrPhoneIsValid = false
    @State private var passwordIsValid = false
    @State private var hasInteracted = false
    @State private var isPhoneNumber = false
    @State private var isEmailAddress = false
    
    // Computed property for form validity
    private var isFormValid: Bool {
        if isPhoneNumber {
            return emailOrPhoneIsValid
        } else {
            return emailOrPhoneIsValid && passwordIsValid
        }
    }
    
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
                            
                            Text(isPhoneNumber ? "Enter your phone number" : "Enter your email and password")
                                .font(.custom("PlusJakartaSans-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 4)
                            
                            // Login Form
                            VStack(spacing: 16) {
                                // Email or Phone Field with smart detection
                                GlassyInputField(
                                    icon: isPhoneNumber ? "phone" : "envelope", 
                                    title: "EMAIL OR PHONE", 
                                    labelColor: emailOrPhoneValidationColor
                                ) {
                                    TextField("", text: $emailOrPhone)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .keyboardType(isPhoneNumber ? .phonePad : .emailAddress)
                                        .autocapitalization(.none)
                                        .textContentType(isPhoneNumber ? .telephoneNumber : .emailAddress)
                                        .onChange(of: emailOrPhone) { newValue in
                                            validateEmailOrPhone(newValue)
                                            if !hasInteracted { hasInteracted = true }
                                        }
                                }
                                
                                // Password Field - only show for email users
                                if isEmailAddress {
                                    GlassyInputField(
                                        icon: "lock", 
                                        title: "PASSWORD", 
                                        labelColor: passwordValidationColor
                                    ) {
                                        SecureField("", text: $password)
                                            .font(.plusJakarta(.body))
                                            .foregroundColor(.white)
                                            .textContentType(.password)
                                            .onChange(of: password) { newValue in
                                                validatePassword(newValue)
                                                if !hasInteracted { hasInteracted = true }
                                            }
                                    }
                                }
                                
                                // Sign In Button - changes based on input type
                                Button(action: {
                                    // Add haptic feedback for immediate response
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    
                                    if isPhoneNumber {
                                        sendPhoneVerification()
                                    } else {
                                        signInWithEmail()
                                    }
                                }) {
                                    ZStack {
                                        HStack {
                                            if isLoading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                    .scaleEffect(0.8)
                                                Text(isPhoneNumber ? "Sending Code..." : "Signing In...")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            } else {
                                                Text(isPhoneNumber ? "Send Verification Code" : "Sign In")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(buttonBackgroundColor)
                                        .scaleEffect(isLoading ? 0.98 : 1.0)
                                        .animation(.easeInOut(duration: 0.1), value: isLoading)
                                )
                                .disabled(isLoading || (!isFormValid && hasInteracted))
                                .opacity(buttonOpacity)
                                .animation(.easeInOut(duration: 0.2), value: isFormValid)
                                .contentShape(Rectangle())
                                
                                // Or divider
                                HStack {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 1)
                                    Text("OR")
                                        .font(.custom("PlusJakartaSans-Medium", size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 12)
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 1)
                                }
                                .padding(.top, 16)
                                
                                // Sign up button
                                Button(action: { showingSignUp = true }) {
                                    Text("Don\'t have an account? Sign up")
                                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                }
                                .padding(.top, 16)
                                .contentShape(Rectangle())
                                
                                // Forgot password button - shown at bottom for convenience
                                Button(action: { 
                                    resetEmail = isEmailAddress ? emailOrPhone : ""
                                    showingForgotPassword = true 
                                }) {
                                    Text("Forgot Password?")
                                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                }
                                .padding(.top, 20)
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
        .alert("Forgot Password", isPresented: $showingForgotPassword) {
            TextField("Email", text: $resetEmail)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            Button("Send Reset Email") {
                sendPasswordReset()
            }
            Button("Cancel", role: .cancel) {
                resetEmail = ""
            }
        } message: {
            Text("Enter your email address to receive a password reset link.")
                .font(.custom("PlusJakartaSans-Medium", size: 14))
        }
        .alert("Email Sent", isPresented: $showingPasswordResetSuccess) {
            Button("OK") {}
        } message: {
            Text("Password reset email has been sent. Please check your inbox and follow the instructions to reset your password.")
                .font(.custom("PlusJakartaSans-Medium", size: 14))
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
                .environmentObject(authViewModel)
        }
        .fullScreenCover(isPresented: $showingPhoneVerification) {
            PhoneVerificationView(phoneNumber: emailOrPhone, authService: authService)
                .environmentObject(authViewModel)
        }
        .fullScreenCover(isPresented: $showingEmailVerification) {
            EmailVerificationView()
                .environmentObject(authViewModel)
        }
        .onChange(of: authViewModel.appFlow) { newFlow in
            print("SignInView: App flow changed to: \(newFlow)")
            // Dismiss the SignInView when authentication is successful
            switch newFlow {
            case .main, .profileSetup, .emailVerification:
                print("SignInView: Dismissing because flow is: \(newFlow)")
                dismiss()
            default:
                break
            }
        }
    }
    
    // MARK: - Validation Methods
    private func validateEmailOrPhone(_ input: String) {
        // First determine if it's a phone number or email
        let digitsOnly = input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count >= 10 {
            // Likely a phone number
            isPhoneNumber = true
            isEmailAddress = false
            emailOrPhoneIsValid = digitsOnly.count >= 10
            // Format phone number as user types
            emailOrPhone = formatPhoneNumber(input)
        } else if input.contains("@") {
            // Likely an email
            isPhoneNumber = false
            isEmailAddress = true
            emailOrPhoneIsValid = input.contains("@") && input.contains(".") && input.count > 5
        } else {
            // Neither clear phone nor email yet
            isPhoneNumber = false
            isEmailAddress = false
            emailOrPhoneIsValid = false
        }
    }
    
    private func validatePassword(_ password: String) {
        passwordIsValid = password.count > 0 // For sign in, just check it's not empty
    }
    
    private func formatPhoneNumber(_ input: String) -> String {
        // Remove all non-numeric characters
        let digitsOnly = input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Limit to reasonable phone number length
        let limitedDigits = String(digitsOnly.prefix(11))
        
        // Only format when we have enough digits to make it worthwhile
        if limitedDigits.count >= 10 {
            let areaCode = String(limitedDigits.prefix(3))
            let prefix = String(limitedDigits.dropFirst(3).prefix(3))
            let suffix = String(limitedDigits.dropFirst(6))
            
            if limitedDigits.count == 10 {
                return "+1 (\(areaCode)) \(prefix)-\(suffix)"
            } else if limitedDigits.count == 11 && limitedDigits.hasPrefix("1") {
                let number = String(limitedDigits.dropFirst())
                let areaCode = String(number.prefix(3))
                let prefix = String(number.dropFirst(3).prefix(3))
                let suffix = String(number.dropFirst(6))
                return "+1 (\(areaCode)) \(prefix)-\(suffix)"
            }
        }
        
        // For partial numbers, add minimal formatting to guide user
        if limitedDigits.count >= 7 {
            let areaCode = String(limitedDigits.prefix(3))
            let prefix = String(limitedDigits.dropFirst(3).prefix(3))
            let suffix = String(limitedDigits.dropFirst(6))
            return "(\(areaCode)) \(prefix)-\(suffix)"
        } else if limitedDigits.count >= 4 {
            let areaCode = String(limitedDigits.prefix(3))
            let prefix = String(limitedDigits.dropFirst(3))
            return "(\(areaCode)) \(prefix)"
        } else if limitedDigits.count >= 1 {
            return limitedDigits
        }
        
        return ""
    }
    
    private func getCleanPhoneNumber(_ displayNumber: String) -> String {
        // Extract just the digits and format for Firebase (+1XXXXXXXXXX)
        let digitsOnly = displayNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count == 10 {
            return "+1\(digitsOnly)"
        } else if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+\(digitsOnly)"
        }
        
        return "+1\(digitsOnly)"
    }
    
    // MARK: - Computed Properties for UI States
    private var emailOrPhoneValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return emailOrPhoneIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
    }
    
    private var passwordValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return passwordIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
    }
    
    private var buttonBackgroundColor: Color {
        if isLoading {
            return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8))
        }
        return isFormValid || !hasInteracted ? 
            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
            Color.gray.opacity(0.6)
    }
    
    private var buttonOpacity: Double {
        if isLoading { return 0.8 }
        return (isFormValid || !hasInteracted) ? 1.0 : 0.6
    }
    
    // MARK: - Sign In Methods
    private func signInWithEmail() {
        // Prevent double submission
        guard !isLoading else { return }
        
        // Basic validation
        guard isFormValid else {
            if !emailOrPhoneIsValid {
                errorMessage = "Please enter a valid email address"
            } else if !passwordIsValid {
                errorMessage = "Please enter your password"
            }
            showingError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                try await authService.signInWithEmail(email: emailOrPhone, password: password)
                
                await MainActor.run {
                    // Add success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    isLoading = false
                    
                    // Don't dismiss immediately - let the auth state listener handle the flow
                    // The MainCoordinator will automatically switch to the appropriate view
                    // based on the authentication state
                }
            } catch let error as AuthError {
                await MainActor.run {
                    // Add error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
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
    
    private func sendPhoneVerification() {
        // Prevent double submission
        guard !isLoading else { return }
        
        // Basic validation
        guard isFormValid else {
            errorMessage = "Please enter a valid phone number"
            showingError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let cleanPhoneNumber = getCleanPhoneNumber(emailOrPhone)
                try await authService.sendPhoneVerificationCode(phoneNumber: cleanPhoneNumber)
                
                await MainActor.run {
                    // Add success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    showingPhoneVerification = true
                    isLoading = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    // Add error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
                    errorMessage = error.message
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
    
    private func sendPasswordReset() {
        isLoading = true
        Task {
            do {
                try await authService.sendPasswordResetEmail(email: resetEmail)
                
                await MainActor.run {
                    // Add success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    showingPasswordResetSuccess = true
                    resetEmail = ""
                    isLoading = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    // Add error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
                    errorMessage = error.message
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
} 
