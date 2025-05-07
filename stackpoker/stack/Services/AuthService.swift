import Foundation
import FirebaseAuth

class AuthService: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    init() {
        // Listen for authentication state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    func signInWithEmail(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self.user = result.user
                self.isAuthenticated = true
            }
            
            // Send email verification
            try await sendEmailVerification()
        } catch {
            throw handleFirebaseError(error)
        }
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
    
    func reloadUser() async throws -> Bool {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        
        try await user.reload()
        return Auth.auth().currentUser?.isEmailVerified ?? false
    }
    
    func signOut() throws {
        do {
            // Post notification to allow services to clean up before sign out
            NotificationCenter.default.post(name: NSNotification.Name("UserWillSignOut"), object: nil)
            
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                self.user = nil
                self.isAuthenticated = false
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
        
        print("Firebase error: \(error.localizedDescription) (Code: \(nsError.code))")
        
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
        case .unknown(let message):
            return message
        }
    }
} 