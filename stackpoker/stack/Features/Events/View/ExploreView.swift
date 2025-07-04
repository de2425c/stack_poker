import SwiftUI
import FirebaseFirestore
import Combine
import FirebaseAuth
import Kingfisher

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

// MARK: - Event Status Extension
extension Event {
    /// Calculate the current status of a public event based on timing
    var currentStatus: UserEvent.EventStatus {
        let now = Date()
        let calendar = Calendar.current
        
        // Create base date from SimpleDate
        let baseEventDate = calendar.date(from: DateComponents(
            year: simpleDate.year,
            month: simpleDate.month,
            day: simpleDate.day
        )) ?? Date()
        
        // Parse start time if available
        let eventStartTime = parseEventStartTime(baseDate: baseEventDate, timeString: time)
        
        // Parse late registration end time if available
        let lateRegEndTime = parseLateRegistrationEndTime(startTime: eventStartTime, lateRegString: lateRegistration)
        
        // Calculate ongoing period end (12 hours after late reg ends, or start time if no late reg)
        let ongoingEndTime = calendar.date(byAdding: .hour, value: 12, to: lateRegEndTime ?? eventStartTime) ?? eventStartTime
        
        // Determine status based on current time
        if now < eventStartTime {
            return .upcoming
        } else if let lateRegEnd = lateRegEndTime, now >= eventStartTime && now < lateRegEnd {
            return .lateRegistration
        } else if now < ongoingEndTime {
            return .active
        } else {
            return .completed
        }
    }
    
    // MARK: - Time Parsing Helper Functions
    
