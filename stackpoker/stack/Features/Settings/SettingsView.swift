import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

// MARK: - SettingsView
struct SettingsView: View {
    let userId: String
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var sessionStore: SessionStore // Add SessionStore
    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var deleteError: String? = nil
    @State private var isDeleting = false
    @State private var pushNotificationsEnabled: Bool = true // Added for push notification toggle
    // Consolidated import states
    @State private var showImportOptionsSheet = false
    @State private var currentImportType: ImportType = .pokerbase
    @State private var showFileImporter: Bool = false
    @State private var importStatusMessage: String? = nil
    @State private var isImporting = false
    @State private var showPokerIncomeAlert = false
    @State private var showingLegalDocs = false
    
    var body: some View {
        ZStack {
            // Use AppBackgroundView as the background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // Push Notifications Toggle
                HStack {
                    Text("Push Notifications")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $pushNotificationsEnabled)
                        .labelsHidden()
                        .tint(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))) // Green accent
                        .onChange(of: pushNotificationsEnabled) { newValue in
                            // TODO: Implement logic to update user's push notification preferences
                            print("Push notifications toggled to: \(newValue)")
                            // Example: APIManager.shared.updatePushNotificationSetting(enabled: newValue)
                        }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                )
                .padding(.horizontal, 20)
                
                // Consolidated Import CSV Button
                Button(action: { 
                    showImportOptionsSheet = true
                }) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Text("Import CSV")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Spacer()
                        Text("Multiple Formats")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                // Terms & Conditions Button
                Button(action: {
                    showingLegalDocs = true
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Text("Terms & Conditions")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Sign Out Button
                Button(action: signOut) {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                // Delete Account Button
                Button(action: { showDeleteConfirmation = true }) {
                    HStack {
                        Spacer()
                        Text("Delete Account")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)

                // Company Info
                VStack(spacing: 8) {
                    Text("stackpoker.gg")
                        .font(.plusJakarta(.footnote)) // Using Plus Jakarta Sans font
                        .foregroundColor(.gray)
                        .onTapGesture {
                            if let url = URL(string: "https://stackpoker.gg") {
                                UIApplication.shared.open(url)
                            }
                        }

                    Text("support@stackpoker.gg")
                        .font(.plusJakarta(.footnote)) // Using Plus Jakarta Sans font
                        .foregroundColor(.gray)
                        .onTapGesture {
                            if let url = URL(string: "mailto:support@stackpoker.gg") {
                                UIApplication.shared.open(url)
                            }
                        }
                }
                .padding(.top, 30) // Space above company info
                .padding(.bottom, 120) // Maintained bottom padding for tab bar space
            }
            
            // Simple loading overlay
            if isImporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                            .scaleEffect(1.2)
                        
                        Text("Importing \(currentImportType.title) data...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 0.95)))
                            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                    )
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isImporting)
            }
        }
        .alert("Delete Your Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                showFinalDeleteConfirmation = true
            }
        } message: {
            Text("This will remove all your data from the app. This action cannot be undone.")
        }
        .alert("Permanently Delete Account", isPresented: $showFinalDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, Delete Everything", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Are you absolutely sure? All your data, posts, groups, and messages will be permanently deleted.")
        }
        .alert("Error", isPresented: .init(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An unknown error occurred")
        }
        .alert("Import Result", isPresented: Binding(get: { importStatusMessage != nil }, set: { if !$0 { importStatusMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importStatusMessage ?? "")
        }
        .alert("Import from Poker Income Ultimate", isPresented: $showPokerIncomeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To import your data from Poker Income Ultimate, please forward the export email to support@stackpoker.gg and include your username in the email body.")
        }
        .sheet(isPresented: $showImportOptionsSheet) {
            ImportOptionsSheet(
                onImportSelected: { importType in
                    if importType == .pokerIncomeUltimate {
                        showPokerIncomeAlert = true
                    } else {
                        currentImportType = importType
                        showFileImporter = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingLegalDocs) {
            LegalDocsView()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .text, .data]) { result in
            print("Consolidated file importer triggered for type: \(currentImportType)")
            switch result {
            case .success(let url):
                print("File selected: \(url)")
                isImporting = true
                switch currentImportType {
                case .pokerbase:
                    sessionStore.importSessionsFromPokerbaseCSV(fileURL: url) { importResult in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch importResult {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Pokerbase."
                            case .failure(let error):
                                importStatusMessage = "Pokerbase import failed: \(error.localizedDescription)"
                            }
                        }
                    }
                case .pokerAnalytics:
                    sessionStore.importSessionsFromPokerAnalyticsCSV(fileURL: url) { res in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch res {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Poker Analytics."
                            case .failure(let err):
                                importStatusMessage = "Poker Analytics import failed: \(err.localizedDescription)"
                            }
                        }
                    }
                case .pbt:
                    sessionStore.importSessionsFromPBTCSV(fileURL: url) { res in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch res {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Poker Bankroll Tracker."
                            case .failure(let err):
                                importStatusMessage = "Poker Bankroll Tracker import failed: \(err.localizedDescription)"
                            }
                        }
                    }
                case .regroup:
                    sessionStore.importSessionsFromRegroupCSV(fileURL: url) { res in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch res {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Regroup."
                            case .failure(let err):
                                importStatusMessage = "Regroup import failed: \(err.localizedDescription)"
                            }
                        }
                    }
                case .pokerIncomeUltimate:
                    // Handle Poker Income Ultimate import
                    importStatusMessage = "Import from Poker Income Ultimate is not supported in this version."
                    isImporting = false
                }
            case .failure(let error):
                print("File picker error: \(error)")
                importStatusMessage = "Failed to pick \(currentImportType.title) file: \(error.localizedDescription)"
            }
        }
    }
    
    private func signOut() {
        // Use the AuthViewModel's signOut method for proper cleanup
        authViewModel.signOut()
        
        // No need to manually set authState as the listener will handle it
    }
    
    private func deleteAccount() {
        guard let userId = Auth.auth().currentUser?.uid else {
            deleteError = "Not signed in"
            return
        }
        
        isDeleting = true
        
        Task {
            do {
                // 1. Delete user data from collections
                try await deleteUserDataFromFirestore(userId)
                
                // 2. Delete Firebase Auth user
                try await Auth.auth().currentUser?.delete()
                
                // 3. Sign out immediately after successful deletion
                do {
                    try Auth.auth().signOut()
                } catch {

                }
                
                await MainActor.run {
                    isDeleting = false
                    // The app will automatically redirect to the sign-in page due to auth state change
                    authViewModel.checkAuthState()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteUserDataFromFirestore(_ userId: String) async throws {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Delete user document
        batch.deleteDocument(db.collection("users").document(userId))
        
        // Delete user's groups
        let userGroups = try await db.collection("users")
            .document(userId)
            .collection("groups")
            .getDocuments()
        
        for doc in userGroups.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete user's group invites
        let userInvites = try await db.collection("users")
            .document(userId)
            .collection("groupInvites")
            .getDocuments()
        
        for doc in userInvites.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete user's follow relationships from userFollows collection
        // Delete where user is a follower (following someone)
        let followingDocs = try await db.collection("userFollows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        for doc in followingDocs.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete where user is being followed (someone following them)
        let followerDocs = try await db.collection("userFollows")
            .whereField("followeeId", isEqualTo: userId)
            .getDocuments()
        
        for doc in followerDocs.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Commit the batch deletion of Firestore data
        try await batch.commit()
        
        // Attempt to delete profile image, but don't let it stop the account deletion process
        do {
            try await Storage.storage().reference()
                .child("profile_images/\(userId).jpg")
                .delete()
        } catch {
            // Log the error but continue with account deletion

        }
    }
}