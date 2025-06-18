import SwiftUI

struct StakerSearchField: View {
    @Binding var config: StakerConfig
    @ObservedObject var userService: UserService
    @ObservedObject var manualStakerService: ManualStakerService
    
    let userId: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    
    @State private var searchDebounceTimer: Timer?
    @State private var showingSearchResults = false
    @State private var showingCreateManualStaker = false
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Toggle for manual entry
            Toggle(isOn: $config.isManualEntry.animation()) {
                Text("Use Manual Staker")
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 4)

            if config.isManualEntry {
                manualStakerSection
            } else {
                appUserSection
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingSearchResults)
        .animation(.easeInOut(duration: 0.2), value: config.isManualEntry)
        .onAppear {
            // Load manual stakers when view appears
            print("Debug: StakerSearchField onAppear - userId: \(userId)")
            Task {
                try? await manualStakerService.fetchManualStakers(forUser: userId)
            }
        }
        .onChange(of: config.isManualEntry) { isManual in
            if isManual {
                // Refresh manual stakers when switching to manual mode
                print("Debug: Switching to manual mode, fetching stakers for user: \(userId)")
                Task {
                    try? await manualStakerService.fetchManualStakers(forUser: userId)
                    await MainActor.run {
                        print("Debug: After manual mode fetch, manualStakers count: \(manualStakerService.manualStakers.count)")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateManualStaker) {
            CreateManualStakerView(
                isPresented: $showingCreateManualStaker,
                manualStakerService: manualStakerService,
                userId: userId,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                glassOpacity: glassOpacity,
                materialOpacity: materialOpacity
            ) { newProfile in
                // Select the newly created profile
                print("StakerSearchField: Received new profile: \(newProfile.name), ID: \(newProfile.id ?? "nil")")
                config.selectedManualStaker = newProfile
                config.searchQuery = ""
                config.manualStakerSearchResults = []
                showingSearchResults = false
                print("StakerSearchField: Set selectedManualStaker to: \(config.selectedManualStaker?.name ?? "nil"), ID: \(config.selectedManualStaker?.id ?? "nil")")
            }
        }
    }
    
    // MARK: - Manual Staker Section
    @ViewBuilder
    private var manualStakerSection: some View {
        if let selectedManualStaker = config.selectedManualStaker {
            selectedManualStakerView(selectedManualStaker)
        } else {
            manualStakerSearchView
                .onAppear {
                    // Force fetch when manual staker search view appears
                    print("Debug: Manual staker search view appeared, forcing fetch for user: \(userId)")
                    Task {
                        try? await manualStakerService.fetchManualStakers(forUser: userId)
                        await MainActor.run {
                            print("Debug: Manual staker search view fetch complete, count: \(manualStakerService.manualStakers.count)")
                        }
                    }
                }
            
            // Manual staker search results
            if showingSearchResults && !config.manualStakerSearchResults.isEmpty {
                manualStakerResultsView
            }
        }
    }
    
    @ViewBuilder
    private func selectedManualStakerView(_ staker: ManualStakerProfile) -> some View {
        GlassyInputField(
            icon: "person.fill.checkmark",
            title: "Selected Manual Staker",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(primaryTextColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(staker.name.first ?? "?").uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(staker.name)
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    
                    if let contactInfo = staker.contactInfo, !contactInfo.isEmpty {
                        Text(contactInfo)
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    } else {
                        Text("Manual Staker")
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        config.selectedManualStaker = nil
                        config.searchQuery = ""
                        config.manualStakerSearchResults = []
                        showingSearchResults = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var manualStakerSearchView: some View {
        GlassyInputField(
            icon: "magnifyingglass",
            title: "Search Manual Stakers",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 8) {
                TextField("Search existing manual stakers...", text: $config.searchQuery)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .focused($isSearchFocused)
                    .onChange(of: config.searchQuery) { newValue in
                        handleManualStakerSearch(newValue)
                    }
                    .onTapGesture {
                        isSearchFocused = true
                        // Ensure manual stakers are loaded when tapping the search field
                        Task {
                            try? await manualStakerService.fetchManualStakers(forUser: userId)
                            await MainActor.run {
                                // Show all manual stakers when tapping the search field
                                if config.searchQuery.isEmpty {
                                    config.manualStakerSearchResults = manualStakerService.manualStakers.filter { $0.createdByUserId == userId }
                                    print("Debug: Manual stakers for user \(userId): \(config.manualStakerSearchResults.count) found")
                                    print("Debug: All manual stakers: \(manualStakerService.manualStakers.count)")
                                    showingSearchResults = !config.manualStakerSearchResults.isEmpty
                                } else {
                                    handleManualStakerSearch(config.searchQuery)
                                }
                            }
                        }
                    }
                
                if !config.searchQuery.isEmpty {
                    Button(action: {
                        config.searchQuery = ""
                        config.manualStakerSearchResults = []
                        showingSearchResults = false
                        isSearchFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                    }
                }
            }
            .padding(.vertical, 4)
        }
        
        // Create new manual staker button
        Button(action: {
            showingCreateManualStaker = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Create New Manual Staker")
            }
            .font(.plusJakarta(.caption, weight: .semibold))
            .foregroundColor(primaryTextColor.opacity(0.9))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var manualStakerResultsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(config.manualStakerSearchResults.enumerated()), id: \.element.id) { index, profile in
                Button(action: {
                    selectManualStaker(profile)
                }) {
                    HStack(spacing: 12) {
                        // Avatar placeholder
                        Circle()
                            .fill(primaryTextColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(profile.name.first ?? "?").uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(primaryTextColor.opacity(0.8))
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.plusJakarta(.subheadline, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if let contactInfo = profile.contactInfo, !contactInfo.isEmpty {
                                Text(contactInfo)
                                    .font(.plusJakarta(.caption, weight: .regular))
                                    .foregroundColor(secondaryTextColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(secondaryTextColor.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color.white.opacity(index % 2 == 0 ? 0.02 : 0.05)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                if index < config.manualStakerSearchResults.count - 1 {
                    Divider()
                        .background(secondaryTextColor.opacity(0.1))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Material.ultraThinMaterial)
                .opacity(materialOpacity * 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(secondaryTextColor.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - App User Section
    @ViewBuilder
    private var appUserSection: some View {
        if let selectedStaker = config.selectedStaker {
            selectedAppUserView(selectedStaker)
        } else {
            appUserSearchView
            
            // App user search results
            if showingSearchResults && !config.searchResults.isEmpty {
                appUserResultsView
            }
        }
    }
    
    @ViewBuilder
    private func selectedAppUserView(_ staker: UserProfile) -> some View {
        GlassyInputField(
            icon: "person.fill.checkmark",
            title: "Selected App User",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(primaryTextColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(staker.displayName?.first ?? staker.username.first ?? "?").uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(staker.username)")
                        .font(.plusJakarta(.subheadline, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    
                    if let displayName = staker.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        config.selectedStaker = nil
                        config.searchQuery = ""
                        config.searchResults = []
                        showingSearchResults = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var appUserSearchView: some View {
        GlassyInputField(
            icon: "magnifyingglass",
            title: "Search App Users",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 8) {
                TextField("Search by username or name...", text: $config.searchQuery)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .focused($isSearchFocused)
                    .onChange(of: config.searchQuery) { newValue in
                        handleAppUserSearch(newValue)
                    }
                    .onTapGesture {
                        isSearchFocused = true
                        if !config.searchQuery.isEmpty && !config.searchResults.isEmpty {
                            showingSearchResults = true
                        }
                    }
                
                if config.isSearching {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: primaryTextColor))
                        .scaleEffect(0.7)
                } else if !config.searchQuery.isEmpty {
                    Button(action: {
                        config.searchQuery = ""
                        config.searchResults = []
                        showingSearchResults = false
                        isSearchFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var appUserResultsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(config.searchResults.enumerated()), id: \.element.id) { index, userProfile in
                Button(action: {
                    selectAppUser(userProfile)
                }) {
                    HStack(spacing: 12) {
                        // Avatar placeholder
                        Circle()
                            .fill(primaryTextColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(userProfile.displayName?.first ?? userProfile.username.first ?? "?").uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(primaryTextColor.opacity(0.8))
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(userProfile.username)")
                                .font(.plusJakarta(.subheadline, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if let displayName = userProfile.displayName, !displayName.isEmpty {
                                Text(displayName)
                                    .font(.plusJakarta(.caption, weight: .regular))
                                    .foregroundColor(secondaryTextColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(secondaryTextColor.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color.white.opacity(index % 2 == 0 ? 0.02 : 0.05)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                if index < config.searchResults.count - 1 {
                    Divider()
                        .background(secondaryTextColor.opacity(0.1))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Material.ultraThinMaterial)
                .opacity(materialOpacity * 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(secondaryTextColor.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Helper Methods
    
    private func handleManualStakerSearch(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedQuery.isEmpty {
            // Show all manual stakers when search is empty but field is focused
            if isSearchFocused {
                config.manualStakerSearchResults = manualStakerService.manualStakers.filter { $0.createdByUserId == userId }
                showingSearchResults = !config.manualStakerSearchResults.isEmpty
            } else {
                config.manualStakerSearchResults = []
                showingSearchResults = false
            }
            return
        }
        
        config.manualStakerSearchResults = manualStakerService.searchManualStakers(query: trimmedQuery, userId: userId)
        print("Debug: Search for '\(trimmedQuery)' returned \(config.manualStakerSearchResults.count) results")
        showingSearchResults = !config.manualStakerSearchResults.isEmpty
    }
    
    private func handleAppUserSearch(_ newValue: String) {
        searchDebounceTimer?.invalidate()
        
        if newValue.isEmpty {
            config.searchResults = []
            config.isSearching = false
            showingSearchResults = false
            return
        }
        
        // Clear previous results immediately for better UX
        if newValue.count == 1 {
            config.searchResults = []
        }
        
        config.isSearching = true
        showingSearchResults = true
        
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            performAppUserSearch(currentQuery: newValue)
        }
    }
    
    private func performAppUserSearch(currentQuery: String) {
        let query = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            config.searchResults = []
            config.isSearching = false
            showingSearchResults = false
            return
        }
        
        Task {
            do {
                let users = try await userService.searchUsers(query: query, limit: 5)
                await MainActor.run {
                    if config.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(query.lowercased()) {
                        config.searchResults = users
                        showingSearchResults = !users.isEmpty
                    }
                    config.isSearching = false
                }
            } catch {
                await MainActor.run {
                    config.searchResults = []
                    config.isSearching = false
                    showingSearchResults = false
                }
            }
        }
    }
    
    private func selectManualStaker(_ profile: ManualStakerProfile) {
        withAnimation(.easeInOut(duration: 0.3)) {
            config.selectedManualStaker = profile
            config.searchQuery = ""
            config.manualStakerSearchResults = []
            showingSearchResults = false
            isSearchFocused = false
        }
        
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func selectAppUser(_ userProfile: UserProfile) {
        withAnimation(.easeInOut(duration: 0.3)) {
            config.selectedStaker = userProfile
            config.searchQuery = ""
            config.searchResults = []
            showingSearchResults = false
            isSearchFocused = false
        }
        
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
} 