    private func parseEventStartTime(baseDate: Date, timeString: String?) -> Date {
        guard let timeString = timeString, !timeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Default to 6 PM if no time specified
            let calendar = Calendar.current
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: baseDate) ?? baseDate
        }
        
        let calendar = Calendar.current
        let cleanTimeString = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse time in various formats
        let timeFormats = ["h:mm a", "HH:mm", "h a", "ha", "h:mma"]
        let formatter = DateFormatter()
        
        for format in timeFormats {
            formatter.dateFormat = format
            if let time = formatter.date(from: cleanTimeString) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                if let hour = timeComponents.hour, let minute = timeComponents.minute {
                    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? baseDate
                }
            }
        }
        
        // If parsing fails, default to 6 PM
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: baseDate) ?? baseDate
    }
    
    private func parseLateRegistrationEndTime(startTime: Date, lateRegString: String?) -> Date? {
        guard let lateRegString = lateRegString, !lateRegString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        let calendar = Calendar.current
        let cleanString = lateRegString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract level information (e.g., "End of Level 8", "Level 10", "8 levels")
        if let levelMatch = extractLevelNumber(from: cleanString) {
            // Assume each level is the levelLength from the event (default 20 minutes if not specified)
            let levelLengthMinutes = levelLength ?? 20
            let totalMinutes = levelMatch * levelLengthMinutes
            return calendar.date(byAdding: .minute, value: totalMinutes, to: startTime)
        }
        
        // Try to extract time duration (e.g., "2 hours", "90 minutes", "1.5 hours")
        if let durationMinutes = extractDurationMinutes(from: cleanString) {
            return calendar.date(byAdding: .minute, value: durationMinutes, to: startTime)
        }
        
        // Try to extract specific time (e.g., "9:30 PM", "21:30")
        if let specificTime = parseSpecificTime(from: cleanString, baseDate: startTime) {
            return specificTime
        }
        
        // Default fallback: 2 hours after start if we can't parse
        return calendar.date(byAdding: .hour, value: 2, to: startTime)
    }
    
    private func extractLevelNumber(from string: String) -> Int? {
        // Patterns to match: "end of level 8", "level 10", "8 levels", etc.
        let patterns = [
            "(?:end of )?level (\\d+)",
            "(\\d+) levels?",
            "through level (\\d+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: string.utf16.count)
                if let match = regex.firstMatch(in: string, options: [], range: range) {
                    let numberRange = match.range(at: 1)
                    if let range = Range(numberRange, in: string) {
                        if let number = Int(String(string[range])) {
                            return number
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func extractDurationMinutes(from string: String) -> Int? {
        // Patterns for duration: "2 hours", "90 minutes", "1.5 hours", "2h 30m"
        let patterns = [
            "(\\d+(?:\\.\\d+)?)\\s*hours?",
            "(\\d+)\\s*minutes?",
            "(\\d+)h\\s*(\\d+)m",
            "(\\d+)\\s*hrs?",
            "(\\d+)\\s*mins?"
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: string.utf16.count)
                if let match = regex.firstMatch(in: string, options: [], range: range) {
                    switch index {
                    case 0, 3: // hours patterns
                        let hoursRange = match.range(at: 1)
                        if let range = Range(hoursRange, in: string),
                           let hours = Double(String(string[range])) {
                            return Int(hours * 60)
                        }
                    case 1, 4: // minutes patterns  
                        let minutesRange = match.range(at: 1)
                        if let range = Range(minutesRange, in: string),
                           let minutes = Int(String(string[range])) {
                            return minutes
                        }
                    case 2: // "2h 30m" pattern
                        let hoursRange = match.range(at: 1)
                        let minutesRange = match.range(at: 2)
                        if let hoursStringRange = Range(hoursRange, in: string),
                           let minutesStringRange = Range(minutesRange, in: string),
                           let hours = Int(String(string[hoursStringRange])),
                           let minutes = Int(String(string[minutesStringRange])) {
                            return hours * 60 + minutes
                        }
                    default:
                        break
                    }
                }
            }
        }
        return nil
    }
    
    private func parseSpecificTime(from string: String, baseDate: Date) -> Date? {
        let calendar = Calendar.current
        let timeFormats = ["h:mm a", "HH:mm", "h a", "ha"]
        let formatter = DateFormatter()
        
        for format in timeFormats {
            formatter.dateFormat = format
            // Try to find time pattern in the string
            if let regex = try? NSRegularExpression(pattern: "\\b\\d{1,2}:?\\d{0,2}\\s*[ap]?m?\\b", options: .caseInsensitive) {
                let range = NSRange(location: 0, length: string.utf16.count)
                if let match = regex.firstMatch(in: string, options: [], range: range) {
                    if let timeRange = Range(match.range, in: string) {
                        let timeString = String(string[timeRange])
                        if let time = formatter.date(from: timeString) {
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                            if let hour = timeComponents.hour, let minute = timeComponents.minute {
                                let baseDateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
                                var newComponents = DateComponents()
                                newComponents.year = baseDateComponents.year
                                newComponents.month = baseDateComponents.month
                                newComponents.day = baseDateComponents.day
                                newComponents.hour = hour
                                newComponents.minute = minute
                                return calendar.date(from: newComponents)
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
}

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
    // New fields for new_event format
    let chipsFormatted: String?
    let game: String?
    let guarantee: Double?
    let guaranteeFormatted: String?
    let lateRegistration: String?
    let levelLength: Int?
    let levelsFormatted: String?
    let pdfLink: String?
    let seriesEnd: String?
    let seriesStart: String?
    let startingChips: Int?
    let imageUrl: String?
}

// Old IdentifiableDate struct removed (was lines 4-16)

// 1. Event Model (Updated for new_event collection)
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
    
    // New fields for new_event format
    let chipsFormatted: String?
    let game: String?
    let guarantee: Double?
    let guaranteeFormatted: String?
    let lateRegistration: String?
    let levelLength: Int?
    let levelsFormatted: String?
    let pdfLink: String?
    let seriesEnd: Date?
    let seriesStart: Date?
    let startingChips: Int?
    let imageUrl: String?

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard let docId = Optional(document.documentID), !docId.isEmpty else {
            return nil
        }
        self.id = docId

        // Parse buy-in information - use buyInFormatted and buyIn from new_event format
        guard let buyinFormatted = data["buyInFormatted"] as? String, !buyinFormatted.isEmpty else { 
            return nil 
        }
        self.buyin_string = buyinFormatted
        self.buyin_usd = data["buyIn"] as? Double

        // Parse event date - convert from Timestamp to SimpleDate
        guard let eventDateTimestamp = data["eventDate"] as? Timestamp else { 
            return nil
        }
        let eventDate = eventDateTimestamp.dateValue()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: eventDate)
        let month = calendar.component(.month, from: eventDate)
        let day = calendar.component(.day, from: eventDate)
        self.simpleDate = SimpleDate(year: year, month: month, day: day)

        // Parse event name
        guard let eventNameStr = data["eventName"] as? String, !eventNameStr.isEmpty else { 
            return nil
        }
        self.event_name = eventNameStr

        // Parse series name
        self.series_name = data["series"] as? String

        // Parse event time
        let timeValue = data["eventTime"] as? String
        if let t = timeValue, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.time = t
        } else {
            self.time = nil
        }

        // Legacy fields (not in new format but keeping for compatibility)
        self.description = nil // Not present in new format
        self.casino = data["casino"] as? String // Read casino directly from Firebase

        // New fields from new_event format
        self.chipsFormatted = data["chipsFormatted"] as? String
        self.game = data["game"] as? String
        self.guarantee = data["guarantee"] as? Double
        self.guaranteeFormatted = data["guaranteeFormatted"] as? String
        self.lateRegistration = data["lateRegistration"] as? String
        self.levelLength = data["levelLength"] as? Int
        self.levelsFormatted = data["levelsFormatted"] as? String
        self.pdfLink = data["pdfLink"] as? String
        self.startingChips = data["startingChips"] as? Int
        self.imageUrl = data["imageUrl"] as? String
        
        // Parse series dates
        if let seriesEndTimestamp = data["seriesEnd"] as? Timestamp {
            self.seriesEnd = seriesEndTimestamp.dateValue()
        } else {
            self.seriesEnd = nil
        }
        
        if let seriesStartTimestamp = data["seriesStart"] as? Timestamp {
            self.seriesStart = seriesStartTimestamp.dateValue()
        } else {
            self.seriesStart = nil
        }
    }
    
    // Manual initializer for creating events from RSVP data
    init(id: String, buyin_string: String, simpleDate: SimpleDate, event_name: String, series_name: String? = nil, description: String? = nil, time: String? = nil, buyin_usd: Double? = nil, casino: String? = nil, chipsFormatted: String? = nil, game: String? = nil, guarantee: Double? = nil, guaranteeFormatted: String? = nil, lateRegistration: String? = nil, levelLength: Int? = nil, levelsFormatted: String? = nil, pdfLink: String? = nil, seriesEnd: Date? = nil, seriesStart: Date? = nil, startingChips: Int? = nil, imageUrl: String? = nil) {
        self.id = id
        self.buyin_string = buyin_string
        self.simpleDate = simpleDate
        self.event_name = event_name
        self.series_name = series_name
        self.description = description
        self.time = time
        self.buyin_usd = buyin_usd
        self.casino = casino
        self.chipsFormatted = chipsFormatted
        self.game = game
        self.guarantee = guarantee
        self.guaranteeFormatted = guaranteeFormatted
        self.lateRegistration = lateRegistration
        self.levelLength = levelLength
        self.levelsFormatted = levelsFormatted
        self.pdfLink = pdfLink
        self.seriesEnd = seriesEnd
        self.seriesStart = seriesStart
        self.startingChips = startingChips
        self.imageUrl = imageUrl
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

// MARK: - Event List Item View (Flat Format)
struct EventListItemView: View {
    let event: Event
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 16) {
                // Left side - Event Name and Game type
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.event_name)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let game = event.game, !game.isEmpty {
                        Text(game)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.gray)
                    }
                }
                
                // Right side - Buy-in and Time 
                VStack(alignment: .trailing, spacing: 4) {
                    Text(event.buyin_string)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                    
                    if let time = event.time {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Text(time)
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                    
                    // Border
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Series Card View
struct SeriesCardView: View {
    let seriesName: String
    let totalEventCount: Int
    let currentDateEventCount: Int
    let events: [Event]
    let currentDate: SimpleDate?
    let onSelect: () -> Void
    
    @State private var cardOffset: CGFloat = 30
    @State private var cardOpacity: Double = 0
    
    // Get the first event's imageUrl for the banner
    private var bannerImageUrl: String? {
        return events.first?.imageUrl
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // Top Banner Image (no text overlay)
                ZStack {
                    // Image with fallback to stack logo
                    if let imageUrl = bannerImageUrl, let url = URL(string: imageUrl) {
                        KFImage(url)
                            .placeholder {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 40/255, green: 40/255, blue: 50/255),
                                                Color(red: 25/255, green: 25/255, blue: 35/255)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 110)
                            .clipped()
                    } else {
                        // Fallback to stack logo
                        ZStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5),
                                            Color(red: 40/255, green: 40/255, blue: 50/255)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 110)
                            
                            Image("stack_logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                                .opacity(0.8)
                        }
                    }
                }
                
                // Bottom section with series info
                VStack(alignment: .leading, spacing: 8) {
                    Text(seriesName)
                        .font(.custom("PlusJakartaSans-Bold", size: 18))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Events")
                                .font(.custom("PlusJakartaSans-Medium", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("\(totalEventCount)")
                                .font(.custom("PlusJakartaSans-Bold", size: 16))
                                .foregroundColor(.white)
                        }
                        
                        if currentDateEventCount > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Today")
                                    .font(.custom("PlusJakartaSans-Medium", size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text("\(currentDateEventCount)")
                                    .font(.custom("PlusJakartaSans-Bold", size: 16))
                                    .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                            }
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.2))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            ZStack {
                // Use a slightly darker base for the card
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 28/255, green: 30/255, blue: 40/255))
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 8)
        .offset(y: cardOffset)
        .opacity(cardOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardOffset = 0
                cardOpacity = 1
            }
        }
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
    private let cacheKey = "cached_enhanced_events_v2" // Updated version to include imageUrl
    private let cacheTimestampKey = "cached_events_timestamp_v2"
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
                            casino: cachedEvent.casino,
                            chipsFormatted: cachedEvent.chipsFormatted,
                            game: cachedEvent.game,
                            guarantee: cachedEvent.guarantee,
                            guaranteeFormatted: cachedEvent.guaranteeFormatted,
                            lateRegistration: cachedEvent.lateRegistration,
                            levelLength: cachedEvent.levelLength,
                            levelsFormatted: cachedEvent.levelsFormatted,
                            pdfLink: cachedEvent.pdfLink,
                            seriesEnd: cachedEvent.seriesEnd != nil ? Date(timeIntervalSince1970: Double(cachedEvent.seriesEnd!) ?? 0) : nil,
                            seriesStart: cachedEvent.seriesStart != nil ? Date(timeIntervalSince1970: Double(cachedEvent.seriesStart!) ?? 0) : nil,
                            startingChips: cachedEvent.startingChips,
                            imageUrl: cachedEvent.imageUrl
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
                    casino: event.casino,
                    chipsFormatted: event.chipsFormatted,
                    game: event.game,
                    guarantee: event.guarantee,
                    guaranteeFormatted: event.guaranteeFormatted,
                    lateRegistration: event.lateRegistration,
                    levelLength: event.levelLength,
                    levelsFormatted: event.levelsFormatted,
                    pdfLink: event.pdfLink,
                    seriesEnd: event.seriesEnd?.timeIntervalSince1970.description,
                    seriesStart: event.seriesStart?.timeIntervalSince1970.description,
                    startingChips: event.startingChips,
                    imageUrl: event.imageUrl
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
                let querySnapshot = try await db.collection("new_event").order(by: "eventDate").getDocuments()
                
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
                let querySnapshot = try await db.collection("new_event").order(by: "eventDate").getDocuments()
                
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

// MARK: - Combined Event Item for Mixed Schedule
struct CombinedEventItem: Identifiable {
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

struct ExploreView: View {
    @State private var placeholderSearchText = "" 
    @StateObject private var viewModel = ExploreViewModel()
    @StateObject private var userEventService = UserEventService()
    @StateObject private var userService = UserService()
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var tutorialManager: TutorialManager
    @State private var selectedSimpleDate: SimpleDate? = nil
    @State private var selectedTab: EventsTab
    @State private var showingCreateEvent = false
    @State private var showingEventInvites = false
    @State private var showingEventDetail = false
    @State private var selectedEvent: Event?
    @State private var selectedUserEvent: UserEvent? = nil // For UserEvent detail sheet
    @State private var showingSeriesView = true // New: Controls whether to show series cards or events
    @State private var selectedSeriesName: String? = nil // New: Currently selected series for detailed view
    @State private var calendarSelectedDate = Date()
    @State private var isLoadingMyEvents = false // Track loading state for My Events tab
    @State private var isListViewMode = false // Toggle between card view and list view in series detail
    @State private var selectedDateInSeries: SimpleDate? = nil // For date navigation within series
    @State private var showingDatePicker = false // For calendar date picker
    @State private var isCalendarDaySelected = false // Track if a specific day is selected in calendar
    var onEventSelected: ((Event) -> Void)? // Callback for when an event is selected
    var isSheetPresentation: Bool = false // New parameter to control top padding
    @Environment(\.dismiss) var dismiss // To dismiss the view if used as a sheet
    
    // Initialize selectedTab based on whether this is for event selection
    init(onEventSelected: ((Event) -> Void)? = nil, isSheetPresentation: Bool = false) {
        self.onEventSelected = onEventSelected
        self.isSheetPresentation = isSheetPresentation
        // Default to Events tab when used for event selection, My Events otherwise
        self._selectedTab = State(initialValue: isSheetPresentation ? .events : .myEvents)
    }

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
            // First, sort by buy-in amount (put $0 events last)
            let buyin1 = event1.buyin_usd ?? parseBuyinFromString(event1.buyin_string) ?? 0
            let buyin2 = event2.buyin_usd ?? parseBuyinFromString(event2.buyin_string) ?? 0
            
            // If one is $0 and the other isn't, put the $0 one last
            if buyin1 == 0 && buyin2 > 0 {
                return false
            } else if buyin2 == 0 && buyin1 > 0 {
                return true
            }
            
            // If both are $0 or both are non-zero, sort alphabetically by event name
            return event1.event_name.localizedCompare(event2.event_name) == .orderedAscending
        }
    }
    
    // Changed to take SimpleDate
    private func formatDateForSlider(_ simpleDate: SimpleDate) -> String {
        return simpleDate.displayShort // e.g., "May 24"
    }
    
    // MARK: - Computed Properties for Event Filtering
    
    /// All user events for calendar display
    private var allUserEvents: [UserEvent] {
        return userEventService.userEvents.filter { event in
            // Only exclude cancelled events
            return event.status != .cancelled
        }
    }

    // MARK: - Series Grouping
    private var groupedEventsBySeries: [String: [Event]] {
        // For series overview, show ALL events across all dates (no date filter)
        // Only apply buy-in filter if selected
        var eventsForCurrentFilters = viewModel.allEvents
        
        // Apply buy-in filter if not "all"
        if viewModel.selectedBuyinRange != .all {
            eventsForCurrentFilters = eventsForCurrentFilters.filter { event in
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
    
    // Events for currently selected series (when in series detail view) - ALL dates
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
        
        // NO date filter - show all events for the series across all dates
        
        return eventsToFilter.sorted { (event1, event2) -> Bool in
            // Sort by date first
            if event1.simpleDate != event2.simpleDate {
                return event1.simpleDate < event2.simpleDate
            }
            
            // Then sort by buy-in amount (put $0 events last within the same date)
            let buyin1 = event1.buyin_usd ?? parseBuyinFromString(event1.buyin_string) ?? 0
            let buyin2 = event2.buyin_usd ?? parseBuyinFromString(event2.buyin_string) ?? 0
            
            // If one is $0 and the other isn't, put the $0 one last
            if buyin1 == 0 && buyin2 > 0 {
                return false
            } else if buyin2 == 0 && buyin1 > 0 {
                return true
            }
            
            // If both are $0 or both are non-zero, sort alphabetically by event name
            return event1.event_name.localizedCompare(event2.event_name) == .orderedAscending
        }
    }
    
    // Group events by date for series detail view
    private var eventsGroupedByDateForSeries: [SimpleDate: [Event]] {
        return Dictionary(grouping: eventsForSelectedSeries) { $0.simpleDate }
    }
    
    private var sortedDatesForSeries: [SimpleDate] {
        return eventsGroupedByDateForSeries.keys.sorted()
    }
    
    // Current date display for series navigation
    private var currentDateInSeriesDisplay: String {
        guard let currentDate = selectedDateInSeries else {
            return sortedDatesForSeries.first?.displayMedium ?? "No Date"
        }
        return currentDate.displayMedium
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()
            
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
            // Initialize calendar state
            isCalendarDaySelected = false
            calendarSelectedDate = Date()
            
            // Always fetch public events to support RSVP display in My Events
            viewModel.fetchEvents()
            
            if selectedTab == .events {
                // Public events tab - no additional user event fetching needed
                isLoadingMyEvents = false
            } else {
                // Set loading state immediately for My Events tab
                isLoadingMyEvents = true
                Task {
                    try? await userEventService.fetchUserEvents()
                    try? await userEventService.fetchPendingEventInvites()
                    try? await userEventService.fetchPublicEventRSVPs()
                    await userEventService.startMyEventsListeners()
                    
                    // Clear loading state after all data is loaded
                    await MainActor.run {
                        isLoadingMyEvents = false
                    }
                }
            }
            
            // Tutorial: User will advance by tapping groups tab
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .events {
                // Ensure public events are loaded
                viewModel.fetchEvents()
                userEventService.stopMyEventsListeners()
                isLoadingMyEvents = false
            } else {
                // Set loading state immediately to prevent flash
                isLoadingMyEvents = true
                
                // Reset calendar to month view when switching to My Events
                isCalendarDaySelected = false
                calendarSelectedDate = Date()
                
                // Also ensure public events are loaded for RSVP lookup
                viewModel.fetchEvents()
                Task {
                    try? await userEventService.fetchUserEvents()
                    try? await userEventService.fetchPendingEventInvites()
                    try? await userEventService.fetchPublicEventRSVPs()
                    await userEventService.startMyEventsListeners()
                    
                    // Clear loading state after all data is loaded
                    await MainActor.run {
                        isLoadingMyEvents = false
                    }
                }
            }
        }
        .onChange(of: viewModel.allEvents) { _ in 
            // Only set initial date if none is selected
            if selectedSimpleDate == nil {
                // Always try to select current system date first if it has events
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
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                VStack {
                    DatePicker(
                        "Select Date",
                        selection: Binding(
                            get: {
                                // Convert selectedDateInSeries to Date
                                guard let simpleDate = selectedDateInSeries else {
                                    return Date()
                                }
                                var components = DateComponents()
                                components.year = simpleDate.year
                                components.month = simpleDate.month
                                components.day = simpleDate.day
                                return Calendar.current.date(from: components) ?? Date()
                            },
                            set: { newDate in
                                // Convert Date to SimpleDate
                                let calendar = Calendar.current
                                let year = calendar.component(.year, from: newDate)
                                let month = calendar.component(.month, from: newDate)
                                let day = calendar.component(.day, from: newDate)
                                let newSimpleDate = SimpleDate(year: year, month: month, day: day)
                                
                                // Only set if this date exists in the series
                                if sortedDatesForSeries.contains(newSimpleDate) {
                                    selectedDateInSeries = newSimpleDate
                                }
                            }
                        ),
                        in: {
                            // Create date range from available dates
                            guard let firstDate = sortedDatesForSeries.first,
                                  let lastDate = sortedDatesForSeries.last else {
                                return Date()...Date()
                            }
                            
                            var firstComponents = DateComponents()
                            firstComponents.year = firstDate.year
                            firstComponents.month = firstDate.month
                            firstComponents.day = firstDate.day
                            
                            var lastComponents = DateComponents()
                            lastComponents.year = lastDate.year
                            lastComponents.month = lastDate.month
                            lastComponents.day = lastDate.day
                            
                            let startDate = Calendar.current.date(from: firstComponents) ?? Date()
                            let endDate = Calendar.current.date(from: lastComponents) ?? Date()
                            
                            return startDate...endDate
                        }(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    
                    Spacer()
                }
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
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
    @Namespace private var viewToggleNamespace
    
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
                                selectedDateInSeries = nil
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
                
                // --- Centered Navigation ---
                if showingSeriesView {
                    // Simple title for main events view
                    Text("Series")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.white)
                } else {
                    // Date Navigation for series detail view
                    HStack(spacing: 16) {
                        // Previous Date Button
                        Button(action: {
                            navigateToDateInSeries(direction: -1)
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(canNavigateToDateInSeries(direction: -1) ? 0.1 : 0.05))
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(canNavigateToDateInSeries(direction: -1) ? .white : .white.opacity(0.3))
                            }
                        }
                        .disabled(!canNavigateToDateInSeries(direction: -1))
                        
                        // Date Display (Clickable)
                        Button(action: {
                            showingDatePicker = true
                        }) {
                            VStack(alignment: .center, spacing: 2) {
                                Text(selectedSeriesName ?? "Events")
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                                Text(currentDateInSeriesDisplay)
                                   .font(.system(size: 16, weight: .bold, design: .default))
                                    .foregroundColor(.white)
                                   .lineLimit(1)
                            }
                        }
                        .frame(minWidth: 120)
                        
                        // Next Date Button
                        Button(action: {
                            navigateToDateInSeries(direction: 1)
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(canNavigateToDateInSeries(direction: 1) ? 0.1 : 0.05))
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(canNavigateToDateInSeries(direction: 1) ? .white : .white.opacity(0.3))
                            }
                        }
                        .disabled(!canNavigateToDateInSeries(direction: 1))
                    }
                }
                
                Spacer()
                
                // Trailing Section - Filter
                HStack {
                    if !showingSeriesView {
                        // Buy-in Filter
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
                            // Calculate current date event count for this series
                            let currentDateEvents = events.filter { $0.simpleDate == currentSystemSimpleDate }
                            
                            SeriesCardView(
                                seriesName: seriesName,
                                totalEventCount: events.count,
                                currentDateEventCount: currentDateEvents.count,
                                events: events,
                                currentDate: currentSystemSimpleDate,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedSeriesName = seriesName
                                        showingSeriesView = false
                                        selectedDateInSeries = nil // Reset date selection for new series
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
        VStack(spacing: 0) {
            // View Toggle Bar (Box vs List)
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isListViewMode = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.grid.1x2")
                            .font(.system(size: 12, weight: .medium))
                        Text("Box")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                    }
                    .foregroundColor(!isListViewMode ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if !isListViewMode {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                                    .matchedGeometryEffect(id: "viewToggleBackground", in: viewToggleNamespace)
                            }
                        }
                    )
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isListViewMode = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12, weight: .medium))
                        Text("List")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                    }
                    .foregroundColor(isListViewMode ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if isListViewMode {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                                    .matchedGeometryEffect(id: "viewToggleBackground", in: viewToggleNamespace)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            

            
        ScrollViewReader { proxy in
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
            } else if isListViewMode {
                // List View - Show all dates with dividers
                LazyVStack(spacing: 0) {
                    ForEach(sortedDatesForSeries, id: \.self) { date in
                        if let eventsForDate = eventsGroupedByDateForSeries[date] {
                            // Date Section Header
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(date.displayMedium)
                                        .font(.system(size: 18, weight: .bold, design: .default))
                                        .foregroundColor(.white)
                                    
                                    Text(relativeDateStringForSimpleDate(date))
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
                            .padding(.top, date == sortedDatesForSeries.first ? 8 : 24)
                            .padding(.bottom, 12)
                            .id("date_\(date.year)_\(date.month)_\(date.day)") // ID for scrolling
                            
                            // Events for this date - List View
                            VStack(spacing: 8) {
                                ForEach(eventsForDate.sorted { $0.event_name < $1.event_name }) { event in
                                    EventListItemView(event: event, onSelect: {
                                        if let onEventSelected = onEventSelected {
                                            onEventSelected(event)
                                        } else {
                                            selectedEvent = event
                                            showingEventDetail = true
                                        }
                                    })
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Bottom padding
                    Color.clear.frame(height: 100)
                }
            } else {
                // Box View - Show only events for selected date
                VStack(spacing: 14) {
                    let currentDate = selectedDateInSeries ?? sortedDatesForSeries.first
                    if let currentDate = currentDate, 
                       let eventsForCurrentDate = eventsGroupedByDateForSeries[currentDate] {
                        ForEach(eventsForCurrentDate.sorted { $0.event_name < $1.event_name }) { event in
                            EventCardView(event: event, onSelect: {
                                if let onEventSelected = onEventSelected {
                                    onEventSelected(event)
                                } else {
                                    selectedEvent = event
                                    showingEventDetail = true
                                }
                            })
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
            .onChange(of: selectedDateInSeries) { newDate in
                if let date = newDate, isListViewMode {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo("date_\(date.year)_\(date.month)_\(date.day)", anchor: .top)
                    }
                }
            }
            .onAppear {
                // Set initial selected date to current date if available, otherwise first date
                if selectedDateInSeries == nil && !sortedDatesForSeries.isEmpty {
                    // Try to find current date in the series
                    if sortedDatesForSeries.contains(currentSystemSimpleDate) {
                        selectedDateInSeries = currentSystemSimpleDate
                    } else {
                        selectedDateInSeries = sortedDatesForSeries.first
                    }
                }
            }
        }
        }
    }
    
    // Helper function to convert SimpleDate to relative date string
    private func relativeDateStringForSimpleDate(_ simpleDate: SimpleDate) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Convert SimpleDate to Date for comparison
        var dateComponents = DateComponents()
        dateComponents.year = simpleDate.year
        dateComponents.month = simpleDate.month
        dateComponents.day = simpleDate.day
        
        guard let eventDate = calendar.date(from: dateComponents) else {
            return ""
        }
        
        let eventDateStart = calendar.startOfDay(for: eventDate)
        
        if calendar.isDate(eventDateStart, inSameDayAs: today) {
            return "Today"
        } else if calendar.isDate(eventDateStart, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) {
            return "Tomorrow"
        } else if calendar.isDate(eventDateStart, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
            return "Yesterday"
        } else {
            let daysFromToday = calendar.dateComponents([.day], from: today, to: eventDateStart).day ?? 0
            if daysFromToday > 0 {
                return "In \(daysFromToday) day\(daysFromToday == 1 ? "" : "s")"
            } else {
                return "\(-daysFromToday) day\(daysFromToday == -1 ? "" : "s") ago"
            }
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
    
    // MARK: - Series Date Navigation Helpers
    private func canNavigateToDateInSeries(direction: Int) -> Bool {
        let currentDate = selectedDateInSeries ?? sortedDatesForSeries.first
        guard let currentDate = currentDate else { return false }
        
        if let currentIndex = sortedDatesForSeries.firstIndex(of: currentDate) {
            let newIndex = currentIndex + direction
            return newIndex >= 0 && newIndex < sortedDatesForSeries.count
        }
        return false
    }
    
    private func navigateToDateInSeries(direction: Int) {
        let currentDate = selectedDateInSeries ?? sortedDatesForSeries.first
        guard let currentDate = currentDate else { return }
        
        if let currentIndex = sortedDatesForSeries.firstIndex(of: currentDate) {
            let newIndex = currentIndex + direction
            if newIndex >= 0 && newIndex < sortedDatesForSeries.count {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedDateInSeries = sortedDatesForSeries[newIndex]
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
            if userEventService.isLoading || isLoadingMyEvents {
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
            } else if allUserEvents.isEmpty && userEventService.publicEventRSVPs.isEmpty {
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
                MyEventsCalendarView(
                    events: allCombinedEventItems,
                    selectedDate: Binding(
                        get: { calendarSelectedDate },
                        set: { newDate in
                            let calendar = Calendar.current
                            let selectedDay = calendar.startOfDay(for: newDate)
                            let previousDay = calendar.startOfDay(for: calendarSelectedDate)
                            
                            calendarSelectedDate = newDate
                            
                            // If clicking on the same date that's already selected, toggle back to month view
                            if selectedDay == previousDay && isCalendarDaySelected {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isCalendarDaySelected = false
                                }
                            } else {
                                // Select the new date and show day view
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isCalendarDaySelected = true
                                }
                            }
                        }
                    )
                )
                .padding(.bottom, 12)

                if isCalendarDaySelected {
                    // Day View - Show events for selected date
                    dayViewContent
                } else {
                    // Month View - Show all upcoming events in chronological order
                    monthViewContent
                }
                
                // Bottom padding
                Color.clear.frame(height: 100)
            }
        }
    }
    
    // MARK: - Day View Content
    private var dayViewContent: some View {
        let eventsForDate = eventsForSelectedCalendarDate
        
        return Group {
            // Back to Month View Button
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isCalendarDaySelected = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Back to Month")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            if !eventsForDate.isEmpty {
                // Date Section Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDateHeader(calendarSelectedDate))
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        
                        Text(relativeDateString(calendarSelectedDate))
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
            } else {
                VStack {
                    Spacer(minLength: 20)
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        .padding(.bottom, 10)
                    Text("No Events on This Day")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Month View Content
    private var monthViewContent: some View {
        Group {
            if upcomingEventsForMonth.isEmpty {
                VStack {
                    Spacer(minLength: 20)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        .padding(.bottom, 16)
                    
                    Text("No Upcoming Events")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                    
                    Text("Your events for this month will appear here")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
            } else {
                // Show upcoming events grouped by date
                ForEach(upcomingEventsGroupedByDate.keys.sorted(), id: \.self) { date in
                    if let eventsForDate = upcomingEventsGroupedByDate[date] {
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
                        .padding(.top, date == upcomingEventsGroupedByDate.keys.sorted().first ? 8 : 24)
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
            }
        }
    }
    
    // MARK: - Computed Properties for Schedule
    private var groupedEventsByDate: [Date: [UserEvent]] {
        let calendar = Calendar.current
        return Dictionary(grouping: allUserEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
    }
    
    // MARK: - Combined Event Item for Mixed Schedule
    private var allCombinedEventItems: [CombinedEventItem] {
        var combinedItems: [CombinedEventItem] = []
        
        // Add UserEvents
        for userEvent in allUserEvents {
            combinedItems.append(CombinedEventItem(userEvent: userEvent))
        }
        
        // Add Public Event RSVPs (all of them)
        for rsvp in userEventService.publicEventRSVPs {
            // Look up the original event to get complete timing data
            if let originalEvent = viewModel.allEvents.first(where: { $0.id == rsvp.publicEventId }) {
                combinedItems.append(CombinedEventItem(publicEvent: originalEvent, rsvpDate: rsvp.eventDate))
            } else {
                // Create event from RSVP data if original not found
                let fallbackEvent = Event(
                    id: rsvp.publicEventId,
                    buyin_string: "TBD",
                    simpleDate: SimpleDate(
                        year: Calendar.current.component(.year, from: rsvp.eventDate),
                        month: Calendar.current.component(.month, from: rsvp.eventDate),
                        day: Calendar.current.component(.day, from: rsvp.eventDate)
                    ),
                    event_name: rsvp.eventName,
                    series_name: nil,
                    description: nil,
                    time: nil,
                    buyin_usd: nil,
                    casino: nil,
                    chipsFormatted: nil,
                    game: nil,
                    guarantee: nil,
                    guaranteeFormatted: nil,
                    lateRegistration: nil,
                    levelLength: nil,
                    levelsFormatted: nil,
                    pdfLink: nil,
                    seriesEnd: nil,
                    seriesStart: nil,
                    startingChips: nil,
                    imageUrl: nil
                )
                
                combinedItems.append(CombinedEventItem(publicEvent: fallbackEvent, rsvpDate: rsvp.eventDate))
            }
        }
        
        return combinedItems
    }
    
    // MARK: - Combined Grouped Events (UserEvents + Public Event RSVPs)
    private var combinedGroupedEventsByDate: [Date: [CombinedEventItem]] {
        let calendar = Calendar.current
        return Dictionary(grouping: allCombinedEventItems) { item in
            calendar.startOfDay(for: item.date)
        }
    }
    
    // Filter events for the selected date in the new calendar
    private var eventsForSelectedCalendarDate: [CombinedEventItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: calendarSelectedDate)
        return combinedGroupedEventsByDate[startOfDay] ?? []
    }
    
    // Get all upcoming events for the current month in chronological order
    private var upcomingEventsForMonth: [CombinedEventItem] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: calendarSelectedDate)
        let currentYear = calendar.component(.year, from: calendarSelectedDate)
        
        return allCombinedEventItems
            .filter { item in
                // Only show upcoming events (from today forward)
                let itemDate = calendar.startOfDay(for: item.date)
                let today = calendar.startOfDay(for: now)
                let isUpcoming = itemDate >= today
                
                // Check if event is in the selected month/year
                let itemMonth = calendar.component(.month, from: item.date)
                let itemYear = calendar.component(.year, from: item.date)
                let isInSelectedMonth = itemMonth == currentMonth && itemYear == currentYear
                
                return isUpcoming && isInSelectedMonth
            }
            .sorted { $0.date < $1.date }
    }
    
    // Group upcoming events by date for month view
    private var upcomingEventsGroupedByDate: [Date: [CombinedEventItem]] {
        let calendar = Calendar.current
        return Dictionary(grouping: upcomingEventsForMonth) { item in
            calendar.startOfDay(for: item.date)
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
