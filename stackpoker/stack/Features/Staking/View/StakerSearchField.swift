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
    
    // Local state for search query and results
    @State private var localSearchQuery: String = ""
    @State private var localSearchResults: [UserProfile] = []
    
    // Manual staker loading state
    @State private var isLoadingManualStakers = false
    
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
            // Only fetch if we don't already have manual stakers
            if manualStakerService.manualStakers.isEmpty {
                Task {
                    isLoadingManualStakers = true
                    try? await manualStakerService.fetchManualStakers(forUser: userId)
                    isLoadingManualStakers = false
                }
            }
        }
        .onChange(of: config.isManualEntry) { isManual in
            if isManual && manualStakerService.manualStakers.isEmpty {
                Task {
                    isLoadingManualStakers = true
                    try? await manualStakerService.fetchManualStakers(forUser: userId)
                    isLoadingManualStakers = false
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
                config.selectedManualStaker = newProfile
                config.searchQuery = ""
                config.manualStakerSearchResults = []
                showingSearchResults = false
            }
        }
    }
    
    // MARK: - Manual Staker Section
    @ViewBuilder
    private var manualStakerSection: some View {
        if let selectedManualStaker = config.selectedManualStaker {
            selectedManualStakerView(selectedManualStaker)
        } else {
            manualStakerListView
                .onAppear {
                    if manualStakerService.manualStakers.isEmpty {
                        Task {
                            isLoadingManualStakers = true
                            try? await manualStakerService.fetchManualStakers(forUser: userId)
                            isLoadingManualStakers = false
                        }
                    }
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
    private var manualStakerListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            GlassyInputField(
                icon: "person.2.fill",
                title: "Select Manual Staker",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                EmptyView()
            }
            
            // Loading state
            if isLoadingManualStakers {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: primaryTextColor))
                        .scaleEffect(0.8)
                    Text("Loading manual stakers...")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
            } else {
                // Manual stakers list
                let userManualStakers = manualStakerService.manualStakers.filter { $0.createdByUserId == userId }
                
                if userManualStakers.isEmpty {
                    VStack(spacing: 8) {
                        Text("No manual stakers yet")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                        Text("Create your first manual staker below")
                            .font(.plusJakarta(.caption, weight: .regular))
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                } else {
                    // List of manual stakers
                    VStack(spacing: 0) {
                        ForEach(Array(userManualStakers.enumerated()), id: \.element.id) { index, profile in
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
                            
                            if index < userManualStakers.count - 1 {
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
        }
    }
    

    
    // MARK: - App User Section
    @ViewBuilder
    private var appUserSection: some View {
        if let selectedStaker = config.selectedStaker {
            selectedAppUserView(selectedStaker)
        } else {
            appUserSearchView
            
            // App user search results
            if showingSearchResults && !localSearchResults.isEmpty {
                appUserResultsView
            } else if config.isSearching && !localSearchQuery.isEmpty {
                // Show searching indicator
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: primaryTextColor))
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
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
                        localSearchQuery = ""
                        config.searchQuery = ""
                        localSearchResults = []
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
                TextField("Search by username or name...", text: $localSearchQuery)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .focused($isSearchFocused)
                    .onChange(of: localSearchQuery) { newValue in
                        config.searchQuery = newValue
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
                } else if !localSearchQuery.isEmpty {
                    Button(action: {
                        localSearchQuery = ""
                        config.searchQuery = ""
                        localSearchResults = []
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
            ForEach(Array(localSearchResults.enumerated()), id: \.element.id) { index, userProfile in
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
                
                if index < localSearchResults.count - 1 {
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
    

    
    private func handleAppUserSearch(_ newValue: String) {
        searchDebounceTimer?.invalidate()
        
        if newValue.isEmpty {
            localSearchResults = []
            config.searchResults = []
            config.isSearching = false
            showingSearchResults = false
            return
        }
        
        // Clear previous results immediately for better UX
        if newValue.count == 1 {
            localSearchResults = []
            config.searchResults = []
        }
        
        config.isSearching = true
        showingSearchResults = true
        
        // Optimized debounce time for faster response
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
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
                // Optimized search with smaller limit for faster response
                let users = try await userService.searchUsers(query: query, limit: 8)
                
                await MainActor.run {
                    let currentSearchQuery = localSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let searchQuery = query.lowercased()
                    
                    // Only update results if the search query hasn't changed since we started this search
                    if currentSearchQuery == searchQuery {
                        localSearchResults = users
                        config.searchResults = users
                        showingSearchResults = !users.isEmpty
                    }
                    config.isSearching = false
                }
            } catch {
                await MainActor.run {
                    localSearchResults = []
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
        }
    }
    
    private func selectAppUser(_ userProfile: UserProfile) {
        withAnimation(.easeInOut(duration: 0.3)) {
            config.selectedStaker = userProfile
            localSearchQuery = ""
            config.searchQuery = ""
            localSearchResults = []
            config.searchResults = []
            showingSearchResults = false
            isSearchFocused = false
        }
        
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
} 