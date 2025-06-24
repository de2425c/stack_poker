import SwiftUI
import FirebaseFirestore
import Combine
import FirebaseAuth

// MARK: - Tab Selection Enum
enum EventsTab: String, CaseIterable {
    case events = "Events"
    case myEvents = "My Events"
}

// --- New SimpleDate Structures ---
struct SimpleDate: Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init?(from dateString: String) {
        let components = dateString.split(separator: "-").map { String($0) }
        guard components.count == 3,
              let y = Int(components[0]),
              let m = Int(components[1]),
              let d = Int(components[2]) else {
            // print("Error: Could not parse SimpleDate from string: \(dateString)")
            return nil
        }
        // Basic validation for month and day ranges
        guard (1...12).contains(m) && (1...31).contains(d) else {
            // print("Error: Invalid month or day in SimpleDate from string: \(dateString)")
            return nil
        }
        self.year = y
        self.month = m
        self.day = d
    }

    init(year: Int, month: Int, day: Int) {
        // Basic validation for month and day ranges can be added if necessary,
        // but components from Calendar should be valid.
        self.year = year
        self.month = month
        self.day = day
    }

    // For Comparable conformance (chronological order)
    static func < (lhs: SimpleDate, rhs: SimpleDate) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        if lhs.month != rhs.month {
            return lhs.month < rhs.month
        }
        return lhs.day < rhs.day
    }

    // Helper to get month name (short)
    private func monthNameShort() -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard month >= 1 && month <= 12 else { return "Unk" }
        return months[month - 1]
    }

    var displayMedium: String { // e.g., "May 24, 2025"
        return "\(monthNameShort()) \(day), \(year)"
    }
    
    var displayShort: String { // e.g., "May 24"
        return "\(monthNameShort()) \(day)"
    }
}

struct IdentifiableSimpleDate: Identifiable, Hashable {
    let id = UUID()
    let simpleDate: SimpleDate

    func hash(into hasher: inout Hasher) {
        hasher.combine(simpleDate)
    }

    static func == (lhs: IdentifiableSimpleDate, rhs: IdentifiableSimpleDate) -> Bool {
        lhs.simpleDate == rhs.simpleDate
    }
}
// --- End SimpleDate Structures ---

// --- New BuyinRange Enum ---
enum BuyinRange: String, CaseIterable, Identifiable {
    case all = "All Buy-ins"
    case range0_500 = "$0 - $500"
    case range500_1500 = "$500 - $1,500"
    case range1500_5000 = "$1,500 - $5,000"
    case range5000plus = "$5,000+"

    var id: String { self.rawValue }

    // Helper to check if a numeric buy-in falls into this range
    func contains(_ value: Double) -> Bool {
        switch self {
        case .all:
            return true
        case .range0_500:
            return value >= 0 && value <= 500
        case .range500_1500:
            return value > 500 && value <= 1500
        case .range1500_5000:
            return value > 1500 && value <= 5000
        case .range5000plus:
            return value > 5000
        }
    }
}
// --- End BuyinRange Enum ---

// MARK: - Cached Event Model
struct CachedEvent: Codable {
    let id: String
    let buyin_string: String
    let date: String
    let event_name: String
    let series_name: String?
    let description: String?
    let time: String?
    let buyin_usd: Double?
    let casino: String?
}

// Old IdentifiableDate struct removed (was lines 4-16)

// 1. Event Model (Updated for enhanced_events collection)
struct Event: Identifiable, Hashable {
    let id: String 
    let buyin_string: String
    let simpleDate: SimpleDate
    let event_name: String
    let series_name: String?
    let description: String?
    let time: String?
    let buyin_usd: Double? // New field for USD buy-in
    let casino: String? // New optional casino field

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard let docId = Optional(document.documentID), !docId.isEmpty else {
            return nil
        }
        self.id = docId

        guard let buyinStr = data["buyin_string"] as? String, !buyinStr.isEmpty else { 
            return nil 
        }
        self.buyin_string = buyinStr

        guard let dateStringFromFirestore = data["date"] as? String,
              let parsedSimpleDate = SimpleDate(from: dateStringFromFirestore) else { 
            return nil
        }
        self.simpleDate = parsedSimpleDate

        guard let eventNameStr = data["event_name"] as? String, !eventNameStr.isEmpty else { 
            return nil
        }
        self.event_name = eventNameStr

        // Optional fields
        self.series_name = data["series_name"] as? String
        self.description = data["description"] as? String
        self.buyin_usd = data["buyin_usd"] as? Double // Initialize new field

        // Optional casino field
        self.casino = data["casino"] as? String

        let timeValue = data["time"] as? String
        if let t = timeValue, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.time = t
        } else {
            self.time = nil
        }
    }
    
    // Manual initializer for creating events from RSVP data
    init(id: String, buyin_string: String, simpleDate: SimpleDate, event_name: String, series_name: String? = nil, description: String? = nil, time: String? = nil, buyin_usd: Double? = nil, casino: String? = nil) {
        self.id = id
        self.buyin_string = buyin_string
        self.simpleDate = simpleDate
        self.event_name = event_name
        self.series_name = series_name
        self.description = description
        self.time = time
        self.buyin_usd = buyin_usd
        self.casino = casino
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var labelFont: Font = .system(size: 12, weight: .medium, design: .rounded)
    var valueFont: Font = .system(size: 14, weight: .regular, design: .rounded)
    var labelColor: Color = .gray.opacity(0.8)
    var valueColor: Color = .white
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(labelFont)
                .foregroundColor(labelColor)
            Text(value)
                .font(valueFont)
                .foregroundColor(valueColor)
                .lineLimit(alignment == .leading ? 2 : 1)
        }
    }
}

