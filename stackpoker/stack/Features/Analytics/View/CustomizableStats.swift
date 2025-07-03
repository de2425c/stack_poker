import SwiftUI
import SwiftUIReorderableForEach

// MARK: - Performance Stat Enum
enum PerformanceStat: String, CaseIterable, Identifiable, Equatable {
    case avgProfit = "avg_profit"
    case bestSession = "best_session"
    case sessions = "sessions"
    case hours = "hours"
    case avgSessionLength = "avg_length"
    case dollarPerHour = "dollar_per_hour"
    case bbPerHour = "bb_per_hour"
    case longestWinStreak = "longest_win_streak"
    case longestLoseStreak = "longest_lose_streak"
    case bestLocation = "best_location"
    case bestStake = "best_stake"
    case standardDeviation = "standard_deviation"
    case tournamentROI = "tournament_roi"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .avgProfit: return "Avg. Profit"
        case .bestSession: return "Best Session"
        case .sessions: return "Total Sessions"
        case .hours: return "Total Hours"
        case .avgSessionLength: return "Avg. Hours"
        case .dollarPerHour: return "$/Hour"
        case .bbPerHour: return "BB/Hour"
        case .longestWinStreak: return "Win Streak"
        case .longestLoseStreak: return "Lose Streak"
        case .bestLocation: return "Best Location"
        case .bestStake: return "Best Stake"
        case .standardDeviation: return "Std. Deviation"
        case .tournamentROI: return "Tourney ROI"
        }
    }
    
    var iconName: String {
        switch self {
        case .avgProfit: return "dollarsign.circle.fill"
        case .bestSession: return "star.fill"
        case .sessions: return "list.star"
        case .hours: return "clock.fill"
        case .avgSessionLength: return "timer"
        case .dollarPerHour: return "chart.line.uptrend.xyaxis"
        case .bbPerHour: return "speedometer"
        case .longestWinStreak: return "flame.fill"
        case .longestLoseStreak: return "thermometer.snowflake"
        case .bestLocation: return "mappin.and.ellipse"
        case .bestStake: return "target"
        case .standardDeviation: return "waveform.path"
        case .tournamentROI: return "percent"
        }
    }
    
    var color: Color {
        switch self {
        case .avgProfit: return .green
        case .bestSession: return .yellow
        case .sessions: return .orange
        case .hours: return .purple
        case .avgSessionLength: return .pink
        case .dollarPerHour: return .mint
        case .bbPerHour: return .teal
        case .longestWinStreak: return .red
        case .longestLoseStreak: return .blue
        case .bestLocation: return .cyan
        case .bestStake: return .indigo
        case .standardDeviation: return .brown
        case .tournamentROI: return .gray
        }
    }
}



// MARK: - Customize Stats View
struct CustomizeStatsView: View {
    @Binding var selectedStats: [PerformanceStat]
    @Binding var isDraggingAny: Bool
    
    @State private var allowReordering = true
    @State private var combinedItems: [StatItem] = []
    @State private var isUpdatingFromDrag = false
    
