import SwiftUI
import FirebaseFirestore
import PhotosUI
import FirebaseAuth

struct ProfileSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var userService: UserService
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool? = nil
    @State private var lastCheckedUsername = ""
    @State private var currentStep = 1 // Track which step we're on (1 or 2)
    let isNewUser: Bool
    
    // Profile image
    @State private var selectedImage: UIImage? = nil
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var isUploadingImage = false
    
    // Debounce timer for username checks
    @State private var usernameCheckTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Use AppBackgroundView
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        Text(currentStep == 1 ? "Create Profile" : "Complete Profile")
                            .font(.custom("PlusJakartaSans-Bold", size: 32))
                            .foregroundColor(.white)
                            .padding(.top, 85)
                        
                        Text(currentStep == 1 ? "Step 1/2: Set your display name and username" : "Step 2/2: Tell us about yourself")
                            .font(.custom("PlusJakartaSans-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.bottom, 12)
                        
                        // Form content based on step
                        if currentStep == 1 {
                            // Step 1: Display Name and Username
                            VStack(spacing: 16) {
                                // Display Name field
                                GlassyInputField(icon: "person", title: "DISPLAY NAME", labelColor: Color.white.opacity(0.6)) {
                                    TextField("", text: $displayName)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                }
                                
                                // Username field with availability check
                                VStack(spacing: 4) {
                                    GlassyInputField(icon: "at", title: "USERNAME", labelColor: Color.white.opacity(0.6)) {
                                        HStack {
                                            TextField("", text: $username)
                                                .font(.plusJakarta(.body))
                                                .foregroundColor(.white)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                                .onChange(of: username) { newValue in
                                                    checkUsername(newValue)
                                                }
                                            
                                            // Username availability indicator
                                            if !username.isEmpty {
                                                if isCheckingUsername {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                        .frame(width: 20, height: 20)
                                                } else if let isAvailable = usernameAvailable {
                                                    Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                        .foregroundColor(isAvailable ? Color(red: 64/255, green: 156/255, blue: 255/255) : .red)
                                                        .frame(width: 20, height: 20)
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Username availability message
                                    if !username.isEmpty && !isCheckingUsername && username == lastCheckedUsername {
                                        if let isAvailable = usernameAvailable {
                                            Text(isAvailable ? "Username available!" : "Username already taken")
                                                .font(.custom("PlusJakartaSans-Regular", size: 12))
                                                .foregroundColor(isAvailable ? Color(red: 64/255, green: 156/255, blue: 255/255) : .red)
                                                .padding(.leading, 8)
                                        }
                                    }
                                }
                                
                                // Next button
                                Button(action: {
                                    currentStep = 2
                                }) {
                                    Text("Next")
                                        .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity, minHeight: 56)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(step1ButtonBackgroundColor)
                                )
                                .disabled(isStep1ButtonDisabled)
                                .contentShape(Rectangle())
                                .padding(.top, 24)
                            }
                        } else {
                            // Step 2: Profile Photo, Bio and Location
                            VStack(spacing: 16) {
                                // Profile Photo Section
                                VStack(spacing: 12) {
                                    Text("PROFILE PHOTO")
                                        .font(.custom("PlusJakartaSans-Medium", size: 12))
                                        .foregroundColor(Color.white.opacity(0.6))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 8)
                                        
                                    ZStack {
                                        // Photo background circle
                                        Circle()
                                            .fill(Color.black.opacity(0.3))
                                            .frame(width: 100, height: 100)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                            )
                                        
                                        // Selected image or placeholder
                                        if let selectedImage = selectedImage {
                                            Image(uiImage: selectedImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 90, height: 90)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        
                                        // Upload indicator if uploading
                                        if isUploadingImage {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(1.5)
                                        }
                                        
                                        // Camera button overlay
                                        PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color(red: 64/255, green: 156/255, blue: 255/255),
                                                            Color(red: 100/255, green: 180/255, blue: 255/255)
                                                        ]),
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ))
                                                    .frame(width: 32, height: 32)
                                                
                                                Image(systemName: "camera.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                        .onChange(of: imagePickerItem) { newItem in
                                            loadTransferableImage(from: newItem)
                                        }
                                        .position(x: 70, y: 70)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.bottom, 8)
                                }
                                
                                // Bio field
                                GlassyInputField(icon: "text.quote", title: "BIO", labelColor: Color.white.opacity(0.6)) {
                                    TextEditor(text: $bio)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .frame(minHeight: 100)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.clear)
                                }
                                .frame(height: 130)
                                
                                // Location field
                                GlassyInputField(icon: "location", title: "LOCATION", labelColor: Color.white.opacity(0.6)) {
                                    TextField("", text: $location)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                }
                                
                                // Buttons row
                                HStack(spacing: 16) {
                                    // Back button
                                    Button(action: {
                                        currentStep = 1
                                    }) {
                                        Text("Back")
                                            .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(Color.white.opacity(0.15))
                                    .foregroundColor(.white)
                                    .cornerRadius(28)
                                    
                                    // Complete setup button
                                    Button(action: createProfile) {
                                        if isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                .scaleEffect(0.8)
                                        } else {
                                            Text("Complete Setup")
                                                .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                .foregroundColor(.black)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(
                                        RoundedRectangle(cornerRadius: 28)
                                            .fill(LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                                    Color(red: 100/255, green: 180/255, blue: 255/255)
                                                ]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ))
                                    )
                                    .disabled(isLoading)
                                    .contentShape(Rectangle())
                                }
                                .padding(.top, 24)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .onTapGesture {
                    // Tap to dismiss keyboard when in step 2
                    if currentStep == 2 {
                        hideKeyboard()
                    }
                }
                
                // Close button - only show for actual new users who might want to sign out
                if isNewUser {
                    VStack {
                        HStack {
                            Button(action: { 
                                // Sign out since they're not completing profile setup
                                do {
                                    try Auth.auth().signOut()
                                } catch {
                                    print("Error signing out: \(error)")
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
            }
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
                .font(.custom("PlusJakartaSans-Medium", size: 16))
        }
        .onChange(of: authViewModel.appFlow) { newFlow in
            // Auto-dismiss when the app flow changes to main (profile setup complete)
            if case .main = newFlow {
                print("ProfileSetupView: App flow changed to main, dismissing ProfileSetupView")
                dismiss()
            }
        }

    }
    
    // Helper function to dismiss keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // Dynamic button background color for step 1
    private var step1ButtonBackgroundColor: LinearGradient {
        if isStep1ButtonDisabled {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray, Color.gray]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 64/255, green: 156/255, blue: 255/255),
                Color(red: 100/255, green: 180/255, blue: 255/255)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // Button disabled state for step 1
    private var isStep1ButtonDisabled: Bool {
        username.isEmpty || displayName.isEmpty || isCheckingUsername || usernameAvailable == false
    }
    
    // Load image from picker
    private func loadTransferableImage(from imageSelection: PhotosPickerItem?) {
        guard let imageSelection = imageSelection else { return }
        
        Task {
            do {
                if let data = try await imageSelection.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            } catch {

            }
        }
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
        print("ProfileSetupView: createProfile called")
        print("ProfileSetupView: Username: '\(username)', DisplayName: '\(displayName)'")
        
        guard !username.isEmpty && !displayName.isEmpty else { 
            print("ProfileSetupView: Username or display name is empty")
            return 
        }
        
        // Check if user is authenticated
        guard let currentUser = Auth.auth().currentUser else {
            print("ProfileSetupView: No authenticated user found")
            errorMessage = "Authentication error. Please sign in again."
            showingError = true
            return
        }
        
        print("ProfileSetupView: User authenticated, UID: \(currentUser.uid)")
        
        isLoading = true
        
        Task {
            do {
                // First upload the image if selected
                var avatarURL: String? = nil
                
                if let selectedImage = selectedImage {
                    isUploadingImage = true
                    
                    // Get userId from Firebase Auth directly
                    let userId = Auth.auth().currentUser?.uid ?? ""
                    let uploadResult = await withCheckedContinuation { continuation in
                        userService.uploadProfileImage(selectedImage, userId: userId) { result in
                            continuation.resume(returning: result)
                        }
                    }
                    
                    isUploadingImage = false
                    
                    switch uploadResult {
                    case .success(let url):
                        avatarURL = url
                    case .failure(let error):
                        print("upload failed")
                        // Continue without image if upload fails
                    }
                }
                
                // Create a profile with all the collected data
                var profileData: [String: Any] = [
                    "username": username,
                    "displayName": displayName
                ]
                
                // Add optional fields if provided
                if !bio.isEmpty {
                    profileData["bio"] = bio
                }
                
                if !location.isEmpty {
                    profileData["location"] = location
                }
                
                // Add avatar URL if available
                if let avatarURL = avatarURL {
                    profileData["avatarURL"] = avatarURL
                }
                
                print("ProfileSetupView: About to create profile with data: \(profileData)")
                
                try await userService.createUserProfile(userData: profileData)
                
                print("ProfileSetupView: Profile created successfully!")
                
            } catch {
                print("ProfileSetupView: Profile creation failed with error: \(error)")
                print("ProfileSetupView: Error type: \(type(of: error))")
                print("ProfileSetupView: Error description: \(error.localizedDescription)")
                
                await MainActor.run {
                    // Provide more specific error messages
                    if let userServiceError = error as? UserServiceError {
                        errorMessage = userServiceError.message
                    } else {
                        let nsError = error as NSError
                        errorMessage = "Error (\(nsError.code)): \(nsError.localizedDescription)"
                    }
                    
                    showingError = true
                    isLoading = false
                    print("ProfileSetupView: Showing error: \(errorMessage)")
                }
                return
            }
            
            // Profile created successfully - refresh flow and let MainCoordinator handle everything
            await MainActor.run {
                isLoading = false
                
                // Add success haptic feedback
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                
                print("ProfileSetupView: Profile created successfully, forcing main flow")
                
                // If this ProfileSetupView is presented as a sheet (from EmailVerificationView),
                // dismiss it first before forcing the flow change to prevent sheet conflicts
                if isNewUser {
                    // Small delay to ensure the profile creation is fully processed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        authViewModel.forceAppFlow(.main(userId: currentUser.uid))
                    }
                } else {
                    // For ProfileSetupView shown directly in MainCoordinator, force the flow immediately
                    authViewModel.forceAppFlow(.main(userId: currentUser.uid))
                }
            }
        }
    }
}

