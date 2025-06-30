import Foundation
@preconcurrency import FirebaseAuth
import FirebaseCore

@MainActor
class AuthService: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    
    // Store verification ID for phone authentication
    @Published var verificationID: String?
    
    init() {
        // Ensure Firebase is configured
        if FirebaseApp.app() == nil {
            print("AuthService: Warning - Firebase not configured yet")
        }
        
        // Listen for authentication state changes
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task {
                await self?._updateAuthState(with: firebaseUser)
            }
        }
        
        print("AuthService: Initialized successfully")
    }
    
    private func _updateAuthState(with firebaseUser: FirebaseAuth.User?) {
        self.user = firebaseUser
        self.isAuthenticated = firebaseUser != nil
    }
    
    deinit {
        if let handle = authStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func signInWithEmail(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await MainActor.run {
                self.user = result.user
                self.isAuthenticated = true
            }
            
            // Check if the user's email is verified
            if !result.user.isEmailVerified {
                throw AuthError.emailNotVerified
            }
        } catch {
            throw handleFirebaseError(error)
        }
    }
    
    func signUpWithEmail(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            await MainActor.run {
                self.user = result.user
                self.isAuthenticated = true
            }
            
            // Send email verification
            try await sendEmailVerification()
        } catch {
            throw handleFirebaseError(error)
        }
    }
    
    // MARK: - Phone Authentication Methods
    
    func sendPhoneVerificationCode(phoneNumber: String) async throws {
        do {
            print("AuthService: Starting phone verification for: \(phoneNumber)")
            
            // Ensure we're on the main actor for Firebase Auth operations
            await MainActor.run {
                // Configure Firebase Auth settings
                Auth.auth().settings?.isAppVerificationDisabledForTesting = false
                
                Auth.auth().languageCode = "en"
                print("AuthService: Firebase Auth configured for production")
            }
            
            // Small delay to ensure settings are applied
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            // Verify that Firebase is properly initialized
            guard FirebaseApp.app() != nil else {
                throw AuthError.unknown(message: "Firebase is not properly initialized")
            }
            
            print("AuthService: Attempting phone verification...")
            let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            
            await MainActor.run {
                self.verificationID = verificationID
                print("AuthService: Phone verification code sent successfully")
            }
        } catch {
            print("AuthService: Phone verification failed with error: \(error)")
            
            // Provide more specific error information
            if let nsError = error as NSError? {
                print("AuthService: Error domain: \(nsError.domain), code: \(nsError.code)")
                print("AuthService: Error description: \(nsError.localizedDescription)")
                if let userInfo = nsError.userInfo as? [String: Any] {
                    print("AuthService: Error userInfo: \(userInfo)")
                }
            }
            
            throw handleFirebaseError(error)
        }
    }
    
    func verifyPhoneCode(verificationCode: String) async throws {
        guard let verificationID = verificationID else {
            throw AuthError.phoneVerificationFailed
        }
        
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: verificationCode
            )
            
            let result = try await Auth.auth().signIn(with: credential)
            await MainActor.run {
                self.user = result.user
                self.isAuthenticated = true
                self.verificationID = nil // Clear after successful verification
            }
        } catch {
            throw handleFirebaseError(error)
        }
    }
    
    func signUpWithPhoneNumber(phoneNumber: String) async throws {
        // For phone authentication, we first send the verification code
        // The actual signup happens in verifyPhoneCode
        try await sendPhoneVerificationCode(phoneNumber: phoneNumber)
    }
    
    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        
        do {
            try await user.sendEmailVerification()
        } catch {
            throw AuthError.verificationEmailFailed
        }
    }
    
    func sendPasswordResetEmail(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw handleFirebaseError(error)
        }
    }
    
    func reloadUser() async throws -> Bool {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        
        try await user.reload()
        return Auth.auth().currentUser?.isEmailVerified ?? false
    }
    
    func signOut() async throws {
        do {
            // Post notification to allow services to clean up before sign out
            NotificationCenter.default.post(name: NSNotification.Name("UserWillSignOut"), object: nil)
            
            try Auth.auth().signOut()
            await MainActor.run {
                self.user = nil
                self.isAuthenticated = false
                self.verificationID = nil // Clear verification ID on sign out
            }
        } catch {
            throw AuthError.signOutError
        }
    }
    
    private func handleFirebaseError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        
        // Handle email verification error separately
        if error is AuthError {
            return error as! AuthError
        }
        
        
        switch nsError.code {
        case AuthErrorCode.wrongPassword.rawValue:
            return .wrongPassword
        case AuthErrorCode.userNotFound.rawValue:
            return .userNotFound
        case AuthErrorCode.invalidEmail.rawValue:
            return .invalidEmail
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return .emailInUse
        case AuthErrorCode.networkError.rawValue:
            return .networkError
        case AuthErrorCode.weakPassword.rawValue:
            return .weakPassword
        case AuthErrorCode.tooManyRequests.rawValue:
            return .tooManyRequests
        case AuthErrorCode.userDisabled.rawValue:
            return .userDisabled
        case AuthErrorCode.requiresRecentLogin.rawValue:
            return .requiresRecentLogin
        case AuthErrorCode.invalidPhoneNumber.rawValue:
            return .invalidPhoneNumber
        case AuthErrorCode.invalidVerificationCode.rawValue:
            return .invalidVerificationCode
        case AuthErrorCode.invalidVerificationID.rawValue:
            return .phoneVerificationFailed
        case AuthErrorCode.sessionExpired.rawValue:
            return .phoneVerificationExpired
        case AuthErrorCode.quotaExceeded.rawValue:
            return .quotaExceeded
        case AuthErrorCode.missingPhoneNumber.rawValue:
            return .missingPhoneNumber
        case AuthErrorCode.captchaCheckFailed.rawValue:
            return .captchaCheckFailed
        case AuthErrorCode.appNotAuthorized.rawValue:
            return .unknown(message: "App not authorized for phone authentication. Please check APNs configuration.")
        case AuthErrorCode.missingAppToken.rawValue:
            return .unknown(message: "Missing APNs token. Please ensure push notifications are enabled.")
        default:
            return .unknown(message: error.localizedDescription)
        }
    }
}

