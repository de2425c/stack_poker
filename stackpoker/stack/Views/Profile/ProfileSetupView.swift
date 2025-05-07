import SwiftUI
import FirebaseFirestore

struct ProfileSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var userService = UserService()
    @State private var username = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    // New states for real-time username checking
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool? = nil
    @State private var lastCheckedUsername = ""
    let isNewUser: Bool
    
    // Debounce timer for username checks
    @State private var usernameCheckTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Complete Your Profile")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Tell us a bit about yourself")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 40)
                        
                        // Form Fields
                        VStack(spacing: 16) {
                            // Username field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Username")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 14))
                                
                                HStack {
                                    TextField("", text: $username)
                                        .textFieldStyle(CustomTextFieldStyle())
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .onChange(of: username) { newValue in
                                            checkUsername(newValue)
                                        }
                                    
                                    // Username availability indicator
                                    if !username.isEmpty {
                                        if isCheckingUsername {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                                .frame(width: 20, height: 20)
                                        } else if let isAvailable = usernameAvailable {
                                            Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .foregroundColor(isAvailable ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                }
                                
                                // Username availability message
                                if !username.isEmpty && !isCheckingUsername {
                                    if username == lastCheckedUsername {
                                        if let isAvailable = usernameAvailable {
                                            Text(isAvailable ? "Username available!" : "Username already taken")
                                                .font(.system(size: 12))
                                                .foregroundColor(isAvailable ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                                        }
                                    }
                                }
                            }
                            
                            // Display Name field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display Name")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 14))
                                
                                TextField("", text: $displayName)
                                    .textFieldStyle(CustomTextFieldStyle())
                                
                                if displayName.isEmpty {
                                    Text("Display name is required")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .padding(.top, 32)
                        
                        Spacer()
                        
                        // Submit Button
                        Button(action: createProfile) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Text("Complete Setup")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(buttonBackgroundColor)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .disabled(isButtonDisabled)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 24)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationBarHidden(true)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // Dynamic button background color based on validation
    private var buttonBackgroundColor: Color {
        if isButtonDisabled {
            return Color.gray
        }
        return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
    }
    
    // Button disabled state
    private var isButtonDisabled: Bool {
        username.isEmpty || displayName.isEmpty || isLoading || isCheckingUsername || usernameAvailable == false
    }
    
    // Check username availability in real-time
    private func checkUsername(_ username: String) {
        // Cancel any existing task
        usernameCheckTask?.cancel()
        
        // Reset state if empty
        if username.isEmpty {
            usernameAvailable = nil
            isCheckingUsername = false
            return
        }
        
        // Don't check too short usernames
        if username.count < 3 {
            usernameAvailable = false
            return
        }
        
        // Set checking state
        isCheckingUsername = true
        
        // Debounce username checks by 500ms
        usernameCheckTask = Task {
            // Wait to avoid too many requests while typing
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if Task.isCancelled { return }
            
            do {
                // Query Firestore for existing username
                let db = Firestore.firestore()
                let querySnapshot = try await db.collection("users")
                    .whereField("username", isEqualTo: username)
                    .getDocuments()
                
                if Task.isCancelled { return }
                
                // Update UI on main thread
                await MainActor.run {
                    lastCheckedUsername = username
                    usernameAvailable = querySnapshot.documents.isEmpty
                    isCheckingUsername = false
                }
            } catch {
                if Task.isCancelled { return }
                
                // Handle errors
                await MainActor.run {
                    isCheckingUsername = false
                    usernameAvailable = nil
                }
            }
        }
    }
    
    private func createProfile() {
        guard !username.isEmpty && !displayName.isEmpty else { return }
        
        isLoading = true
        Task {
            do {
                try await userService.createUserProfile(
                    username: username,
                    displayName: displayName
                )
                DispatchQueue.main.async {
                    if isNewUser {
                        authViewModel.authState = .signedIn
                    }
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = (error as? UserServiceError)?.message ?? "An unexpected error occurred"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
}

// Custom modifier to handle keyboard
struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onAppear {
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                    let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
                    keyboardHeight = keyboardFrame.height
                }
                
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                    keyboardHeight = 0
                }
            }
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        ModifiedContent(content: self, modifier: KeyboardAdaptive())
    }
} 