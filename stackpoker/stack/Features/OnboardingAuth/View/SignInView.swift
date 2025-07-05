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
    @State private var validationTimer: Timer?
    
    // Country picker states
    @State private var selectedCountry = CountryCode.defaultCountry
    @State private var showingCountryPicker = false
    
    // Focus state for keyboard management
    @FocusState private var isInputFocused: Bool
    
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
                                    if isPhoneNumber {
                                        HStack(spacing: 12) {
                                            // Country picker button
                                            Button(action: { showingCountryPicker = true }) {
                                                HStack(spacing: 4) {
                                                    Text(selectedCountry.flag)
                                                        .font(.system(size: 20))
                                                    Text(selectedCountry.dialCode)
                                                        .font(.plusJakarta(.body))
                                                        .foregroundColor(.white.opacity(0.7))
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.white.opacity(0.5))
                                                }
                                            }
                                            
                                            TextField("", text: $emailOrPhone)
                                                .font(.plusJakarta(.body))
                                                .foregroundColor(.white)
                                                .keyboardType(.phonePad)
                                                .textContentType(.telephoneNumber)
                                                .focused($isInputFocused)
                                                .onChange(of: emailOrPhone) { newValue in
                                                    validateEmailOrPhone(newValue)
                                                    if !hasInteracted { hasInteracted = true }
                                                }
                                                .toolbar {
                                                    ToolbarItemGroup(placement: .keyboard) {
                                                        Spacer()
                                                        Button("Done") {
                                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                                        }
                                                        .foregroundColor(.blue)
                                                        .fontWeight(.medium)
                                                    }
                                                }
                                        }
                                    } else {
                                        TextField("", text: $emailOrPhone)
                                            .font(.plusJakarta(.body))
                                            .foregroundColor(.white)
                                            .keyboardType(.emailAddress)
                                            .autocapitalization(.none)
                                            .textContentType(.emailAddress)
                                            .focused($isInputFocused)
                                            .onChange(of: emailOrPhone) { newValue in
                                                validateEmailOrPhone(newValue)
                                                if !hasInteracted { hasInteracted = true }
                                            }
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
                                
                                // Info text for phone users about CAPTCHA
                                if isPhoneNumber {
                                    Text("You may need to complete a CAPTCHA verification for security.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 4)
                                        .padding(.top, 8)
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
                                                    .foregroundColor(.white)
                                            } else {
                                                Text(isPhoneNumber ? "Send Verification Code" : "Sign In")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
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
        .sheet(isPresented: $showingCountryPicker) {
            SignInCountryPickerView(selectedCountry: $selectedCountry, showingCountryPicker: $showingCountryPicker)
        }
        .onAppear {
            // Auto-focus the input field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Validation Methods
    private func validateEmailOrPhone(_ input: String) {
        // Cancel any existing timer
        validationTimer?.invalidate()
        
        // If input contains @, it's definitely an email
        if input.contains("@") {
            isPhoneNumber = false
            isEmailAddress = true
            emailOrPhoneIsValid = input.contains("@") && input.contains(".") && input.count > 5
            return
        }
        
        // For inputs without @, add a delay before determining if it's a phone number
        validationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            let digitsOnly = input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            let digitRatio = digitsOnly.count > 0 ? Double(digitsOnly.count) / Double(input.count) : 0
            
            // Only consider it a phone number if it's mostly digits (80%+) and has at least 3 digits
            if digitsOnly.count >= 3 && digitRatio >= 0.8 {
                // Likely a phone number
                self.isPhoneNumber = true
                self.isEmailAddress = false
                let minLength = self.getMinLengthForCountry(self.selectedCountry.code)
                self.emailOrPhoneIsValid = digitsOnly.count >= minLength
                // Format phone number as user types
                self.emailOrPhone = self.formatPhoneNumber(input)
            } else {
                // Not enough evidence to be a phone number
                self.isPhoneNumber = false
                self.isEmailAddress = false
                self.emailOrPhoneIsValid = false
            }
        }
    }
    
    private func validatePassword(_ password: String) {
        passwordIsValid = password.count > 0 // For sign in, just check it's not empty
    }
    
    private func formatPhoneNumber(_ input: String) -> String {
        // Remove all non-numeric characters
        let digitsOnly = input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Limit to max length for the country
        let maxLength = getMaxLengthForCountry(selectedCountry.code)
        let limitedDigits = String(digitsOnly.prefix(maxLength))
        
        // Apply country-specific formatting
        switch selectedCountry.code {
        case "US", "CA":
            return formatUSPhoneNumber(limitedDigits)
        case "GB":
            return formatUKPhoneNumber(limitedDigits)
        case "FR":
            return formatFrenchPhoneNumber(limitedDigits)
        case "DE":
            return formatGermanPhoneNumber(limitedDigits)
        case "JP":
            return formatJapanesePhoneNumber(limitedDigits)
        case "AU":
            return formatAustralianPhoneNumber(limitedDigits)
        default:
            // Generic formatting for other countries
            return formatGenericPhoneNumber(limitedDigits)
        }
    }
    
    // Country-specific formatting methods
    private func formatUSPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
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
    
    private func formatUKPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 7 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4).prefix(3))
            let third = String(limitedDigits.dropFirst(7))
            return "\(first) \(second) \(third)"
        } else if limitedDigits.count >= 4 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4))
            return "\(first) \(second)"
        }
        return limitedDigits
    }
    
    private func formatFrenchPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 8 {
            let parts = stride(from: 0, to: limitedDigits.count, by: 2).map { i in
                let start = limitedDigits.index(limitedDigits.startIndex, offsetBy: i)
                let end = limitedDigits.index(start, offsetBy: min(2, limitedDigits.count - i))
                return String(limitedDigits[start..<end])
            }
            return parts.joined(separator: " ")
        }
        return limitedDigits
    }
    
    private func formatGermanPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 6 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3).prefix(3))
            let third = String(limitedDigits.dropFirst(6))
            return "\(first) \(second) \(third)"
        } else if limitedDigits.count >= 3 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3))
            return "\(first) \(second)"
        }
        return limitedDigits
    }
    
    private func formatJapanesePhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 7 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3).prefix(4))
            let third = String(limitedDigits.dropFirst(7))
            return "\(first)-\(second)-\(third)"
        } else if limitedDigits.count >= 3 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3))
            return "\(first)-\(second)"
        }
        return limitedDigits
    }
    
    private func formatAustralianPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 8 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4).prefix(3))
            let third = String(limitedDigits.dropFirst(7))
            return "\(first) \(second) \(third)"
        } else if limitedDigits.count >= 4 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4))
            return "\(first) \(second)"
        }
        return limitedDigits
    }
    
    private func formatGenericPhoneNumber(_ digits: String) -> String {
        // Generic formatting - just return the digits with spaces every 3-4 characters
        let limitedDigits = digits
        
        if limitedDigits.count > 4 {
            let groups = stride(from: 0, to: limitedDigits.count, by: 3).map { i in
                let start = limitedDigits.index(limitedDigits.startIndex, offsetBy: i)
                let end = limitedDigits.index(start, offsetBy: min(3, limitedDigits.count - i))
                return String(limitedDigits[start..<end])
            }
            return groups.joined(separator: " ")
        }
        return limitedDigits
    }
    
    private func getCleanPhoneNumber(_ displayNumber: String) -> String {
        // Extract just the digits and format for Firebase
        let digitsOnly = displayNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return selectedCountry.dialCode + digitsOnly
    }
    
    // Helper methods for country phone validation
    private func getMinLengthForCountry(_ countryCode: String) -> Int {
        switch countryCode {
        case "US", "CA": return 10
        case "GB": return 10
        case "FR": return 9
        case "DE": return 10
        case "JP": return 10
        case "AU": return 9
        case "IT", "ES": return 9
        case "NL", "BE": return 9
        case "CH": return 9
        case "AT": return 10
        case "SE", "NO", "DK": return 8
        case "PL": return 9
        case "RU": return 10
        case "TR": return 10
        case "IL": return 9
        case "BR": return 10
        case "MX": return 10
        case "AR": return 10
        case "CL": return 9
        case "CO": return 10
        case "PE": return 9
        case "IN": return 10
        case "CN": return 11
        case "KR": return 10
        case "TH": return 9
        case "VN": return 9
        case "SG": return 8
        case "MY": return 9
        case "ID": return 10
        case "PH": return 10
        case "NZ": return 9
        case "ZA": return 9
        case "EG": return 10
        case "NG": return 10
        case "KE": return 9
        default: return 8
        }
    }
    
    private func getMaxLengthForCountry(_ countryCode: String) -> Int {
        switch countryCode {
        case "US", "CA": return 10
        case "GB": return 11
        case "FR": return 10
        case "DE": return 12
        case "JP": return 11
        case "AU": return 10
        case "IT": return 10
        case "ES": return 9
        case "NL", "BE": return 9
        case "CH": return 10
        case "AT": return 13
        case "SE": return 10
        case "NO", "DK": return 8
        case "PL": return 9
        case "RU": return 10
        case "TR": return 10
        case "IL": return 10
        case "BR": return 11
        case "MX": return 10
        case "AR": return 11
        case "CL": return 9
        case "CO": return 10
        case "PE": return 9
        case "IN": return 10
        case "CN": return 11
        case "KR": return 11
        case "TH": return 10
        case "VN": return 11
        case "SG": return 8
        case "MY": return 11
        case "ID": return 13
        case "PH": return 10
        case "NZ": return 10
        case "ZA": return 10
        case "EG": return 10
        case "NG": return 11
        case "KE": return 10
        default: return 15
        }
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
    
    private var buttonBackgroundColor: LinearGradient {
        if !hasInteracted || !isFormValid {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.6)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        if isLoading {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.8),
                    Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.8)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
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

// MARK: - Country Picker View
struct SignInCountryPickerView: View {
    @Binding var selectedCountry: CountryCode
    @Binding var showingCountryPicker: Bool
    @State private var searchText = ""
    
    private var filteredCountries: [CountryCode] {
        if searchText.isEmpty {
            return CountryCode.allCountries
        } else {
            return CountryCode.allCountries.filter { country in
                country.name.localizedCaseInsensitiveContains(searchText) ||
                country.dialCode.contains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List(filteredCountries, id: \.code) { country in
                Button(action: {
                    selectedCountry = country
                    showingCountryPicker = false
                }) {
                    HStack {
                        Text(country.flag)
                            .font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.name)
                                .font(.custom("PlusJakartaSans-Medium", size: 16))
                                .foregroundColor(.primary)
                            Text(country.dialCode)
                                .font(.custom("PlusJakartaSans-Regular", size: 14))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedCountry.code == country.code {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(PlainListStyle())
            .searchable(text: $searchText, prompt: "Search countries")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingCountryPicker = false
                    }
                }
            }
        }
    }
} 