// MARK: - Series Card View
struct SeriesCardView: View {
    let seriesName: String
    let eventCount: Int
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Series Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                    Color(red: 100/255, green: 180/255, blue: 255/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    // Use different icons for different series types
                    Image(systemName: iconForSeries(seriesName))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                
                // Series Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(seriesName)
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.01)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForSeries(_ seriesName: String) -> String {
        let lowercased = seriesName.lowercased()
        
        if lowercased.contains("wsop") || lowercased.contains("world series") {
            return "crown"
        } else if lowercased.contains("wpt") || lowercased.contains("world poker") {
            return "globe"
        } else if lowercased.contains("circuit") {
            return "repeat"
        } else if lowercased.contains("daily") || lowercased.contains("regular") {
            return "calendar"
        } else if lowercased.contains("tournament") {
            return "trophy"
        } else if lowercased.contains("other") {
            return "folder"
        } else {
            return "suit.spade"
        }
    }
}

class ExploreViewModel: ObservableObject {
    @Published var allEvents: [Event] = []
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var loadingMessage: String = ""
    @Published var errorMessage: String? = nil
    
    // --- Updated Filter Properties (removed country/state) ---
    @Published var selectedSeriesSet: Set<String> = [] // For multi-select series
    @Published var selectedBuyinRange: BuyinRange = .all // Property for buy-in range
    @Published var availableSeries: [String] = [] // Property for available series
    // --- End Updated Filter Properties ---
    
    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>() // For observing changes
    
    // MARK: - Caching Properties
    private let cacheKey = "cached_enhanced_events"
    private let cacheTimestampKey = "cached_events_timestamp"
    private let cacheExpiryHours: TimeInterval = 6 // Cache expires after 6 hours
    
    // MARK: - Performance Properties
    private var updateSeriesWorkItem: DispatchWorkItem?

