import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import UIKit

struct ProfileEditView: View {
    @State var profile: UserProfile
    var onSave: (UserProfile) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userService: UserService
    
    // Profile data
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var favoriteGame: String = "NLH"
    @State private var location: String = ""
    @State private var hyperlinkText: String = ""
    @State private var hyperlinkURL: String = ""
    
    // UI states
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    @State private var isAnimating = false
    @State private var activeField: ProfileField? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var saveButtonPressed = false // Added for animation
    
    // Game options
    let gameOptions = ["NLH", "PLO", "Omaha", "Stud8", "Razz"]
    
    // Focus management
    enum ProfileField {
        case displayName, username, bio, location, hyperlinkText, hyperlinkURL
    }
    
    var body: some View {
        ZStack {
            // Background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom navigation bar - with proper centering and top padding
                VStack(spacing: 0) {
                    // Add top spacing
                    Spacer()
                        .frame(height: 60) // Increased top padding
                    
                    HStack {
                        // Fixed width leading space
                        HStack {
                            Spacer()
                        }
                        .frame(width: 120) // Increased width to balance larger save button

                        // Centered title
                        Text("Edit Profile")
                            .font(.plusJakarta(.headline, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity) // Allow expansion

                        // Save button with fixed width container
                        HStack {
                            Spacer()
                            Button(action: {
                                print("Save button tapped") // Debug print
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    saveButtonPressed = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        saveButtonPressed = false
                                    }
                                }
                                saveProfile()
                            }) {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 20, height: 20)
                                } else {
                                    Text("Save")
                                        .font(.plusJakarta(.body, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20) // Increased horizontal padding
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                                        )
                                        .scaleEffect(saveButtonPressed ? 0.95 : 1.0) // Added scale animation
                                }
                            }
                            .disabled(isUploading)
                            .buttonStyle(PlainButtonStyle()) // Ensure it's properly tappable
                        }
                        .frame(width: 120) // Increased width to match leading space
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .background(Color.clear)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile photo section
                        VStack(spacing: 16) {
                            ZStack {
                                // Profile image container
                                Circle()
                                    .fill(Color(red: 32/255, green: 34/255, blue: 38/255))
                                    .frame(width: 82, height: 82)
                                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
                                
                                // Profile image
                                if let selectedImage = selectedImage {
                                    Image(uiImage: selectedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 75, height: 75)
                                        .clipShape(Circle())
                                } else if let url = profile.avatarURL, !url.isEmpty, let imageURL = URL(string: url) {
                                    AsyncImage(url: imageURL) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 75, height: 75)
                                                .clipShape(Circle())
                                        } else if phase.error != nil {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 50))
                                                .foregroundColor(.gray)
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                        }
                                    }
                                    .frame(width: 75, height: 75)
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                }
                                
                                // Camera button overlay
                                PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 2)
                                    )
                                }
                                .onChange(of: imagePickerItem) { newItem in
                                    loadTransferableImage(from: newItem)
                                }
                                .position(x: 85, y: 85)
                            }
                            
                            Text("Change Profile Photo")
                                .font(.plusJakarta(.footnote, weight: .medium))
                                .foregroundColor(.white) // Changed to white
                        }
                        .padding(.top, 8) // Reduced from 16 to 8 to bring profile photo closer to header
                        
                        // Form fields
                        VStack(spacing: 20) {
                            // Display name field
                            GlassyInputField(icon: "person.text.rectangle", title: "DISPLAY NAME") {
                                TextField("Your display name", text: $displayName)
                                    .font(.plusJakarta(.body))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .onTapGesture { activeField = .displayName }
                            }
                            
                            // Username field (non-editable, styled to match)
                            GlassyInputField(icon: "at", title: "USERNAME") {
                                HStack {
                                    Text("@\(username)")
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }

                            // Hyperlink text field
                            GlassyInputField(icon: "link", title: "LINK TEXT (OPTIONAL)") {
                                TextField("Link text (max 15 chars)", text: $hyperlinkText)
                                    .font(.plusJakarta(.body))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .onTapGesture { activeField = .hyperlinkText }
                                    .onChange(of: hyperlinkText) { newValue in
                                        if newValue.count > 15 {
                                            hyperlinkText = String(newValue.prefix(15))
                                        }
                                    }
                            }

                            // Hyperlink URL field
                            GlassyInputField(icon: "globe", title: "LINK URL (OPTIONAL)") {
                                TextField("https://example.com", text: $hyperlinkURL)
                                    .font(.plusJakarta(.body))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .onTapGesture { activeField = .hyperlinkURL }
                                    .autocapitalization(.none)
                                    .keyboardType(.URL)
                            }

                            // Bio field
                            GlassyInputField(icon: "text.alignleft", title: "BIO") {
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $bio)
                                        .font(.plusJakarta(.body))
                                        .foregroundColor(.white)
                                        .frame(minHeight: 80, maxHeight: 120)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.clear)
                                        .padding(.vertical, 6)
                                        .onTapGesture { activeField = .bio }

                                    if bio.isEmpty {
                                        Text("Tell us about yourself")
                                            .font(.plusJakarta(.body))
                                            .foregroundColor(.gray.opacity(0.7))
                                            .padding(.leading, 5)
                                            .padding(.top, 14)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                            
                            // Location field
                            GlassyInputField(icon: "mappin.and.ellipse", title: "LOCATION") {
                                TextField("Your location", text: $location)
                                    .font(.plusJakarta(.body))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .onTapGesture { activeField = .location }
                            }
                            
                            // Favorite game picker
                            VStack(alignment: .leading, spacing: 10) {
                                Text("FAVORITE GAME")
                                    .font(.plusJakarta(.caption, weight: .medium))
                                    .foregroundColor(Color.gray)
                                
                                // Game selection cards
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(gameOptions, id: \.self) { game in
                                            Button(action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    favoriteGame = game
                                                }
                                            }) {
                                                Text(game)
                                                    .font(.plusJakarta(.subheadline, weight: favoriteGame == game ? .semibold : .medium))
                                                    .foregroundColor(favoriteGame == game ? .black : .white)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 12)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .fill(favoriteGame == game ?
                                                                  Color.white.opacity(0.9) : // Selected: prominent white
                                                                  Color.white.opacity(0.1)) // Unselected: subtle glassy white
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(
                                                                favoriteGame == game ?
                                                                Color.white.opacity(0.7) : // Selected border
                                                                Color.white.opacity(0.2), // Unselected border
                                                                lineWidth: 1
                                                            )
                                                    )
                                            }
                                            .buttonStyle(ScaleButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Error message
                        if let uploadError = uploadError {
                            Text(uploadError)
                                .font(.plusJakarta(.footnote))
                                .foregroundColor(.red)
                                .padding(.top, 8)
                        }
                        
                        // Section for content that needs bottom padding before the end of ScrollView
                        VStack(spacing: 10) {
                            // Intentionally left blank for now, can add content here if needed above keyboard
                        }
                        .padding(.bottom, 30) // Ensures space when keyboard is up or for general layout
                    }
                    .padding(.top, 20) // Reduced top padding since we have header spacing now
                    .padding(.bottom, 20)
                }
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside input fields
            hideKeyboard()
        }
        .onAppear {
            initializeFields()
            animateIn()
        }
    }
    
    private func initializeFields() {
        displayName = profile.displayName ?? ""
        username = profile.username
        bio = profile.bio ?? ""
        favoriteGame = profile.favoriteGame ?? "NLH"
        location = profile.location ?? ""
        hyperlinkText = profile.hyperlinkText ?? ""
        hyperlinkURL = profile.hyperlinkURL ?? ""
    }
    
    private func animateIn() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.4)) {
                isAnimating = true
            }
        }
    }
    
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
                print("Error loading image: \(error)")
            }
        }
    }
    
    private func saveProfile() {
        print("saveProfile called") // Debug print
        
        // Reset any previous errors
        uploadError = nil
        
        // Update the profile with edited values
        var updatedProfile = profile
        updatedProfile.displayName = displayName.isEmpty ? nil : displayName
        updatedProfile.username = username
        updatedProfile.bio = bio.isEmpty ? nil : bio
        updatedProfile.favoriteGame = favoriteGame
        updatedProfile.location = location.isEmpty ? nil : location
        updatedProfile.hyperlinkText = hyperlinkText.isEmpty ? nil : hyperlinkText
        updatedProfile.hyperlinkURL = hyperlinkURL.isEmpty ? nil : hyperlinkURL
        
        // Handle image upload if needed
        if let selectedImage = selectedImage {
            print("Uploading image...") // Debug print
            isUploading = true
            
            userService.uploadProfileImage(selectedImage, userId: profile.id) { result in
                DispatchQueue.main.async {
                    self.isUploading = false
                    switch result {
                    case .success(let urlString):
                        print("Image uploaded successfully: \(urlString)") // Debug print
                        updatedProfile.avatarURL = urlString
                        self.saveProfileToFirestore(updatedProfile)
                    case .failure(let error):
                        print("Image upload failed: \(error)") // Debug print
                        self.uploadError = "Image upload error: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            print("No image to upload, saving directly...") // Debug print
            saveProfileToFirestore(updatedProfile)
        }
    }
    
    private func saveProfileToFirestore(_ updatedProfile: UserProfile) {
        print("saveProfileToFirestore called") // Debug print
        
        Task {
            do {
                // Create the update dictionary
                var updateData: [String: Any] = [
                    "username": updatedProfile.username,
                    "favoriteGame": updatedProfile.favoriteGame ?? "NLH"
                ]
                
                // Only include non-empty values
                if let displayName = updatedProfile.displayName, !displayName.isEmpty {
                    updateData["displayName"] = displayName
                }
                
                if let bio = updatedProfile.bio, !bio.isEmpty {
                    updateData["bio"] = bio
                }
                
                if let location = updatedProfile.location, !location.isEmpty {
                    updateData["location"] = location
                }
                
                if let hyperlinkText = updatedProfile.hyperlinkText, !hyperlinkText.isEmpty {
                    updateData["hyperlinkText"] = hyperlinkText
                }
                
                if let hyperlinkURL = updatedProfile.hyperlinkURL, !hyperlinkURL.isEmpty {
                    updateData["hyperlinkURL"] = hyperlinkURL
                }
                
                if let avatarURL = updatedProfile.avatarURL, !avatarURL.isEmpty {
                    updateData["avatarURL"] = avatarURL
                }
                
                print("Updating profile with data: \(updateData)") // Debug print
                
                try await userService.updateUserProfile(updateData)
                
                print("Profile updated successfully") // Debug print
                
                await MainActor.run {
                    onSave(updatedProfile)
                    dismiss()
                }
            } catch {
                print("Failed to save profile: \(error)") // Debug print
                await MainActor.run {
                    uploadError = "Failed to save profile: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Helper function to dismiss keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}