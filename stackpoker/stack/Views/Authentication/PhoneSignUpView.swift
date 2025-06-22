import SwiftUI
import FirebaseAuth

struct PhoneSignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var phoneNumber = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingPhoneVerification = false
    @StateObject private var authService = AuthService()
    
    // Real-time validation states
    @State private var phoneIsValid = false
    @State private var hasInteracted = false
    
    // Computed property for form validity
    private var isFormValid: Bool {
        phoneIsValid
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign Up with Phone")
                                .font(.custom("PlusJakartaSans-Bold", size: 32))
                                .foregroundColor(.white)
                                .padding(.top, 85)
                            
                            Text("Enter your phone number to get started")
                                .font(.custom("PlusJakartaSans-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 4)
                            
                            // Phone Number Registration Form
                            VStack(spacing: 16) {
                                // Phone Number Field with real-time validation
                                GlassyInputField(
                                    icon: "phone", 
                                    title: "PHONE NUMBER", 
                                    labelColor: phoneValidationColor
                                ) {
                                    TextField("", text: $phoneNumber)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .keyboardType(.phonePad)
                                        .textContentType(.telephoneNumber)
                                        .onChange(of: phoneNumber) { newValue in
                                            // Format phone number as user types
                                            phoneNumber = formatPhoneNumber(newValue)
                                            validatePhoneNumber(phoneNumber)
                                            if !hasInteracted { hasInteracted = true }
                                        }
                                        .placeholder(when: phoneNumber.isEmpty) {
                                            Text("+1 (555) 123-4567")
                                                .foregroundColor(.white.opacity(0.5))
                                                .font(.plusJakarta(.body))
                                        }
                                }
                                
                                // Info text about SMS charges
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("We'll send you a verification code via SMS.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Text("Standard message and data rates may apply.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 4)
                                
                                // Send Code Button
                                Button(action: {
                                    // Add haptic feedback for immediate response
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    sendVerificationCode()
                                }) {
                                    ZStack {
                                        HStack {
                                            if isLoading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                    .scaleEffect(0.8)
                                                Text("Sending Code...")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            } else {
                                                Text("Send Verification Code")
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
                                if !showingPhoneVerification {
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
        .fullScreenCover(isPresented: $showingPhoneVerification) {
            PhoneVerificationView(phoneNumber: phoneNumber, authService: authService)
                .environmentObject(authViewModel)
        }
    }
    
    // MARK: - Validation Methods
    private func validatePhoneNumber(_ phone: String) {
        // Basic phone number validation - check if it has at least 10 digits
        let digitsOnly = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        phoneIsValid = digitsOnly.count >= 10
    }
    
    private func formatPhoneNumber(_ phone: String) -> String {
        // Remove all non-numeric characters
        let digitsOnly = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
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
    
    private func getCleanPhoneNumber() -> String {
        // Extract just the digits and format for Firebase (+1XXXXXXXXXX)
        let digitsOnly = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count == 10 {
            return "+1\(digitsOnly)"
        } else if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+\(digitsOnly)"
        } else if digitsOnly.count >= 10 {
            // Take first 10 digits and add +1
            let first10 = String(digitsOnly.prefix(10))
            return "+1\(first10)"
        }
        
        return "+1\(digitsOnly)"
    }
    
    // MARK: - Computed Properties for UI States
    private var phoneValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return phoneIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
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
    
    // MARK: - Send Verification Code Method
    private func sendVerificationCode() {
        // Prevent double submission
        guard !isLoading else { return }
        
        // Final validation before submission
        guard isFormValid else {
            errorMessage = "Please enter a valid phone number"
            showingError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let cleanPhoneNumber = getCleanPhoneNumber()
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
}



