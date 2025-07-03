import SwiftUI

struct HighlightsSection: View {
    @ObservedObject var viewModel: AnalyticsViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // Section Header
            Text("HIGHLIGHTS")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            
            // STEP 1: Calculate proper height based on screen width
            // Formula: ~50pt padding + (6/3)y + y = screen_width = ~50pt + 3y
            // Solving: y = (screen_width - 50) / 3
            let screenWidth = UIScreen.main.bounds.width
            let squareSize: CGFloat = (screenWidth - 50) / 3
            
            // STEP 2: Carousel width is 6/3 (=2) times the square size for 60% screen
            let carouselWidth: CGFloat = 2.0 * squareSize
            
            // STEP 3: Carousel content height matches square size (excluding page indicators)
            let carouselContentHeight: CGFloat = squareSize
            
            // Main content row - carousel and win rate with same height
            HStack(spacing: 20) {
                // Carousel content only (no page indicators)
                TabView(selection: $viewModel.selectedCarouselIndex) {
                    ForEach(carouselHighlights.indices, id: \.self) { index in
                        let highlight = carouselHighlights[index]
                        
                        VStack(alignment: .leading, spacing: 12) {
                            // Header
                            HStack(spacing: 10) {
                                Image(systemName: highlight.iconName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(highlight.type == .multiplier ? .orange : (highlight.type == .persona ? .cyan : .pink))
                                    .frame(width: 28, height: 28)
                                
                                Text(highlight.title)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Spacer()
                            }
                            
                            // Primary content
                            Text(highlight.primaryText)
                                .font(.system(size: highlight.type == .multiplier ? 38 : 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            
                            // Secondary and tertiary content - for multiplier, show buy-in and cashout adjacent
                            if highlight.type == .multiplier {
                                if let secondaryText = highlight.secondaryText, let tertiaryText = highlight.tertiaryText {
                                    HStack(spacing: 12) {
                                        Text(secondaryText)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.white.opacity(0.75))
                                        Text(tertiaryText)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                }
                            } else {
                                // For other types, show normally
                                if let secondaryText = highlight.secondaryText {
                                    Text(secondaryText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.75))
                                }
                                
                                if let tertiaryText = highlight.tertiaryText {
                                    Text(tertiaryText)
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                        .foregroundColor(.white.opacity(0.65))
                                }
                            }
                            
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: carouselContentHeight * 0.15)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.08)
                                
                                RoundedRectangle(cornerRadius: carouselContentHeight * 0.15)
                                    .fill(Color.white.opacity(0.02))
                                
                                RoundedRectangle(cornerRadius: carouselContentHeight * 0.15)
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
                        .clipShape(RoundedRectangle(cornerRadius: carouselContentHeight * 0.15))
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(width: carouselWidth, height: carouselContentHeight)
                .clipShape(RoundedRectangle(cornerRadius: carouselContentHeight * 0.15))
                
                // Win-rate square (height = width = carousel height)
                WinRateCard(winRate: viewModel.winRate)
                    .frame(width: squareSize, height: squareSize)
            }
            
            // Page indicators below the main content
            if carouselHighlights.count > 1 {
                HStack {
                    // Spacer to center indicators under carousel
                    HStack(spacing: 7) {
                        ForEach(carouselHighlights.indices, id: \.self) { index in
                            Capsule()
                                .fill(viewModel.selectedCarouselIndex == index ? Color.white.opacity(0.85) : Color.white.opacity(0.3))
                                .frame(width: viewModel.selectedCarouselIndex == index ? 20 : 7, height: 7)
                                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: viewModel.selectedCarouselIndex)
                        }
                    }
                    .frame(width: carouselWidth)
                    
                    Spacer()
                }
            }
        }
        .frame(height: (UIScreen.main.bounds.width - 50) / 3 + 20) // Dynamic height + small buffer
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - Computed Properties
    
    @MainActor
    private var carouselHighlights: [CarouselHighlight] {
        var items: [CarouselHighlight] = []
        
        // Top Location (Hot Spot) - FIRST
        if let locData = topLocation {
            items.append(CarouselHighlight(
                type: .location,
                title: "Hot Spot",
                iconName: "mappin.and.ellipse",
                primaryText: locData.location,
                secondaryText: "Played \(locData.count) times",
                tertiaryText: nil
            ))
        }
        
        // Best Multiplier
        if let ratioData = highestCashoutToBuyInRatio {
            items.append(CarouselHighlight(
                type: .multiplier,
                title: "Best Multiplier",
                iconName: "flame.fill",
                primaryText: String(format: "%.1fx", ratioData.ratio),
                secondaryText: "Buy-in: $\(Int(ratioData.session.buyIn).formattedWithCommas)",
                tertiaryText: "Cash-out: $\(Int(ratioData.session.cashout).formattedWithCommas)"
            ))
        }
        
        // Poker Persona
        items.append(CarouselHighlight(
            type: .persona,
            title: "Your Style",
            iconName: pokerPersona.category.icon,
            primaryText: pokerPersona.category.rawValue,
            secondaryText: pokerPersona.dominantHours,
            tertiaryText: nil
        ))
        
        return items.filter { !$0.primaryText.isEmpty || $0.type == .persona }
    }
    
    @MainActor
    private var highestCashoutToBuyInRatio: (ratio: Double, session: Session)? {
        guard !viewModel.filteredSessions.isEmpty else { return nil }
        
        var maxRatio: Double = 0
        var sessionWithMaxRatio: Session? = nil
        
        for session in viewModel.filteredSessions {
            if session.buyIn > 0 { // Avoid division by zero
                let ratio = session.cashout / session.buyIn
                if ratio > maxRatio {
                    maxRatio = ratio
                    sessionWithMaxRatio = session
                }
            }
        }
        
        if let session = sessionWithMaxRatio {
            return (maxRatio, session)
        }
        return nil
    }
    
    @MainActor
    private var pokerPersona: (category: TimeOfDayCategory, dominantHours: String) {
        guard !viewModel.filteredSessions.isEmpty else {
            return (.unknown, "N/A")
        }
        
        var morningSessions = 0 // 5 AM - 11:59 AM
        var afternoonSessions = 0 // 12 PM - 4:59 PM
        var eveningSessions = 0   // 5 PM - 8:59 PM
        var nightSessions = 0     // 9 PM - 4:59 AM
        
        let calendar = Calendar.current
        for session in viewModel.filteredSessions {
            let hour = calendar.component(.hour, from: session.startTime)
            switch hour {
            case 5..<12: morningSessions += 1
            case 12..<17: afternoonSessions += 1
            case 17..<21: eveningSessions += 1
            case 21..<24, 0..<5: nightSessions += 1
            default: break
            }
        }
        
        let totalPlaySessions = Double(morningSessions + afternoonSessions + eveningSessions + nightSessions)
        if totalPlaySessions == 0 { return (.unknown, "N/A")}
        
        var persona: TimeOfDayCategory = .unknown
        var maxCount = 0
        var dominantPeriodName = "N/A"
        
        if morningSessions > maxCount { maxCount = morningSessions; persona = .morning; dominantPeriodName = "Morning" }
        if afternoonSessions > maxCount { maxCount = afternoonSessions; persona = .afternoon; dominantPeriodName = "Afternoon"}
        if eveningSessions > maxCount { maxCount = eveningSessions; persona = .evening; dominantPeriodName = "Evening" }
        if nightSessions > maxCount { maxCount = nightSessions; persona = .night; dominantPeriodName = "Night"}
        
        let percentage = (Double(maxCount) / totalPlaySessions * 100)
        let dominantHoursString = "\(dominantPeriodName): \(String(format: "%.0f%%", percentage))"
        
        return (persona, dominantHoursString)
    }
    
    @MainActor
    private var topLocation: (location: String, count: Int)? {
        guard !viewModel.filteredSessions.isEmpty else { return nil }
        
        let locationStrings = viewModel.filteredSessions.map { displayLocation(for: $0) }
        let locationCounts = locationStrings.reduce(into: [String: Int]()) { counts, loc in
            counts[loc, default: 0] += 1
        }
        guard let (loc, cnt) = locationCounts.max(by: { $0.value < $1.value }) else { return nil }
        return (loc, cnt)
    }
    
    // Helper: unified display string for location / game & stakes
    private func displayLocation(for session: Session) -> String {
        if session.gameType.lowercased().contains("cash") {
            // e.g. "PokerStars $1/$2"
            return "\(session.gameName) \(session.stakes)".trimmingCharacters(in: .whitespaces)
        }
        // tournaments – use location if available otherwise series/gameName
        return (session.location ?? session.gameName).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Supporting Types

private struct CarouselHighlight: Identifiable {
    let id = UUID()
    let type: HighlightType
    var title: String
    var iconName: String
    var primaryText: String
    var secondaryText: String?
    var tertiaryText: String?
}

private enum HighlightType {
    case multiplier, persona, location
}

enum TimeOfDayCategory: String, CaseIterable {
    case morning = "Morning Pro" // 5 AM - 12 PM
    case afternoon = "Afternoon Grinder" // 12 PM - 5 PM
    case evening = "Evening Shark" // 5 PM - 9 PM
    case night = "Night Owl" // 9 PM - 5 AM
    case unknown = "Versatile Player"
    
    var icon: String {
        switch self {
        case .morning: return "sun.max.fill"
        case .afternoon: return "cloud.sun.fill"
        case .evening: return "moon.stars.fill"
        case .night: return "zzz"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

