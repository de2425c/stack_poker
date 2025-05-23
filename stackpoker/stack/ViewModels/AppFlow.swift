import Foundation

// Unified onboarding / main-app state machine
// The whole UI switches off this single source of truth.
public enum AppFlow: Equatable {
    case loading                // waiting for Firebase
    case signedOut              // welcome / auth
    case emailVerification      // account exists but email not verified
    case profileSetup           // email verified but profile missing
    case main(userId: String)   // fully onboarded
} 