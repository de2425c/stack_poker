import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit
import Kingfisher

// MARK: - SettingsView
struct SettingsView: View {
    let userId: String
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var sessionStore: SessionStore
    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var deleteError: String? = nil
    @State private var isDeleting = false
    @State private var pushNotificationsEnabled: Bool = true
    // Consolidated import states
    @State private var showImportOptionsSheet = false
    @State private var currentImportType: ImportType = .pokerbase
    @State private var showFileImporter: Bool = false
    @State private var importStatusMessage: String? = nil
    @State private var isImporting = false
    @State private var showPokerIncomeAlert = false
    @State private var showingLegalDocs = false
    
    // NEW: Re-authentication states
    @State private var showReauthenticationAlert = false
    @State private var reauthEmail: String = ""
    @State private var reauthPassword: String = ""
    @State private var isReauthenticating = false
    @State private var pendingDeletion = false
    
    // Modern color scheme
    private let accentBlue = Color(red: 64/255, green: 156/255, blue: 255/255)
    private let backgroundCard = Color(UIColor(red: 28/255, green: 30/255, blue: 35/255, alpha: 1.0))
    private let glassBackground = Color.white.opacity(0.03)
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Modern Header with gradient
                    headerSection
                        .padding(.top, 10)
                        .padding(.bottom, 32)
                    