enum AuthError: Error {
    case invalidCredentials
    case wrongPassword
    case userNotFound
    case networkError
    case invalidEmail
    case emailInUse
    case weakPassword
    case signOutError
    case unknown(message: String = "An unknown error occurred")
    case emailNotVerified
    case verificationEmailFailed
    case notAuthenticated
    case tooManyRequests
    case userDisabled
    case requiresRecentLogin
    case passwordResetSent
    // Phone authentication errors
    case invalidPhoneNumber
    case invalidVerificationCode
    case phoneVerificationFailed
    case phoneVerificationExpired
    case quotaExceeded
    case missingPhoneNumber
    case captchaCheckFailed
    
    var message: String {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .wrongPassword:
            return "Incorrect password. Please try again."
        case .userNotFound:
            return "No account found with this email. Please check your email or sign up."
        case .networkError:
            return "Network error occurred. Please check your internet connection."
        case .invalidEmail:
            return "Invalid email format. Please enter a valid email address."
        case .emailInUse:
            return "Email is already in use. Try signing in or use a different email."
        case .weakPassword:
            return "Password must be at least 6 characters long."
        case .signOutError:
            return "Error signing out. Please try again."
        case .emailNotVerified:
            return "Please verify your email before signing in. Check your inbox."
        case .verificationEmailFailed:
            return "Failed to send verification email. Please try again later."
        case .notAuthenticated:
            return "You must be logged in to perform this action."
        case .tooManyRequests:
            return "Too many login attempts. Please try again later."
        case .userDisabled:
            return "Your account has been disabled. Please contact support."
        case .requiresRecentLogin:
            return "For security reasons, please sign in again before completing this action."
        case .passwordResetSent:
            return "Password reset email has been sent. Please check your inbox."
        case .invalidPhoneNumber:
            return "Invalid phone number format. Please check your phone number."
        case .invalidVerificationCode:
            return "Invalid verification code. Please check the code and try again."
        case .phoneVerificationFailed:
            return "Phone verification failed. Please try again."
        case .phoneVerificationExpired:
            return "Verification code has expired. Please request a new code."
        case .quotaExceeded:
            return "SMS quota exceeded. Please try again later."
        case .missingPhoneNumber:
            return "Phone number is required for verification."
        case .captchaCheckFailed:
            return "CAPTCHA verification failed. Please try again."
        case .unknown(let message):
            return message
        }
    }
} 