    init() {
        // Observe changes to allEvents to update series list with debouncing
        $allEvents
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAvailableSeries()
            }
            .store(in: &cancellables)
    }

    private func updateAvailableSeries() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            let events = await MainActor.run { self.allEvents }
            
            guard !events.isEmpty else {
                await MainActor.run {
                    self.availableSeries = []
                }
                return
            }

            var seriesCounts: [String: Int] = [:]
            for event in events {
                if let series = event.series_name, !series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    seriesCounts[series, default: 0] += 1
                }
            }

            // Sort series: by count (descending), then alphabetically for ties
            let sortedSeries = seriesCounts.sorted { (item1, item2) -> Bool in
                if item1.value != item2.value {
                    return item1.value > item2.value // Higher count first
                }
                return item1.key < item2.key // Alphabetical for ties
            }.map { $0.key }

            await MainActor.run {
                self.availableSeries = sortedSeries
                
                // If current selectedSeriesSet contains series no longer available, remove them
                let validSeries = Set(self.availableSeries)
                self.selectedSeriesSet = self.selectedSeriesSet.filter { validSeries.contains($0) }
            }
        }
    }

    // MARK: - Caching Methods
    
    private func loadCachedEvents() async -> [Event]? {
        return await withCheckedContinuation { continuation in
            Task.detached {
                guard let timestamp = UserDefaults.standard.object(forKey: self.cacheTimestampKey) as? Date else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Check if cache is still valid (within expiry time)
                let timeElapsed = Date().timeIntervalSince(timestamp)
                if timeElapsed > (self.cacheExpiryHours * 3600) {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Load cached data
                guard let cachedData = UserDefaults.standard.data(forKey: self.cacheKey) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let cachedEvents = try JSONDecoder().decode([CachedEvent].self, from: cachedData)
                    let events = cachedEvents.compactMap { cachedEvent in
                        Event(
                            id: cachedEvent.id,
                            buyin_string: cachedEvent.buyin_string,
                            simpleDate: SimpleDate(from: cachedEvent.date) ?? SimpleDate(year: 2024, month: 1, day: 1),
                            event_name: cachedEvent.event_name,
                            series_name: cachedEvent.series_name,
                            description: cachedEvent.description,
                            time: cachedEvent.time,
                            buyin_usd: cachedEvent.buyin_usd,
                            casino: cachedEvent.casino
                        )
                    }
                    continuation.resume(returning: events)
                } catch {
                    print("Error loading cached events: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func cacheEvents(_ events: [Event]) async {
        await Task.detached {
            let cachedEvents = events.map { event in
                CachedEvent(
                    id: event.id,
                    buyin_string: event.buyin_string,
                    date: "\(event.simpleDate.year)-\(String(format: "%02d", event.simpleDate.month))-\(String(format: "%02d", event.simpleDate.day))",
                    event_name: event.event_name,
                    series_name: event.series_name,
                    description: event.description,
                    time: event.time,
                    buyin_usd: event.buyin_usd,
                    casino: event.casino
                )
            }
            
            do {
                let data = try JSONEncoder().encode(cachedEvents)
                UserDefaults.standard.set(data, forKey: self.cacheKey)
                UserDefaults.standard.set(Date(), forKey: self.cacheTimestampKey)
            } catch {
                print("Error caching events: \(error)")
            }
        }.value
    }

    func fetchEvents() {
        // Show loading immediately for responsive UI
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.loadingProgress = 0.0
            self?.loadingMessage = "Checking cache..."
            self?.errorMessage = nil
        }
        
        // Load cache in background to avoid blocking UI
        Task {
            // Try to load from cache first
            await MainActor.run {
                self.loadingProgress = 0.2
                self.loadingMessage = "Loading cached events..."
            }
            
            if let cachedEvents = await loadCachedEvents() {
                await MainActor.run {
                    print("📱 Loading events from cache (\(cachedEvents.count) events)")
                    self.loadingProgress = 1.0
                    self.loadingMessage = "Events loaded!"
                    self.allEvents = cachedEvents
                    
                    // Small delay to show completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isLoading = false
                        self.loadingMessage = ""
                    }
                }
                return
            }
            
            // Cache miss or expired - fetch from Firebase
            await MainActor.run {
                print("🔄 Cache miss - fetching events from Firebase")
                self.loadingProgress = 0.3
                self.loadingMessage = "Fetching from server..."
            }
            
            do {
                let querySnapshot = try await db.collection("enhanced_events").order(by: "date").getDocuments()
                
                await MainActor.run {
                    self.loadingProgress = 0.7
                    self.loadingMessage = "Processing events..."
                }
                
                // Process documents on background thread
                let parsedEvents = await Task.detached {
                    return querySnapshot.documents.compactMap { Event(document: $0) }
                }.value
                
                await MainActor.run {
                    self.loadingProgress = 1.0
                    self.loadingMessage = "Events loaded!"
                    self.allEvents = parsedEvents
                    
                    if self.allEvents.isEmpty && !querySnapshot.documents.isEmpty {
                        self.errorMessage = "Event data could not be processed or all events had empty buy-ins/invalid dates. Check console for details."
                    } else if self.allEvents.isEmpty {
                        self.errorMessage = "No events available (or all had empty buy-ins/invalid dates)."
                    }
                    
                    // Small delay to show completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isLoading = false
                        self.loadingMessage = ""
                    }
                }
                
                // Cache the newly fetched events in background
                if !parsedEvents.isEmpty {
                    Task.detached { [weak self] in
                        await self?.cacheEvents(parsedEvents)
                        print("💾 Cached \(parsedEvents.count) events")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadingMessage = ""
                    self.errorMessage = "Failed to load events: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func refreshEvents() {
        // Force refresh from Firebase (bypass cache)
        print("🔄 Force refreshing events from Firebase")
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.loadingProgress = 0.0
            self?.loadingMessage = "Refreshing events..."
            self?.errorMessage = nil
        }
        
        Task {
            await MainActor.run {
                self.loadingProgress = 0.3
                self.loadingMessage = "Fetching latest events..."
            }
            
            do {
                let querySnapshot = try await db.collection("enhanced_events").order(by: "date").getDocuments()
                
                await MainActor.run {
                    self.loadingProgress = 0.7
                    self.loadingMessage = "Processing events..."
                }
                
                // Process documents on background thread
                let parsedEvents = await Task.detached {
                    return querySnapshot.documents.compactMap { Event(document: $0) }
                }.value
                
                await MainActor.run {
                    self.loadingProgress = 1.0
                    self.loadingMessage = "Events refreshed!"
                    self.allEvents = parsedEvents
                    
                    if self.allEvents.isEmpty && !querySnapshot.documents.isEmpty {
                        self.errorMessage = "Event data could not be processed or all events had empty buy-ins/invalid dates. Check console for details."
                    } else if self.allEvents.isEmpty {
                        self.errorMessage = "No events available (or all had empty buy-ins/invalid dates)."
                    }
                    
                    // Small delay to show completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isLoading = false
                        self.loadingMessage = ""
                    }
                }
                
                // Update cache with fresh data in background
                if !parsedEvents.isEmpty {
                    Task.detached { [weak self] in
                        await self?.cacheEvents(parsedEvents)
                        print("💾 Updated cache with \(parsedEvents.count) fresh events")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadingMessage = ""
                    self.errorMessage = "Failed to load events: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct ExploreView: View {
    @State private var placeholderSearchText = "" 
    @StateObject private var viewModel = ExploreViewModel()
    @StateObject private var userEventService = UserEventService()
    @StateObject private var userService = UserService()
    @EnvironmentObject var sessionStore: SessionStore
    @State private var selectedSimpleDate: SimpleDate? = nil
    @State private var selectedTab: EventsTab = .events
    @State private var showingCreateEvent = false
    @State private var showingEventInvites = false
    @State private var showingEventHistory = false
    @State private var showingEventDetail = false
    @State private var selectedEvent: Event?
    @State private var selectedUserEvent: UserEvent? = nil // For UserEvent detail sheet
    @State private var showingSeriesView = true // New: Controls whether to show series cards or events
    @State private var selectedSeriesName: String? = nil // New: Currently selected series for detailed view
    var onEventSelected: ((Event) -> Void)? // Callback for when an event is selected
    var isSheetPresentation: Bool = false // New parameter to control top padding
    @Environment(\.dismiss) var dismiss // To dismiss the view if used as a sheet

    private var currentSystemSimpleDate: SimpleDate {
        let now = Date()
        let calendar = Calendar.current
        return SimpleDate(year: calendar.component(.year, from: now),
                          month: calendar.component(.month, from: now),
                          day: calendar.component(.day, from: now))
    }

    // --- Computed Property for Dynamic Header Title / Date Picker Label ---
    private var selectedDateDisplayString: String { 
        if let date = selectedSimpleDate {
            return date.displayMedium
        } else if let firstDate = allAvailableDates.first?.simpleDate {
            return firstDate.displayMedium
        } else if !viewModel.allEvents.isEmpty {
            return "A Date" // More active phrasing
        }
        return "No Dates"
    }
    // --- End Dynamic Header Title ---

    // MARK: - All available dates (unfiltered) for the filter sheet
    private var allAvailableDates: [IdentifiableSimpleDate] {
        let uniqueDatesSet = Set(viewModel.allEvents.map { $0.simpleDate })
        return Array(uniqueDatesSet).sorted().map { IdentifiableSimpleDate(simpleDate: $0) }
    }
    
    // MARK: - Available dates for current filters (for main view)
    private var identifiableUniqueSimpleDates: [IdentifiableSimpleDate] {
        var eventsToFilter = viewModel.allEvents
        
        // Apply only series and buy-in filters (NOT date filter)
        if !viewModel.selectedSeriesSet.isEmpty {
            eventsToFilter = eventsToFilter.filter { event in
                guard let eventSeries = event.series_name else { return false }
                return viewModel.selectedSeriesSet.contains(eventSeries)
            }
        }
        
        if viewModel.selectedBuyinRange != .all {
            eventsToFilter = eventsToFilter.filter { event in
                let buyinAmount: Double?
                if let usdBuyin = event.buyin_usd {
                    buyinAmount = usdBuyin
                } else {
                    buyinAmount = parseBuyinFromString(event.buyin_string)
                }
                guard let amount = buyinAmount else { return false }
                return viewModel.selectedBuyinRange.contains(amount)
            }
        }
        
        let uniqueDatesSet = Set(eventsToFilter.map { $0.simpleDate })
        return Array(uniqueDatesSet).sorted().map { IdentifiableSimpleDate(simpleDate: $0) }
    }
    
    // MARK: - Helper function for buy-in parsing (extracted for reuse)
    private func parseBuyinFromString(_ buyinString: String) -> Double? {
        // Remove currency symbols and normalize whitespace
        let cleanedString = buyinString
            .replacingOccurrences(of: "[€£¥,]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var totalAmount: Double = 0
        
        // Split by + and - to handle additions and subtractions
        let components = cleanedString.components(separatedBy: CharacterSet(charactersIn: "+-"))
        let operators = cleanedString.filter { "+-".contains($0) }
        
        // Process each component
        for (index, component) in components.enumerated() {
            let numberString = component
                .replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let number = Double(numberString) else { continue }
            
            if index == 0 {
                totalAmount = number
            } else if index - 1 < operators.count {
                let operatorChar = String(operators[operators.index(operators.startIndex, offsetBy: index - 1)])
                if operatorChar == "+" {
                    totalAmount += number
                } else if operatorChar == "-" {
                    totalAmount -= number
                }
            }
        }
        
        return totalAmount > 0 ? totalAmount : nil
    }

    // Changed to use SimpleDate for filtering
    private var filteredEvents: [Event] {
        var eventsToFilter = viewModel.allEvents

        // --- Apply Series Filter (Multi-select) ---
        if !viewModel.selectedSeriesSet.isEmpty {
            eventsToFilter = eventsToFilter.filter { seriesName in
                guard let eventSeries = seriesName.series_name else { return false }
                return viewModel.selectedSeriesSet.contains(eventSeries)
            }
        }

        // --- Apply Buy-in Filter ---
        if viewModel.selectedBuyinRange != .all {
            eventsToFilter = eventsToFilter.filter { event in
                // Try buyin_usd field first, then parse buyin_string
                let buyinAmount: Double?
                if let usdBuyin = event.buyin_usd {
                    buyinAmount = usdBuyin
                } else {
                    buyinAmount = parseBuyinFromString(event.buyin_string)
                }
                
                guard let amount = buyinAmount else { return false }
                return viewModel.selectedBuyinRange.contains(amount)
            }
        }
        // --- End Filter Logic ---

        // --- Apply Date Filter ---
        if let currentFilterDate = selectedSimpleDate {
            eventsToFilter = eventsToFilter.filter { $0.simpleDate == currentFilterDate }
        } else if let fallbackDate = allAvailableDates.first?.simpleDate {
            // If no date is selected, use the first available date
            eventsToFilter = eventsToFilter.filter { $0.simpleDate == fallbackDate }
        }
        
        return eventsToFilter.sorted { (event1, event2) -> Bool in
            // Sort alphabetically by event name
            return event1.event_name.localizedCompare(event2.event_name) == .orderedAscending
        }
    }
    
    // Changed to take SimpleDate
    private func formatDateForSlider(_ simpleDate: SimpleDate) -> String {
        return simpleDate.displayShort // e.g., "May 24"
    }
    
    // MARK: - Computed Properties for Event Filtering
    
    /// Non-completed events for main feed
    private var activeUserEvents: [UserEvent] {
        let now = Date()
        return userEventService.userEvents.filter { event in
            // Show events that are:
            // 1. Not cancelled
            // 2. Either upcoming OR within 24 hours of completion (still "active")
            if event.status == .cancelled {
                return false
            }
            
            // For events with end dates, consider them completed 24 hours after end
            if let endDate = event.endDate {
                let completionThreshold = Calendar.current.date(byAdding: .hour, value: 24, to: endDate) ?? endDate
                return now < completionThreshold
            }
            
            // For events without end dates, consider them completed 24 hours after start
            let completionThreshold = Calendar.current.date(byAdding: .hour, value: 24, to: event.startDate) ?? event.startDate
            return now < completionThreshold
        }
    }
    
    /// Completed events for history (both UserEvents and public event RSVPs)
    private var completedUserEvents: [UserEvent] {
        let now = Date()
        return userEventService.userEvents.filter { event in
            // Show events that are completed (24+ hours after end/start)
            if event.status == .cancelled {
                return true // Include cancelled events in history
            }
            
            // For events with end dates, consider them completed 24 hours after end
            if let endDate = event.endDate {
                let completionThreshold = Calendar.current.date(byAdding: .hour, value: 24, to: endDate) ?? endDate
                return now >= completionThreshold
            }
            
            // For events without end dates, consider them completed 24 hours after start
            let completionThreshold = Calendar.current.date(byAdding: .hour, value: 24, to: event.startDate) ?? event.startDate
            return now >= completionThreshold
        }.sorted { $0.startDate > $1.startDate } // Most recent first
    }

    /// Total completed events count (UserEvents + Public RSVPs)
    private var totalCompletedEventsCount: Int {
        return completedUserEvents.count + completedPublicEventRSVPs.count
    }

    // MARK: - Series Grouping
    private var groupedEventsBySeries: [String: [Event]] {
        let eventsForCurrentFilters = viewModel.allEvents.filter { event in
            // Apply date filter
            if let currentFilterDate = selectedSimpleDate {
                return event.simpleDate == currentFilterDate
            } else if let fallbackDate = allAvailableDates.first?.simpleDate {
                return event.simpleDate == fallbackDate
            }
            return false
        }
        
        // Group by series, handling events without series
        var grouped: [String: [Event]] = [:]
        for event in eventsForCurrentFilters {
            let seriesKey = event.series_name ?? "Other Events"
            grouped[seriesKey, default: []].append(event)
        }
        
        return grouped
    }
    
    private var sortedSeriesNames: [String] {
        return groupedEventsBySeries.keys.sorted { series1, series2 in
            // Put "Other Events" at the end
            if series1 == "Other Events" && series2 != "Other Events" {
                return false
            } else if series2 == "Other Events" && series1 != "Other Events" {
                return true
            }
            
            // Sort by event count (descending), then alphabetically
            let count1 = groupedEventsBySeries[series1]?.count ?? 0
            let count2 = groupedEventsBySeries[series2]?.count ?? 0
            
            if count1 != count2 {
                return count1 > count2
            }
            return series1 < series2
        }
    }
    
    // Events for currently selected series (when in series detail view)
    private var eventsForSelectedSeries: [Event] {
        guard let seriesName = selectedSeriesName else { return [] }
        
        var eventsToFilter = viewModel.allEvents
        
        // Filter by series
        if seriesName == "Other Events" {
            eventsToFilter = eventsToFilter.filter { $0.series_name == nil }
        } else {
            eventsToFilter = eventsToFilter.filter { $0.series_name == seriesName }
        }
        
        // Apply buy-in filter
        if viewModel.selectedBuyinRange != .all {
            eventsToFilter = eventsToFilter.filter { event in
                let buyinAmount: Double?
                if let usdBuyin = event.buyin_usd {
                    buyinAmount = usdBuyin
                } else {
                    buyinAmount = parseBuyinFromString(event.buyin_string)
                }
                
                guard let amount = buyinAmount else { return false }
                return viewModel.selectedBuyinRange.contains(amount)
            }
        }
        
        // Apply date filter
        if let currentFilterDate = selectedSimpleDate {
            eventsToFilter = eventsToFilter.filter { $0.simpleDate == currentFilterDate }
        } else if let fallbackDate = allAvailableDates.first?.simpleDate {
            eventsToFilter = eventsToFilter.filter { $0.simpleDate == fallbackDate }
        }
        
        return eventsToFilter.sorted { (event1, event2) -> Bool in
            return event1.event_name.localizedCompare(event2.event_name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            AppBackgroundView() 
            
            VStack(spacing: 0) {
                // --- Custom Gradient Tab Bar ---
                customTabBar
                
                // --- Tab Content ---
                if selectedTab == .events {
                    publicEventsView
                } else {
                    myEventsView
                }
            }
        }
        .onAppear {
            // Always fetch public events to support RSVP display in My Events
            viewModel.fetchEvents()
            
            if selectedTab == .events {
                // Public events tab - no additional user event fetching needed
            } else {
                Task {
                    try? await userEventService.fetchUserEvents()
                    try? await userEventService.fetchPendingEventInvites()
                    try? await userEventService.fetchPublicEventRSVPs()
                    await userEventService.startMyEventsListeners()
                }
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .events {
                // Ensure public events are loaded
                viewModel.fetchEvents()
                userEventService.stopMyEventsListeners()
            } else {
                // Also ensure public events are loaded for RSVP lookup
                viewModel.fetchEvents()
                Task {
                    try? await userEventService.fetchUserEvents()
                    try? await userEventService.fetchPendingEventInvites()
                    try? await userEventService.fetchPublicEventRSVPs()
                    await userEventService.startMyEventsListeners()
                }
            }
        }
        .onChange(of: viewModel.allEvents) { _ in 
            // Only set initial date if none is selected
            if selectedSimpleDate == nil {
                // Try to select current system date if it has events, otherwise select the first available date
                let hasEventsToday = allAvailableDates.contains { $0.simpleDate == currentSystemSimpleDate }
                if hasEventsToday {
                selectedSimpleDate = currentSystemSimpleDate
                } else if let firstDate = allAvailableDates.first?.simpleDate {
                    selectedSimpleDate = firstDate
                }
            }
        }

        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView { newEvent in
                // Refresh user events when a new one is created
                Task {
                    try? await userEventService.fetchUserEvents()
                }
            }
            .environmentObject(userEventService)
        }
        .sheet(isPresented: $showingEventInvites) {
            EventInvitesView()
                .environmentObject(userEventService)
        }
        .sheet(isPresented: $showingEventHistory) {
            EventHistoryView(
                completedEvents: completedUserEvents,
                completedPublicEventRSVPs: completedPublicEventRSVPs
            )
            .environmentObject(userEventService)
            .environmentObject(userService)
            .environmentObject(sessionStore)
        }

        .sheet(isPresented: $showingEventDetail) {
            if let selectedEvent = selectedEvent {
                EventDetailView(event: selectedEvent)
                    .environmentObject(userEventService)
                    .environmentObject(userService)
                    .environmentObject(sessionStore)
            }
        }
        .sheet(item: $selectedUserEvent) { userEvent in
            UserEventDetailView(event: userEvent)
                .environmentObject(userEventService)
                .environmentObject(userService)
        }
    }
    
    // MARK: - Custom Tab Bar
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(EventsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedTab == tab {
                                    // Beautiful gradient with glossy effect
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                                    Color(red: 100/255, green: 180/255, blue: 255/255),
                                                    Color(red: 64/255, green: 156/255, blue: 255/255)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            // Glossy highlight overlay
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.white.opacity(0.4),
                                                            Color.white.opacity(0.1),
                                                            Color.clear
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .center
                                                    )
                                                )
                                        )
                                        .shadow(color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.4), radius: 6, x: 0, y: 3)
                                        .shadow(color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.2), radius: 12, x: 0, y: 6)
                                        .matchedGeometryEffect(id: "tabBackground", in: tabNamespace)
                                }
                            }
                        )
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            ZStack {
                // Base transparent background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.02),
                                Color.white.opacity(0.04),
                                Color.white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Glossy overlay
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                
                // Subtle border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
    
    @Namespace private var tabNamespace
    
    // MARK: - Public Events View (Series-based)
    private var publicEventsView: some View {
        VStack(spacing: 0) {
            // --- Header: Back Button & Centered Date Navigation & Buy-in Filter ---
            HStack {
                // Leading Section - Back Button or Filter
                HStack {
                    if !showingSeriesView {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingSeriesView = true
                                selectedSeriesName = nil
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium, design: .default))
                                .foregroundColor(.white)
                        }
                    } else {
                        // Buy-in Filter (Simple)
                        Menu {
                            ForEach(BuyinRange.allCases) { range in
                                Button(action: {
                                    viewModel.selectedBuyinRange = range
                                }) {
                                    HStack {
                                        Text(range.rawValue)
                                        if viewModel.selectedBuyinRange == range {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            ZStack {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                
                                if viewModel.selectedBuyinRange != .all {
                                    Circle()
                                        .fill(Color(red: 64/255, green: 156/255, blue: 255/255))
                                        .frame(width: 8, height: 8)
                                        .offset(x: 10, y: -8)
                                }
                            }
                        }
                    }
                }
                .frame(width: 60, alignment: .leading)
                
                Spacer()
                
                // --- Centered Date Navigation ---
                HStack(spacing: 16) {
                    // Previous Date Button
                    Button(action: {
                        navigateToDate(direction: -1)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(canNavigateToDate(direction: -1) ? 0.1 : 0.05))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(canNavigateToDate(direction: -1) ? .white : .white.opacity(0.3))
                        }
                    }
                    .disabled(!canNavigateToDate(direction: -1))
                    
                    // Date Display
                    VStack(alignment: .center, spacing: 2) {
                        if showingSeriesView {
                            Text("Events On")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Text(selectedDateDisplayString)
                           .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundColor(.white)
                           .lineLimit(1)
                    }
                    .frame(minWidth: 120)
                    
                    // Next Date Button
                    Button(action: {
                        navigateToDate(direction: 1)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(canNavigateToDate(direction: 1) ? 0.1 : 0.05))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(canNavigateToDate(direction: 1) ? .white : .white.opacity(0.3))
                        }
                    }
                    .disabled(!canNavigateToDate(direction: 1))
                }
                
                Spacer()
                
                // Trailing Section - Filter or Spacer
                HStack {
                    if !showingSeriesView {
                        // Buy-in Filter (Simple)
                        Menu {
                            ForEach(BuyinRange.allCases) { range in
                                Button(action: {
                                    viewModel.selectedBuyinRange = range
                                }) {
                                    HStack {
                                        Text(range.rawValue)
                                        if viewModel.selectedBuyinRange == range {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            ZStack {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                
                                if viewModel.selectedBuyinRange != .all {
                                    Circle()
                                        .fill(Color(red: 64/255, green: 156/255, blue: 255/255))
                                        .frame(width: 8, height: 8)
                                        .offset(x: 10, y: -8)
                                }
                            }
                        }
                    }
                }
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .padding(.bottom, 16)
            // --- End Header ---

            if viewModel.isLoading {
                Spacer()
                VStack(spacing: 16) {
                    // Progress Circle
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: viewModel.loadingProgress)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255),
                                        Color(red: 100/255, green: 180/255, blue: 255/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: viewModel.loadingProgress)
                        
                        Image(systemName: "calendar")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text(viewModel.loadingMessage.isEmpty ? "Loading Events..." : viewModel.loadingMessage)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.loadingMessage)
                        
                        if viewModel.loadingProgress > 0 {
                            Text("\(Int(viewModel.loadingProgress * 100))%")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.loadingProgress)
                        }
                    }
                }
                Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 10) {
                     Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    Text("Error")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else if showingSeriesView {
                // Show series cards
                seriesListView
            } else {
                // Show events within selected series
                eventsWithinSeriesView
            }
        }
    }
    
    // MARK: - Series List View
    private var seriesListView: some View {
        ScrollView {
            if groupedEventsBySeries.isEmpty {
                VStack {
                    Spacer(minLength: 50)
                    Image(systemName: identifiableUniqueSimpleDates.isEmpty ? "calendar.badge.plus" : "calendar.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        .padding(.bottom, 10)
                    Text(identifiableUniqueSimpleDates.isEmpty ? "No Events Available" : "No Events for Selected Date")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedSeriesNames, id: \.self) { seriesName in
                        if let events = groupedEventsBySeries[seriesName] {
                            SeriesCardView(
                                seriesName: seriesName,
                                eventCount: events.count,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedSeriesName = seriesName
                                        showingSeriesView = false
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .refreshable {
            viewModel.refreshEvents()
        }
    }
    
    // MARK: - Events Within Series View
    private var eventsWithinSeriesView: some View {
        ScrollView {
            if eventsForSelectedSeries.isEmpty {
                VStack {
                    Spacer(minLength: 50)
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 50))
                        .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        .padding(.bottom, 10)
                    Text("No Events Found")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(.gray)
                    Text("Try adjusting your filters")
                        .font(.system(size: 14))
                        .foregroundColor(.gray.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    ForEach(eventsForSelectedSeries) { event in 
                        EventCardView(event: event, onSelect: {
                            if let onEventSelected = onEventSelected {
                                onEventSelected(event) // Call the callback if provided
                            } else {
                                // Show detail view
                                selectedEvent = event
                                showingEventDetail = true
                            }
                        })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .refreshable {
            viewModel.refreshEvents()
        }
    }
    
    // MARK: - Date Navigation Helpers
    private func canNavigateToDate(direction: Int) -> Bool {
        guard let currentDate = selectedSimpleDate else { return false }
        
        if let currentIndex = allAvailableDates.firstIndex(where: { $0.simpleDate == currentDate }) {
            let newIndex = currentIndex + direction
            return newIndex >= 0 && newIndex < allAvailableDates.count
        }
        return false
    }
    
    private func navigateToDate(direction: Int) {
        guard let currentDate = selectedSimpleDate else { return }
        
        if let currentIndex = allAvailableDates.firstIndex(where: { $0.simpleDate == currentDate }) {
            let newIndex = currentIndex + direction
            if newIndex >= 0 && newIndex < allAvailableDates.count {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedSimpleDate = allAvailableDates[newIndex].simpleDate
                }
            }
        }
    }
    
    // MARK: - My Events View (User Events)
    private var myEventsView: some View {
        VStack(spacing: 0) {
            // --- Header with Create Event Button ---
            HStack {
                Text("My Events")
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundColor(.white)
                
                Spacer()
                
                // History Button
                Button(action: {
                    showingEventHistory = true
                }) {
                    ZStack {
                        Image(systemName: "clock")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                        if totalCompletedEventsCount > 0 {
                            Text("\(totalCompletedEventsCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 16, height: 16)
                                .background(Color.gray.opacity(0.8))
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .padding(.trailing, 12)
                
                // Invites Button (always visible)
                    Button(action: {
                        showingEventInvites = true
                    }) {
                        ZStack {
                            Image(systemName: "envelope")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        if !userEventService.pendingInvites.isEmpty {
                            Text("\(userEventService.pendingInvites.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 16, height: 16)
                                .background(Color(red: 64/255, green: 156/255, blue: 255/255))
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .padding(.trailing, 12)
                
                // Create Event Button
                Button(action: {
                    showingCreateEvent = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                    Color(red: 100/255, green: 180/255, blue: 255/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // --- Content ---
            if userEventService.isLoading {
                Spacer()
                VStack(spacing: 16) {
                    // Progress Circle
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: 0.7) // Indeterminate progress
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255),
                                        Color(red: 100/255, green: 180/255, blue: 255/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: userEventService.isLoading)
                        
                        Image(systemName: "person.calendar")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Text("Loading Your Events...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                Spacer()
            } else if activeUserEvents.isEmpty && userEventService.publicEventRSVPs.isEmpty {
                VStack {
                    Spacer(minLength: 50)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        .padding(.bottom, 16)
                    
                    Text("No Events Yet")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                    
                    Text("Create your first event or RSVP to public events")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .padding(.bottom, 24)
                    
                    Button(action: {
                        showingCreateEvent = true
                    }) {
                        Text("Create Event")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255),
                                        Color(red: 100/255, green: 180/255, blue: 255/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(25)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Combined schedule view with both UserEvents and Public Event RSVPs
                combinedScheduleView
            }
        }
    }
    
    // MARK: - Schedule View
    private var scheduleView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedEventsByDate.keys.sorted(), id: \.self) { date in
                    if let eventsForDate = groupedEventsByDate[date] {
                        // Date Section Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatDateHeader(date))
                                    .font(.system(size: 18, weight: .bold, design: .default))
                                    .foregroundColor(.white)
                                
                                Text(relativeDateString(date))
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Event count badge
                            Text("\(eventsForDate.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color(red: 64/255, green: 156/255, blue: 255/255))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, date == groupedEventsByDate.keys.sorted().first ? 8 : 24)
                        .padding(.bottom, 12)
                        
                        // Events for this date
                        ForEach(eventsForDate.sorted { $0.startDate < $1.startDate }) { event in
                            UserEventCardView(event: event, onSelect: {
                                selectedUserEvent = event
                            })
                                .environmentObject(userEventService)
                                .environmentObject(userService)
                                .environmentObject(sessionStore)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 14)
                        }
                    }
                }
                
                // Bottom padding
                Color.clear.frame(height: 100)
            }
        }
    }
    
    // MARK: - Combined Schedule View (UserEvents + Public Event RSVPs)
    private var combinedScheduleView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(combinedGroupedEventsByDate.keys.sorted(), id: \.self) { date in
                    if let eventsForDate = combinedGroupedEventsByDate[date] {
                        // Date Section Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatDateHeader(date))
                                    .font(.system(size: 18, weight: .bold, design: .default))
                                    .foregroundColor(.white)
                                
                                Text(relativeDateString(date))
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Event count badge
                            Text("\(eventsForDate.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color(red: 64/255, green: 156/255, blue: 255/255))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, date == combinedGroupedEventsByDate.keys.sorted().first ? 8 : 24)
                        .padding(.bottom, 12)
                        
                        // Events for this date
                        ForEach(eventsForDate.sorted { $0.date < $1.date }) { eventItem in
                            if eventItem.isUserEvent, let userEvent = eventItem.userEvent {
                                UserEventCardView(event: userEvent, onSelect: {
                                    selectedUserEvent = userEvent
                                })
                                    .environmentObject(userEventService)
                                    .environmentObject(userService)
                                    .environmentObject(sessionStore)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 14)
                            } else if let publicEvent = eventItem.publicEvent {
                                EventCardView(event: publicEvent, onSelect: {
                                    selectedEvent = publicEvent
                                    showingEventDetail = true
                                })
                                .padding(.horizontal, 20)
                                .padding(.bottom, 14)
                            }
                        }
                    }
                }
                
                // Bottom padding
                Color.clear.frame(height: 100)
            }
        }
    }
    
    // MARK: - Computed Properties for Schedule
    private var groupedEventsByDate: [Date: [UserEvent]] {
        let calendar = Calendar.current
        return Dictionary(grouping: activeUserEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
    }
    
    // MARK: - Combined Event Item for Mixed Schedule
    private struct CombinedEventItem: Identifiable {
        let id = UUID()
        let date: Date
        let isUserEvent: Bool
        let userEvent: UserEvent?
        let publicEvent: Event?
        
        init(userEvent: UserEvent) {
            self.date = userEvent.startDate
            self.isUserEvent = true
            self.userEvent = userEvent
            self.publicEvent = nil
        }
        
        init(publicEvent: Event, rsvpDate: Date) {
            self.date = rsvpDate
            self.isUserEvent = false
            self.userEvent = nil
            self.publicEvent = publicEvent
        }
    }
    
    // MARK: - Combined Grouped Events (UserEvents + Public Event RSVPs)
    private var combinedGroupedEventsByDate: [Date: [CombinedEventItem]] {
        let calendar = Calendar.current
        var combinedItems: [CombinedEventItem] = []
        
        // Add UserEvents
        for userEvent in activeUserEvents {
            combinedItems.append(CombinedEventItem(userEvent: userEvent))
        }
        
        // Add Public Event RSVPs (only active ones)
        for rsvp in userEventService.publicEventRSVPs {
            // Calculate if this public event is completed (12 hours after start)
            let completionTime = calendar.date(byAdding: .hour, value: 12, to: rsvp.eventDate) ?? rsvp.eventDate
            let now = Date()
            
            // Only include if not completed
            if now < completionTime {
                // Look up the original event from viewModel.allEvents to get complete data
                if let originalEvent = viewModel.allEvents.first(where: { $0.id == rsvp.publicEventId }) {
                    combinedItems.append(CombinedEventItem(publicEvent: originalEvent, rsvpDate: rsvp.eventDate))
                } else {
                    // Fallback: Create event from RSVP data if original not found
                    let fallbackEvent = Event(
                        id: rsvp.publicEventId,
                        buyin_string: "TBD",
                        simpleDate: SimpleDate(
                            year: calendar.component(.year, from: rsvp.eventDate),
                            month: calendar.component(.month, from: rsvp.eventDate),
                            day: calendar.component(.day, from: rsvp.eventDate)
                        ),
                        event_name: rsvp.eventName,
                        series_name: nil,
                        description: nil,
                        time: nil,
                        buyin_usd: nil,
                        casino: nil
                    )
                    
                    combinedItems.append(CombinedEventItem(publicEvent: fallbackEvent, rsvpDate: rsvp.eventDate))
                }
            }
        }
        
        return Dictionary(grouping: combinedItems) { item in
            calendar.startOfDay(for: item.date)
        }
    }
    
    // MARK: - Completed Public Event RSVPs
    private var completedPublicEventRSVPs: [PublicEventRSVP] {
        let calendar = Calendar.current
        let now = Date()
        
        return userEventService.publicEventRSVPs.filter { rsvp in
            let completionTime = calendar.date(byAdding: .hour, value: 12, to: rsvp.eventDate) ?? rsvp.eventDate
            return now >= completionTime
        }
    }
    
    // MARK: - Helper Functions for Schedule
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func relativeDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDate = calendar.startOfDay(for: date)
        
        if calendar.isDate(eventDate, inSameDayAs: today) {
            return "Today"
        } else if calendar.isDate(eventDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) {
            return "Tomorrow"
        } else if calendar.isDate(eventDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
            return "Yesterday"
        } else {
            let daysFromToday = calendar.dateComponents([.day], from: today, to: eventDate).day ?? 0
            if daysFromToday > 0 {
                return "In \(daysFromToday) day\(daysFromToday == 1 ? "" : "s")"
            } else {
                return "\(-daysFromToday) day\(daysFromToday == -1 ? "" : "s") ago"
            }
        }
    }
}

#Preview {
    ExploreView()
} 