                    VStack(spacing: 24) {
                        // Preferences Section
                        SettingsSection(title: "Preferences") {
                            notificationToggleCard
                        }
                        
                        // Data Management Section
                        SettingsSection(title: "Data Management") {
                            VStack(spacing: 1) {
                                importCsvCard
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                legalDocsCard
                            }
                        }
                        
                        // Account Section
                        SettingsSection(title: "Account") {
                            VStack(spacing: 1) {
                                signOutCard
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                deleteAccountCard
                            }
                        }
                        
                        // Footer
                        footerSection
                            .padding(.top, 40)
                            .padding(.bottom, 120)
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Loading overlays
            if isImporting {
                modernLoadingOverlay(
                    title: "Importing Data",
                    subtitle: "Importing \(currentImportType.title) data...",
                    color: accentBlue
                )
            }
            
            if isDeleting || isReauthenticating {
                modernLoadingOverlay(
                    title: isReauthenticating ? "Re-authenticating" : "Deleting Account",
                    subtitle: isReauthenticating ? "Verifying your credentials..." : "Removing all your sessions, posts, and data...",
                    color: .red
                )
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
            Text("Are you absolutely sure? All your data, sessions, posts, and imported files will be permanently deleted. You may need to re-enter your password for security verification.")
        }
        .alert("Error", isPresented: .init(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An unknown error occurred")
        }
        .alert("Re-authentication Required", isPresented: $showReauthenticationAlert, actions: {
            TextField("Password", text: $reauthPassword)
            
            Button("Cancel", role: .cancel) {
                cancelReauthentication()
            }
            
            Button("Authenticate") {
                reauthenticateUser()
            }
            .disabled(isReauthenticating)
        }, message: {
            Text("For security reasons, please re-enter your password to confirm account deletion.\n\nEmail: \(reauthEmail)")
        })
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
                    importStatusMessage = "Import from Poker Income Ultimate is not supported in this version."
                    isImporting = false
                }
            case .failure(let error):
                print("File picker error: \(error)")
                importStatusMessage = "Failed to pick \(currentImportType.title) file: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - UI Components
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Manage your preferences and account")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Settings icon with accent
                ZStack {
                    Circle()
                        .fill(accentBlue.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(accentBlue)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var notificationToggleCard: some View {
        ModernSettingsRow(
            icon: "bell.fill",
            title: "Push Notifications",
            iconColor: accentBlue
        ) {
            Toggle("", isOn: $pushNotificationsEnabled)
                .labelsHidden()
                .tint(accentBlue)
                .onChange(of: pushNotificationsEnabled) { newValue in
                    print("Push notifications toggled to: \(newValue)")
                }
        }
    }
    
    private var importCsvCard: some View {
        ModernSettingsRow(
            icon: "tray.and.arrow.down.fill",
            title: "Import CSV",
            subtitle: "Multiple formats supported",
            iconColor: .orange,
            showChevron: true
        ) {
            EmptyView()
        }
        .onTapGesture {
            showImportOptionsSheet = true
        }
    }
    
    private var legalDocsCard: some View {
        ModernSettingsRow(
            icon: "doc.text.fill",
            title: "Terms & Conditions",
            iconColor: .purple,
            showChevron: true
        ) {
            EmptyView()
        }
        .onTapGesture {
            showingLegalDocs = true
        }
    }
    
    private var signOutCard: some View {
        ModernSettingsRow(
            icon: "arrow.right.square.fill",
            title: "Sign Out",
            iconColor: .gray,
            showChevron: true
        ) {
            EmptyView()
        }
        .onTapGesture {
            signOut()
        }
    }
    
    private var deleteAccountCard: some View {
        ModernSettingsRow(
            icon: "trash.fill",
            title: "Delete Account",
            subtitle: "Permanently remove all data",
            iconColor: .red,
            titleColor: .red,
            showChevron: true
        ) {
            EmptyView()
        }
        .onTapGesture {
            showDeleteConfirmation = true
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 12) {
            Text("stackpoker.gg")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accentBlue)
                .onTapGesture {
                    if let url = URL(string: "https://stackpoker.gg") {
                        UIApplication.shared.open(url)
                    }
                }

            Text("support@stackpoker.gg")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .onTapGesture {
                    if let url = URL(string: "mailto:support@stackpoker.gg") {
                        UIApplication.shared.open(url)
                    }
                }
        }
    }
    
    private func modernLoadingOverlay(title: String, subtitle: String, color: Color) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: color))
                    .scaleEffect(1.5)
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Material.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: isDeleting || isReauthenticating || isImporting)
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
                print("🗑️ Starting comprehensive account deletion for user: \(userId)")
                
                // 1. Delete user data from all Firestore collections and Storage first
                try await deleteUserDataFromFirestore(userId)
                print("🗑️ Firestore and Storage data deletion completed")
                
                // 2. Delete Firebase Auth user (this is the sensitive operation)
                try await Auth.auth().currentUser?.delete()
                print("🗑️ Firebase Auth user deleted")
                
                // 3. Sign out and update auth state immediately after successful deletion
                do {
                    try Auth.auth().signOut()
                    print("🗑️ User signed out successfully")
                } catch {
                    print("⚠️ Sign out failed: \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    isDeleting = false
                    pendingDeletion = false
                    print("🗑️ Account deletion completed successfully")
                    // Force auth state to signed out
                    authViewModel.checkAuthState()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    pendingDeletion = false
                    
                    // Check if this is a requiresRecentLogin error (check NSError first)
                    if let nsError = error as NSError?, nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                        handleReauthenticationRequired()
                    } else {
                        deleteError = "Failed to delete account: \(error.localizedDescription)"
                        print("❌ Account deletion failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // NEW: Handle re-authentication requirement
    private func handleReauthenticationRequired() {
        print("🔐 Re-authentication required for account deletion")
        pendingDeletion = true
        
        // Pre-fill email if available
        if let currentUser = Auth.auth().currentUser, let email = currentUser.email {
            reauthEmail = email
        }
        
        showReauthenticationAlert = true
    }
    
    // NEW: Cancel re-authentication
    private func cancelReauthentication() {
        pendingDeletion = false
        reauthPassword = ""
        reauthEmail = ""
        showReauthenticationAlert = false
    }
    
    // NEW: Re-authenticate user
    private func reauthenticateUser() {
        guard !reauthEmail.isEmpty && !reauthPassword.isEmpty else {
            deleteError = "Please enter your email and password"
            return
        }
        
        isReauthenticating = true
        
        Task {
            do {
                print("🔐 Attempting to re-authenticate user: \(reauthEmail)")
                
                // Create credential
                let credential = EmailAuthProvider.credential(withEmail: reauthEmail, password: reauthPassword)
                
                // Re-authenticate
                try await Auth.auth().currentUser?.reauthenticate(with: credential)
                print("🔐 Re-authentication successful")
                
                await MainActor.run {
                    isReauthenticating = false
                    showReauthenticationAlert = false
                    
                    // Clear password for security
                    reauthPassword = ""
                    
                    // Now retry the deletion
                    if pendingDeletion {
                        deleteAccount()
                    }
                }
                
            } catch {
                await MainActor.run {
                    isReauthenticating = false
                    deleteError = "Re-authentication failed: \(error.localizedDescription)"
                    print("❌ Re-authentication failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteUserDataFromFirestore(_ userId: String) async throws {
        let db = Firestore.firestore()
        let storage = Storage.storage()
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
        
        // NEW: Delete user's sessions
        let userSessions = try await db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for doc in userSessions.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // NEW: Delete user's posts
        let userPosts = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for doc in userPosts.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // NEW: Delete user's parked sessions
        let userParkedSessions = try await db.collection("parkedSessions")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for doc in userParkedSessions.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // NEW: Delete user's public sessions
        let userPublicSessions = try await db.collection("public_sessions")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for doc in userPublicSessions.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // NEW: Delete user's session start notifications
        let userSessionNotifications = try await db.collection("sessionStartNotifications")
            .whereField("playerId", isEqualTo: userId)
            .getDocuments()
        
        for doc in userSessionNotifications.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Commit the batch deletion of Firestore data
        try await batch.commit()
        
        // Delete profile image from Storage (don't let this fail the whole process)
        do {
            try await storage.reference()
                .child("profile_images/\(userId).jpg")
                .delete()
        } catch {
            print("Profile image deletion failed: \(error.localizedDescription)")
        }
        
        // NEW: Delete CSV import files from Storage
        let importFolders = [
            "pokerbaseImports/\(userId)",
            "pokerAnalyticsImports/\(userId)", 
            "pbtImports/\(userId)",
            "regroupImports/\(userId)"
        ]
        
        for folder in importFolders {
            do {
                // List all files in the folder
                let listResult = try await storage.reference().child(folder).listAll()
                
                // Delete each file
                for item in listResult.items {
                    try await item.delete()
                }
                
                print("Deleted CSV imports from \(folder)")
            } catch {
                print("Failed to delete CSV imports from \(folder): \(error.localizedDescription)")
                // Continue with deletion even if some CSV files fail
            }
        }
        
        // NEW: Clear all local cache and UserDefaults
        await clearAllLocalCache(userId: userId)
    }
    
    // NEW: Comprehensive cache clearing function
    private func clearAllLocalCache(userId: String) async {
        await MainActor.run {
            print("🧹 Starting comprehensive cache clearing for user: \(userId)")
            
            // Clear all UserDefaults keys for this user
            let userDefaultsKeys = [
                // Session-related keys
                "LiveSession_\(userId)",
                "EnhancedLiveSession_\(userId)",
                "ParkedSessions_\(userId)",
                "liveSession_\(userId)",
                "enhancedLiveSession_\(userId)",
                "LiveSessionData_\(userId)",
                "SessionStore_\(userId)",
                "ActiveSession_\(userId)",
                "CurrentSession_\(userId)",
                "SessionState_\(userId)",
                
                // Cache keys
                "cached_posts_data",
                "cached_following_users",
                "LastFCMToken",
                
                // Event cache keys (from ExploreView)
                "EventsCache",
                "EventsCacheTimestamp",
                
                // Login count and CSV prompt
                "hasShownCSVPrompt",
                "loginCount"
            ]
            
            // Remove all user-specific keys
            for key in userDefaultsKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            
            // Force synchronize UserDefaults
            UserDefaults.standard.synchronize()
            
            // Clear Kingfisher image cache
            ImageCache.default.clearMemoryCache()
            ImageCache.default.clearDiskCache()
            
            // Clear any additional app-level caches
            URLCache.shared.removeAllCachedResponses()
            
            print("🧹 Cache clearing completed")
        }
    }
}