    private var availableStats: [PerformanceStat] {
        PerformanceStat.allCases.filter { !selectedStats.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Selected Stats Section Header
            HStack {
                Text("Selected Stats")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("\(selectedStats.count)/\(PerformanceStat.allCases.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            
            // Combined Reorderable List with Visual Sections
            VStack(spacing: 8) {
                ReorderableForEach($combinedItems, allowReordering: $allowReordering) { item, isDragged in
                    Group {
                        if item.isHeader {
                            // Section header
                            HStack {
                                Text(item.headerTitle ?? "")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, item.headerTitle == "Available Stats" ? 16 : 0)
                        } else if let stat = item.stat {
                            // Stat card
                            ReorderableStatCard(
                                stat: stat,
                                isSelected: item.isSelected,
                                isDragged: isDragged,
                                onTap: {
                                    withAnimation(.spring()) {
                                        if item.isSelected {
                                            selectedStats.removeAll { $0 == stat }
                                            print("🔴 Removed \(stat.title), now selected: \(selectedStats.map(\.title))")
                                        } else {
                                            selectedStats.append(stat)
                                            print("🟢 Added \(stat.title), now selected: \(selectedStats.map(\.title))")
                                        }
                                        updateCombinedItems()
                                    }
                                }
                            )
                        } else {
                            // Empty state
                            Text(item.emptyMessage ?? "")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                )
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .onAppear {
            updateCombinedItems()
        }
        .onChange(of: selectedStats) { newStats in
            guard !isUpdatingFromDrag else { return }
            isDraggingAny = false
            updateCombinedItems()
        }
        .onChange(of: combinedItems) { newItems in
            // When items are reordered via drag, update selectedStats
            let newSelectedStats = newItems.compactMap { item -> PerformanceStat? in
                if let stat = item.stat {
                    // Check if this stat is in the "selected" section (before "Available Stats" header)
                    if let availableHeaderIndex = newItems.firstIndex(where: { $0.headerTitle == "Available Stats" }),
                       let statIndex = newItems.firstIndex(where: { $0.stat?.id == stat.id }),
                       statIndex < availableHeaderIndex {
                        return stat
                    }
                }
                return nil
            }
            
            // Only update if different to avoid infinite loop
            if newSelectedStats.map(\.id) != selectedStats.map(\.id) {
                isUpdatingFromDrag = true
                selectedStats = newSelectedStats
                print("🔄 Reordered via drag, now selected: \(newSelectedStats.map(\.title))")
                
                // Reset flag after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isUpdatingFromDrag = false
                }
            }
        }
    }
    
    private func updateCombinedItems() {
        var newItems: [StatItem] = []
        
        // Selected Stats Section
        if selectedStats.isEmpty {
            newItems.append(StatItem(emptyMessage: "Drag stats here to display them"))
        } else {
            for stat in selectedStats {
                newItems.append(StatItem(stat: stat, isSelected: true))
            }
        }
        
        // Available Stats Section Header
        newItems.append(StatItem(headerTitle: "Available Stats"))
        
        // Available Stats
        if availableStats.isEmpty {
            newItems.append(StatItem(emptyMessage: "All stats are currently selected"))
        } else {
            for stat in availableStats {
                newItems.append(StatItem(stat: stat, isSelected: false))
            }
        }
        
        combinedItems = newItems
    }
}

// MARK: - StatItem for Combined List
struct StatItem: Identifiable, Hashable {
    let id = UUID()
    let stat: PerformanceStat?
    let isSelected: Bool
    let isHeader: Bool
    let headerTitle: String?
    let emptyMessage: String?
    
    init(stat: PerformanceStat, isSelected: Bool) {
        self.stat = stat
        self.isSelected = isSelected
        self.isHeader = false
        self.headerTitle = nil
        self.emptyMessage = nil
    }
    
    init(headerTitle: String) {
        self.stat = nil
        self.isSelected = false
        self.isHeader = true
        self.headerTitle = headerTitle
        self.emptyMessage = nil
    }
    
    init(emptyMessage: String) {
        self.stat = nil
        self.isSelected = false
        self.isHeader = false
        self.headerTitle = nil
        self.emptyMessage = emptyMessage
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: StatItem, rhs: StatItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Stat Display Card (Main View) - Clean minimal design
struct StatDisplayCard: View {
    let stat: PerformanceStat
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon at top left
            HStack {
                Image(systemName: stat.iconName)
                    .font(.plusJakarta(.body, weight: .medium))
                    .foregroundColor(stat.color.opacity(0.8))
                    .frame(width: 20, height: 20)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            
            Spacer()
            
            // Main value left aligned
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.plusJakarta(.title2, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                
                // Title below value
                Text(stat.title)
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(height: 110) // Smaller height for 3-column layout
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Ultra-transparent glassy background like carousel
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.08)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.02))
                
                // Subtle border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Reorderable Stat Card Component
struct ReorderableStatCard: View {
    let stat: PerformanceStat
    let isSelected: Bool
    let isDragged: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle (only for selected stats)
            if isSelected {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
                    .frame(width: 20)
            }
            
            // Icon
            Image(systemName: stat.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(stat.color)
                .frame(width: 20)
            
            // Title
            Text(stat.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Action button
            Button(action: onTap) {
                Image(systemName: isSelected ? "xmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? .red : .green)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill((isSelected ? Color.red : Color.green).opacity(0.15))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDragged ? Color.black.opacity(0.3) : Color.black.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isDragged ? stat.color.opacity(0.5) : Color.gray.opacity(0.2), 
                            lineWidth: isDragged ? 2 : 1
                        )
                )
        )
        .scaleEffect(isDragged ? 1.05 : 1.0)
        .shadow(color: isDragged ? Color.black.opacity(0.3) : Color.clear, radius: isDragged ? 8 : 0, y: isDragged ? 4 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragged)
    }
}
