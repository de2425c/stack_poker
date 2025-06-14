import SwiftUI

struct StakerSearchField: View {
    @Binding var config: StakerConfig
    @ObservedObject var userService: UserService
    
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    
    @State private var searchDebounceTimer: Timer?
    @State private var showingSearchResults = false
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Toggle for manual entry
            Toggle(isOn: $config.isManualEntry.animation()) {
                Text("Enter Staker Manually")
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 4)

            if config.isManualEntry {
                manualEntryField
            } else {
                // Search field with selected user display
                if let selectedStaker = config.selectedStaker {
                    // Show selected staker with option to change
                    selectedStakerView(selectedStaker)
                } else {
                    // Show search field
                    searchFieldView
                }
                
                // Search results overlay
                if showingSearchResults && !config.searchResults.isEmpty {
                    searchResultsView
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingSearchResults)
        .animation(.easeInOut(duration: 0.2), value: config.isManualEntry)
    }
    
    @ViewBuilder
    private var manualEntryField: some View {
        GlassyInputField(
            icon: "person.fill.badge.plus",
            title: "Manual Staker Name",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 8) {
                TextField("Enter staker's name...", text: $config.manualStakerName)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .focused($isSearchFocused)
                
                if !config.manualStakerName.isEmpty {
                    Button(action: {
                        config.manualStakerName = ""
                        isSearchFocused = false // Optionally dismiss focus
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
    private func selectedStakerView(_ staker: UserProfile) -> some View {
        GlassyInputField(
            icon: "person.fill.checkmark",
            title: "Selected Staker",
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
    private var searchFieldView: some View {
        GlassyInputField(
            icon: "magnifyingglass",
            title: "Search for Staker by Name or Username",
            glassOpacity: glassOpacity,
            labelColor: secondaryTextColor,
            materialOpacity: materialOpacity
        ) {
            HStack(spacing: 8) {
                TextField("Enter username or display name...", text: $config.searchQuery)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .focused($isSearchFocused)
                    .onChange(of: config.searchQuery) { newValue in
                        handleSearchQueryChange(newValue)
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
    private var searchResultsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(config.searchResults.enumerated()), id: \.element.id) { index, userProfile in
                Button(action: {
                    selectStaker(userProfile)
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
    
    private func handleSearchQueryChange(_ newValue: String) {
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
            performStakerSearch(currentQuery: newValue)
        }
    }
    
    private func performStakerSearch(currentQuery: String) {
        let query = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            config.searchResults = []
            config.isSearching = false
            showingSearchResults = false
            return
        }
        
        Task {
            do {
                // Use the comprehensive search that searches both username and displayName
                let users = try await userService.searchUsers(query: query, limit: 5)
                await MainActor.run {
                    // Only update if the search query hasn't changed
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
    
    private func selectStaker(_ userProfile: UserProfile) {
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