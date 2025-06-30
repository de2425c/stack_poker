import SwiftUI
import Foundation

// MARK: - Analytics Filtering Support Types

/// Top–level container holding the current filter selections.
struct AnalyticsFilter: Equatable {
    var gameType: GameTypeFilter = .all
    var stakeLevel: StakeLevelFilter = .all
    var location: String? = nil // nil = all locations
    var sessionLength: SessionLengthFilter = .all
    var customStartDate: Date? = nil
    var customEndDate: Date? = nil
    var showRawProfits: Bool = false // false = staking-adjusted, true = raw profits
    
    var isActive: Bool {
        // Returns true when at least one filter is not `.all` / nil / default
        return gameType != .all || stakeLevel != .all || location != nil ||
               sessionLength != .all || customStartDate != nil || customEndDate != nil || showRawProfits
    }
}

// MARK: Individual Filter Enums
enum GameTypeFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case cash = "Cash Game"
    case tournament = "Tournament"
    var id: String { rawValue }
}

enum StakeLevelFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case micro = "Micro"
    case low = "Low"
    case mid = "Mid"
    case high = "High"
    var id: String { rawValue }
    var display: String {
        switch self {
        case .all: return "All"
        case .micro: return "Micro (<$1/$2)"
        case .low: return "Low ($1/$2–$2/$5)"
        case .mid: return "Mid ($2/$5–$5/$10)"
        case .high: return "High (>$5/$10)"
        }
    }
}

enum SessionLengthFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case under2 = "<2h"
    case twoToFour = "2–4h"
    case over4 = ">4h"
    var id: String { rawValue }
}



// MARK: - AnalyticsFilterSheet

/// A beautiful filter sheet styled with glassy design and AppBackgroundView.
struct AnalyticsFilterSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var filter: AnalyticsFilter
    /// Top 5 most common games derived from sessions – pass in.
    let topGames: [String]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Beautiful background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        Text("Filter Analytics")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        VStack(spacing: 16) {
                            // Staking Adjustment Toggle
                            FilterSection(
                                icon: "person.2.square.stack.fill",
                                title: "Profit Calculation",
                                accentColor: .cyan
                            ) {
                                Toggle(isOn: $filter.showRawProfits) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(filter.showRawProfits ? "Raw Profits" : "Staking-Adjusted Profits")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                        Text(filter.showRawProfits ? 
                                             "Showing session profits without staking adjustments" : 
                                             "Showing session profits adjusted for staking transfers")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                            .lineLimit(2)
                                    }
                                }
                                .tint(.cyan)
                                .toggleStyle(SwitchToggleStyle())
                            }
                            
                            // Game Type Filter
                            FilterSection(
                                icon: "gamecontroller.fill",
                                title: "Game Type",
                                accentColor: .blue
                            ) {
                                SegmentedFilterPicker(
                                    selection: $filter.gameType,
                                    options: GameTypeFilter.allCases
                                ) { option in
                                    Text(option.rawValue)
                                }
                            }
                            
                            // Stake Level Filter
                            FilterSection(
                                icon: "dollarsign.circle.fill",
                                title: "Stake Level",
                                accentColor: .green
                            ) {
                                SegmentedFilterPicker(
                                    selection: $filter.stakeLevel,
                                    options: StakeLevelFilter.allCases
                                ) { option in
                                    Text(option.display)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            
                            // Top Games Filter
                            if !topGames.isEmpty {
                                FilterSection(
                                    icon: "suit.spade.fill",
                                    title: "Game (Top 5)",
                                    accentColor: .purple
                                ) {
                                    GameSelectionView(
                                        selectedGame: Binding(
                                            get: { filter.location ?? "All" },
                                            set: { newVal in
                                                filter.location = newVal == "All" ? nil : newVal
                                            }
                                        ),
                                        availableGames: topGames
                                    )
                                }
                            }
                            
                            // Session Length Filter
                            FilterSection(
                                icon: "clock.fill",
                                title: "Session Length",
                                accentColor: .orange
                            ) {
                                SegmentedFilterPicker(
                                    selection: $filter.sessionLength,
                                    options: SessionLengthFilter.allCases
                                ) { option in
                                    Text(option.rawValue)
                                }
                            }
                            
                            // Custom Date Range Filter
                            FilterSection(
                                icon: "calendar.badge.clock",
                                title: "Date Range",
                                accentColor: .mint
                            ) {
                                VStack(spacing: 12) {
                                    // Start Date
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("From Date")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                        
                                        HStack {
                                            DatePicker(
                                                "",
                                                selection: Binding(
                                                    get: { filter.customStartDate ?? Date() },
                                                    set: { filter.customStartDate = $0 }
                                                ),
                                                displayedComponents: .date
                                            )
                                            .labelsHidden()
                                            .colorScheme(.dark)
                                            
                                            Button(action: {
                                                filter.customStartDate = nil
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white.opacity(0.6))
                                                    .font(.system(size: 16))
                                            }
                                            .opacity(filter.customStartDate != nil ? 1 : 0)
                                        }
                                    }
                                    
                                    // End Date
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("To Date")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                        
                                        HStack {
                                            DatePicker(
                                                "",
                                                selection: Binding(
                                                    get: { filter.customEndDate ?? Date() },
                                                    set: { filter.customEndDate = $0 }
                                                ),
                                                displayedComponents: .date
                                            )
                                            .labelsHidden()
                                            .colorScheme(.dark)
                                            
                                            Button(action: {
                                                filter.customEndDate = nil
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white.opacity(0.6))
                                                    .font(.system(size: 16))
                                            }
                                            .opacity(filter.customEndDate != nil ? 1 : 0)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100) // Extra space for toolbar
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            filter = AnalyticsFilter()
                        }
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { 
                        presentationMode.wrappedValue.dismiss() 
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
                }
            }
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Supporting Views

struct FilterSection<Content: View>: View {
    let icon: String
    let title: String
    let accentColor: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
            }
            
            content()
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.01))
                
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                accentColor.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SegmentedFilterPicker<T: Hashable & CaseIterable & Identifiable, Label: View>: View {
    @Binding var selection: T
    let options: [T]
    @ViewBuilder let label: (T) -> Label
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.id) { option in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selection = option
                        }
                    }) {
                        label(option)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSelected(option) ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected(option) ? Color.white : Color.white.opacity(0.1))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isSelected(option) ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected(option))
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func isSelected(_ option: T) -> Bool {
        return String(describing: selection) == String(describing: option)
    }
}

struct GameSelectionView: View {
    @Binding var selectedGame: String
    let availableGames: [String]
    @State private var isExpanded = false
    
    private var allOptions: [String] {
        ["All"] + availableGames
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Current selection button
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(selectedGame)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded options
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(allOptions, id: \.self) { game in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedGame = game
                                isExpanded = false
                            }
                        }) {
                            HStack {
                                Text(game)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedGame == game ? .white : .white.opacity(0.7))
                                
                                Spacer()
                                
                                if selectedGame == game {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedGame == game ? Color.white.opacity(0.15) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
        }
    }
}

// Previews
#if DEBUG
struct AnalyticsFilterSheet_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsFilterSheet(filter: .constant(AnalyticsFilter()), topGames: ["Bellagio", "Commerce", "Aria", "Wynn", "MGM"])
    }
}
#endif 