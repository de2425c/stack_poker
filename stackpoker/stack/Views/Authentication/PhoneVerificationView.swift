import SwiftUI
import FirebaseAuth

struct PhoneVerificationView: View {
    let phoneNumber: String
    let authService: AuthService
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var resendDisabled = false
    @State private var resendCountdown = 30
    @State private var timer: Timer?
    
    // Real-time validation states
    @State private var codeIsValid = false
    @State private var hasInteracted = false
    
    // Computed property for form validity
    private var isFormValid: Bool {
        codeIsValid
    }
    
    var body: some View {
                    ZStack {
                AppBackgroundView()
                    .ignoresSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header section
                VStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                    
                    Text("Verify Your Phone")
                        .font(.custom("PlusJakartaSans-Bold", size: 28))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 4) {
                        Text("We've sent a verification code to")
                            .font(.custom("PlusJakartaSans-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(phoneNumber)
                            .font(.custom("PlusJakartaSans-Medium", size: 16))
                            .foregroundColor(.white)
                    }
                    .multilineTextAlignment(.center)
                }
                
                // Verification code input
                VStack(spacing: 16) {
                    GlassyInputField(
                        icon: "lock.shield", 
                        title: "VERIFICATION CODE", 
                        labelColor: codeValidationColor
                    ) {
                        TextField("", text: $verificationCode)
                            .font(.custom("PlusJakartaSans-Bold", size: 24))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .onChange(of: verificationCode) { newValue in
                                // Limit to 6 digits and validate
                                let digitsOnly = newValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                                verificationCode = String(digitsOnly.prefix(6))
                                validateCode(verificationCode)
                                if !hasInteracted { hasInteracted = true }
                                
                                // Auto-submit when 6 digits are entered
                                if verificationCode.count == 6 {
                                    verifyCode()
                                }
                            }
                            .placeholder(when: verificationCode.isEmpty) {
                                Text("123456")
                                    .foregroundColor(.white.opacity(0.3))
                                    .font(.custom("PlusJakartaSans-Bold", size: 24))
                            }
                    }
                    
                    Text("Enter the 6-digit code sent to your phone")
                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                
                // Action buttons
                VStack(spacing: 16) {
                    // Verify button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        verifyCode()
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Verifying...")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    .foregroundColor(.white)
                            } else {
                                Text("Verify Code")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
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
                    
                    // Resend code button
                    Button(action: {
                        resendCode()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                            
                            if resendDisabled {
                                Text("Resend code in \(resendCountdown)s")
                                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                            } else {
                                Text("Resend verification code")
                                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                            }
                        }
                        .foregroundColor(resendDisabled ? .gray : .white)
                    }
                    .disabled(resendDisabled)
                    
                    // Cancel/Back button
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Use a different phone number")
                            .font(.custom("PlusJakartaSans-Medium", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            startResendCountdown()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    // MARK: - Validation Methods
    private func validateCode(_ code: String) {
        codeIsValid = code.count == 6 && code.allSatisfy { $0.isNumber }
    }
    
    // MARK: - Computed Properties for UI States
    private var codeValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return codeIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
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
    
    // MARK: - Verification Methods
    private func verifyCode() {
        guard !isLoading else { return }
        
        guard isFormValid else {
            errorMessage = "Please enter a valid 6-digit verification code"
            showingError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                try await authService.verifyPhoneCode(verificationCode: verificationCode)
                
                await MainActor.run {
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    isLoading = false
                    // Just dismiss - let MainCoordinator handle the rest like EmailVerificationView
                    dismiss()
                }
            } catch let error as AuthError {
                await MainActor.run {
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
    
    private func resendCode() {
        Task {
            do {
                let cleanPhoneNumber = getCleanPhoneNumber(phoneNumber)
                try await authService.sendPhoneVerificationCode(phoneNumber: cleanPhoneNumber)
                
                await MainActor.run {
                    startResendCountdown()
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? AuthError)?.message ?? "Failed to resend verification code"
                    showingError = true
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func getCleanPhoneNumber(_ displayNumber: String) -> String {
        let digitsOnly = displayNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count == 10 {
            return "+1\(digitsOnly)"
        } else if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+\(digitsOnly)"
        }
        
        return "+1\(digitsOnly)"
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
} 