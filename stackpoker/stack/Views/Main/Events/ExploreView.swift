import SwiftUI
import FirebaseFirestore
import Combine

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

// Old IdentifiableDate struct removed (was lines 4-16)

// 1. Event Model (Updated for SimpleDate)
struct Event: Identifiable, Hashable {
    let id: String 
    let buyin_string: String
    let casino: String
    let city: String?
    let country: String?
    let state: String?
    let simpleDate: SimpleDate
    let name: String
    let series: String?
    let time: String?

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        print("--- Debug Event Init Attempt --- DOC_ID: \(document.documentID)")

        guard let docId = Optional(document.documentID), !docId.isEmpty else {
            print("DEBUG EVENT INIT [FAILED]: Missing or empty document.documentID")
            return nil
        }
        self.id = docId

        guard let buyinStr = data["buyin_string"] as? String, !buyinStr.isEmpty else { 
            print("DEBUG EVENT INIT [FAILED - DOC: \(docId)]: Missing or empty 'buyin_string'. Value: \(String(describing: data["buyin_string"])) ")
            return nil 
        }
        self.buyin_string = buyinStr

        guard let casinoStr = data["casino"] as? String, !casinoStr.isEmpty else { 
            print("DEBUG EVENT INIT [FAILED - DOC: \(docId)]: Missing or empty 'casino'. Value: \(String(describing: data["casino"])) ")
            return nil
        }
        self.casino = casinoStr

        self.city = data["city"] as? String
        self.country = data["country"] as? String
        self.state = data["state"] as? String
        self.series = data["series"] as? String

        guard let dateStringFromFirestore = data["date"] as? String,
              let parsedSimpleDate = SimpleDate(from: dateStringFromFirestore) else { 
            print("DEBUG EVENT INIT [FAILED - DOC: \(docId)]: Could not parse SimpleDate from 'date' string. Value: \(String(describing: data["date"])) ")
            return nil
        }
        self.simpleDate = parsedSimpleDate

        guard let nameStr = data["name"] as? String, !nameStr.isEmpty else { 
            print("DEBUG EVENT INIT [FAILED - DOC: \(docId)]: Missing or empty 'name'. Value: \(String(describing: data["name"])) ")
            return nil
        }
        self.name = nameStr

        let timeValue = data["time"] as? String
        if let t = timeValue, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.time = t
        } else {
            self.time = nil
        }
        
        print("DEBUG EVENT INIT [SUCCESS - DOC: \(docId)]: Successfully initialized event: \(self.name)")
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

struct EventCardView: View {
    let event: Event
    var onSelect: (() -> Void)? // Add a callback for when the card is tapped

    private var locationString: String {
        let city = event.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = event.state?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = event.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var parts: [String] = []
        if !city.isEmpty { parts.append(city) }
        if !state.isEmpty { parts.append(state) }
        if !country.isEmpty { parts.append(country) }

        if parts.isEmpty {
            return "Location Undisclosed"
        } else {
            return parts.joined(separator: ", ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(event.name)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.1))
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Casino", value: event.casino, valueFont: .system(size: 15, weight: .medium, design: .rounded))
                    InfoRow(label: "Location", value: locationString, valueFont: .system(size: 14, weight: .regular, design: .rounded))
                    
                    if let series = event.series, !series.isEmpty {
                        InfoRow(label: "Series", value: series, valueFont: .system(size: 14, weight: .regular, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Date & Time")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.gray.opacity(0.8))
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.gray)
                            Text(event.simpleDate.displayMedium) // Use SimpleDate for display
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                            
                            if let time = event.time, !time.isEmpty {
                                Text("•")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color.gray)
                                Image(systemName: "clock")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.gray)
                                Text(time)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                }
                .layoutPriority(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("BUY-IN")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.gray.opacity(0.7))
                    Text(event.buyin_string)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Color(UIColor(red: 100/255, green: 220/255, blue: 100/255, alpha: 1.0)))
                }
                .frame(minWidth: 80, alignment: .trailing)
            }
        }
        .padding(18)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.4), Color.black.opacity(0.25)]), startPoint: .top, endPoint: .bottom)
                .overlay(Color(UIColor(red: 35/255, green: 37/255, blue: 40/255, alpha: 0.7)))
        )
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.05), Color.white.opacity(0.0)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onTapGesture { // Make the whole card tappable
            onSelect?()
        }
    }
}

class ExploreViewModel: ObservableObject {
    @Published var allEvents: [Event] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // --- New Filter Properties ---
    @Published var selectedCountry: String? = "All Countries" { // Default to "All Countries"
        didSet {
            // Reset state when country changes and update available states
            selectedState = nil 
            updateAvailableStates()
        }
    }
    @Published var selectedState: String? = nil
    @Published var selectedSeriesSet: Set<String> = [] // NEW: For multi-select series
    @Published var selectedBuyinRange: BuyinRange = .all // New property for buy-in range
    @Published var availableCountries: [String] = []
    @Published var availableStates: [String] = []
    @Published var availableSeries: [String] = [] // New property for available series
    // --- End New Filter Properties ---
    
    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>() // For observing changes

    init() {
        // Observe changes to allEvents to update country/state lists
        $allEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAvailableCountries()
                self?.updateAvailableStates()
                self?.updateAvailableSeries() // Call new method
            }
            .store(in: &cancellables)
    }

    private func updateAvailableCountries() {
        let countries = Set(allEvents.compactMap { $0.country?.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }
        self.availableCountries = ["All Countries"] + Array(countries).sorted()
        // If current selectedCountry is no longer valid or nil, and "All Countries" is not the only option,
        // you might want to default to "All Countries" or the first actual country.
        // For now, it will retain selection or be nil.
    }

    private func updateAvailableStates() {
        let states: Set<String>
        if let country = selectedCountry, country != "All Countries" {
            states = Set(allEvents.filter { $0.country == country }.compactMap { $0.state?.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }
        } else {
            // Show all states if "All Countries" or no country is selected, or only states for selected country if it has states
            // For simplicity now, if "All Countries" or no country, show all unique states from all events
            states = Set(allEvents.compactMap { $0.state?.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }
        }
        self.availableStates = ["All States"] + Array(states).sorted()
        // Similar logic for selectedState if it becomes invalid
    }

    private func updateAvailableSeries() {
        guard !allEvents.isEmpty else {
            // self.availableSeries = ["All Series"] // "All Series" will be handled by UI logic now
            self.availableSeries = []
            return
        }

        var seriesCounts: [String: Int] = [:]
        for event in allEvents {
            if let series = event.series, !series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

        // self.availableSeries = ["All Series"] + sortedSeries // "All Series" removed from data source
        self.availableSeries = sortedSeries
        
        // If current selectedSeriesSet contains series no longer available, remove them
        let validSeries = Set(self.availableSeries)
        self.selectedSeriesSet = self.selectedSeriesSet.filter { validSeries.contains($0) }
    }

    func fetchEvents() {
        print("--- DEBUG ExploreViewModel: fetchEvents() called ---")
        isLoading = true
        errorMessage = nil
        
        db.collection("events").order(by: "date").getDocuments { [weak self] (querySnapshot, error) in
            print("--- DEBUG ExploreViewModel: Firestore query returned ---")
            guard let self = self else {
                print("--- DEBUG ExploreViewModel: self is nil after query, returning. ---")
                return
            }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Failed to load events: \(error.localizedDescription)"
                    print("--- DEBUG ExploreViewModel: Firestore error: \(error.localizedDescription) ---")
                    return
                }
                guard let documents = querySnapshot?.documents else {
                    self.errorMessage = "No event documents found in 'events_parsed'."
                    print("--- DEBUG ExploreViewModel: No documents found in 'events_parsed'. ---")
                    return
                }
                
                print("--- DEBUG ExploreViewModel: Received \(documents.count) documents from Firestore. Attempting to parse... ---")
                
                let parsedEvents = documents.compactMap { Event(document: $0) }
                print("--- DEBUG ExploreViewModel: Successfully parsed \(parsedEvents.count) events out of \(documents.count) documents. ---")

                self.allEvents = parsedEvents
                
                if self.allEvents.isEmpty && documents.count > 0 {
                     self.errorMessage = "Event data could not be processed or all events had empty buy-ins/invalid dates. Check console for details."
                     print("--- DEBUG ExploreViewModel: Error - Event data could not be processed or all events had invalid data (allEvents.isEmpty is true, documents.count > 0). Check Event init logs. ---")
                } else if self.allEvents.isEmpty {
                    self.errorMessage = "No events available (or all had empty buy-ins/invalid dates)."
                    print("--- DEBUG ExploreViewModel: No events available (allEvents.isEmpty is true, documents.count is 0 or all failed parsing). Check Event init logs. ---")
                } else {
                    print("--- DEBUG ExploreViewModel: Successfully loaded \(self.allEvents.count) events. ---")
                    // Optionally clear errorMessage if it was set from a previous failed attempt
                    // self.errorMessage = nil 
                }
            }
        }
    }
}

// --- Custom SimpleDateHeaderPicker View ---
struct SimpleDateHeaderPicker: View {
    var availableDates: [IdentifiableSimpleDate]
    @Binding var selectedDate: SimpleDate?
    // TODO: Pass in font names as parameters if Jakarta is used elsewhere for consistency

    @State private var isExpanded: Bool = false

    private var displayString: String {
        if let date = selectedDate {
            return date.displayMedium
        } else if let firstDate = availableDates.first?.simpleDate {
            return firstDate.displayMedium
        } else {
            return "Select Date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable Header Row
            HStack(spacing: 4) {
                Text("Events On")
                    // TODO: Replace with .font(.custom("YourJakartaFontName-Bold", size: 22))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(displayString) 
                    // TODO: Replace with .font(.custom("YourJakartaFontName-Bold", size: 22))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
            }
            .padding(.vertical, 8) // Padding for the tappable area
            .contentShape(Rectangle()) // Makes the whole HStack tappable
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }

            // Expanded List of Dates
            if isExpanded {
                ScrollView { // Wrap the list in a ScrollView
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(availableDates) { identifiableDate in
                            Button(action: {
                                self.selectedDate = identifiableDate.simpleDate
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    self.isExpanded = false
                                }
                            }) {
                                HStack {
                                    Text(identifiableDate.simpleDate.displayMedium)
                                        // TODO: Replace with .font(.custom("YourJakartaFontName-Regular", size: 16))
                                        .font(.system(size: 16, weight: selectedDate == identifiableDate.simpleDate ? .bold : .regular, design: .rounded))
                                        .foregroundColor(selectedDate == identifiableDate.simpleDate ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .white.opacity(0.8))
                                    Spacer()
                                    if selectedDate == identifiableDate.simpleDate {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 10) // Padding within list items
                                .background(Color.black.opacity(selectedDate == identifiableDate.simpleDate ? 0.15 : 0.05))
                                .cornerRadius(8)
                            }
                            .padding(.vertical, 2) // Spacing between items
                        }
                    }
                }
                .padding(8) // Padding around the list itself
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor(red: 40/255, green: 42/255, blue: 45/255, alpha: 1.0))) // Darker background for dropdown
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                )
                // Add maxHeight to the ScrollView itself
                .frame(maxHeight: UIScreen.main.bounds.height * 0.4) // e.g., max 40% of screen height
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                .zIndex(1) // Ensure dropdown appears above other content if needed
            }
        }
    }
}
// --- End Custom SimpleDateHeaderPicker View ---

struct ExploreView: View {
    @State private var placeholderSearchText = "" 
    @StateObject private var viewModel = ExploreViewModel()
    @State private var selectedSimpleDate: SimpleDate? = nil
    var onEventSelected: ((Event) -> Void)? // Callback for when an event is selected
    var isSheetPresentation: Bool = false // New parameter to control top padding
    @Environment(\.dismiss) var dismiss // To dismiss the view if used as a sheet

    // --- Computed Property for Dynamic Header Title / Date Picker Label ---
    private var selectedDateDisplayString: String { 
        if let date = selectedSimpleDate {
            return date.displayMedium
        } else if let firstDate = identifiableUniqueSimpleDates.first?.simpleDate {
            return firstDate.displayMedium
        } else if !viewModel.allEvents.isEmpty {
            return "A Date" // More active phrasing
        }
        return "No Dates"
    }
    // --- End Dynamic Header Title ---

    private var identifiableUniqueSimpleDates: [IdentifiableSimpleDate] {
        let uniqueDatesSet = Set(viewModel.allEvents.map { $0.simpleDate })
        return Array(uniqueDatesSet).sorted().map { IdentifiableSimpleDate(simpleDate: $0) }
    }

    // Changed to use SimpleDate for filtering
    private var filteredEvents: [Event] {
        var eventsToFilter = viewModel.allEvents

        // --- Helper for parsing buyin_string to Double ---
        func parseBuyinToDouble(_ buyinString: String) -> Double? {
            let cleanedString = buyinString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            return Double(cleanedString)
        }
        // --- End Helper ---

        // --- Apply Country Filter ---
        if let country = viewModel.selectedCountry, country != "All Countries" {
            eventsToFilter = eventsToFilter.filter { $0.country == country }
        }

        // --- Apply State Filter ---
        // Only apply state filter if a specific country is selected (or adjust if "All States" for "All Countries" has a different meaning)
        if let country = viewModel.selectedCountry, country != "All Countries", let state = viewModel.selectedState, state != "All States" {
            eventsToFilter = eventsToFilter.filter { $0.state == state }
        } else if (viewModel.selectedCountry == nil || viewModel.selectedCountry == "All Countries"), let state = viewModel.selectedState, state != "All States" {
            // If "All Countries" is selected, filter by state across all countries
            eventsToFilter = eventsToFilter.filter { $0.state == state }
        }

        // --- Apply Series Filter (Multi-select) ---
        if !viewModel.selectedSeriesSet.isEmpty {
            eventsToFilter = eventsToFilter.filter { seriesName in
                guard let eventSeries = seriesName.series else { return false }
                return viewModel.selectedSeriesSet.contains(eventSeries)
            }
        }

        // --- Apply Buy-in Filter ---
        if viewModel.selectedBuyinRange != .all {
            eventsToFilter = eventsToFilter.filter { event in
                if let numericBuyin = parseBuyinToDouble(event.buyin_string) {
                    return viewModel.selectedBuyinRange.contains(numericBuyin)
                }
                return false // If buy-in can't be parsed, exclude it unless filter is "All"
            }
        }
        // --- End Filter Logic ---

        let eventsForSelectedDate: [Event]
        let dateToFilterOn = selectedSimpleDate ?? identifiableUniqueSimpleDates.first?.simpleDate

        if let currentFilterDate = dateToFilterOn {
            eventsForSelectedDate = eventsToFilter.filter { $0.simpleDate == currentFilterDate }
        } else {
            eventsForSelectedDate = [] // Or eventsToFilter if you want to show all when no date is selected and no dates exist
        }
        
        return eventsForSelectedDate.sorted { (event1, event2) -> Bool in
            // Safely handle optional country
            let event1Country = event1.country?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let event2Country = event2.country?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""

            let event1IsAmerican = event1Country == "USA" || event1Country == "UNITED STATES"
            let event2IsAmerican = event2Country == "USA" || event2Country == "UNITED STATES"

            if event1IsAmerican && !event2IsAmerican {
                return true
            } else if !event1IsAmerican && event2IsAmerican {
                return false
            }
            return event1.name.localizedCompare(event2.name) == .orderedAscending
        }
    }
    
    // Changed to take SimpleDate
    private func formatDateForSlider(_ simpleDate: SimpleDate) -> String {
        return simpleDate.displayShort // e.g., "May 24"
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView() 
            
            VStack(spacing: 0) {
                // --- Header: Date Picker & Search Icon ---
                HStack(spacing: 6) {
                    // --- Replace old Picker with Custom SimpleDateHeaderPicker ---
                    if !identifiableUniqueSimpleDates.isEmpty {
                        SimpleDateHeaderPicker(availableDates: identifiableUniqueSimpleDates, selectedDate: $selectedSimpleDate)
                    } else {
                        // Fallback if no dates: "Events On No Dates"
                        Text("Events On \(selectedDateDisplayString)") 
                           // TODO: Replace with .font(.custom("YourJakartaFontName-Bold", size: 22))
                           .font(.system(size: 22, weight: .bold, design: .rounded))
                           .foregroundColor(.gray) 
                           .lineLimit(1)
                    }
                    // --- End Custom Picker Replacement ---
                    
                    Spacer()
                    
                    Button(action: {
                        // TODO: Implement search action
                        print("Search icon tapped")
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, isSheetPresentation ? 75 : 35) // Add extra top padding when presented as sheet
                .padding(.bottom, 10) // Reduced bottom padding for header
                // --- End Header ---
                
                // --- Custom Date Picker List ---
                // if isDatePickerExpanded { ... } // ENTIRE BLOCK REMOVED
                // --- End Custom Date Picker List ---
                
                // --- Filter Pickers (Country, State, AND NOW DATE) ---
                if !viewModel.isLoading && !viewModel.allEvents.isEmpty {
                    HStack(spacing: 10) {
                        // Country Picker
                        Picker(selection: $viewModel.selectedCountry) {
                            ForEach(viewModel.availableCountries, id: \.self) { countryName in
                                Text(countryName).tag(countryName as String?)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(viewModel.selectedCountry ?? "All Countries")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.gray)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .frame(minWidth: 140)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .accentColor(.white)
                        
                        // State Picker
                        if viewModel.selectedCountry != nil && viewModel.selectedCountry != "All Countries" && viewModel.availableStates.count > 1 {
                            Picker(selection: $viewModel.selectedState) {
                                ForEach(viewModel.availableStates, id: \.self) { stateName in
                                    Text(stateName).tag(stateName as String?)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(viewModel.selectedState ?? "All States")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                                .frame(minWidth: 110)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .accentColor(.white)
                            .transition(.opacity.combined(with: .slide))
                        }

                        // Buy-in Picker
                        Picker(selection: $viewModel.selectedBuyinRange) {
                            ForEach(BuyinRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(viewModel.selectedBuyinRange.rawValue)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .frame(minWidth: 120)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .accentColor(.white)
                        
                        Spacer() // Push pickers to the left
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.selectedCountry)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.availableStates)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.selectedBuyinRange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                // --- End Country/State Filter Pickers ---

                // --- NEW: Multi-Select Series Horizontal Scroller ---
                if !viewModel.isLoading && !viewModel.availableSeries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // "All Series" Button
                            Button(action: {
                                viewModel.selectedSeriesSet.removeAll()
                            }) {
                                Text("All Series")
                                    .font(.system(size: 14, weight: viewModel.selectedSeriesSet.isEmpty ? .bold : .medium, design: .rounded))
                                    .foregroundColor(viewModel.selectedSeriesSet.isEmpty ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(viewModel.selectedSeriesSet.isEmpty ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(viewModel.selectedSeriesSet.isEmpty ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)).opacity(0.5) : Color.clear, lineWidth: 1.5)
                                    )
                            }

                            ForEach(viewModel.availableSeries, id: \.self) { seriesName in
                                Button(action: {
                                    if viewModel.selectedSeriesSet.contains(seriesName) {
                                        viewModel.selectedSeriesSet.remove(seriesName)
                                    } else {
                                        viewModel.selectedSeriesSet.insert(seriesName)
                                    }
                                }) {
                                    Text(seriesName)
                                        .font(.system(size: 14, weight: viewModel.selectedSeriesSet.contains(seriesName) ? .bold : .medium, design: .rounded))
                                        .foregroundColor(viewModel.selectedSeriesSet.contains(seriesName) ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .white)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(viewModel.selectedSeriesSet.contains(seriesName) ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(viewModel.selectedSeriesSet.contains(seriesName) ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)).opacity(0.5) : Color.clear, lineWidth: 1.5)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 50) // Give the scroller a fixed height
                    .padding(.bottom, 15)
                    .animation(.default, value: viewModel.selectedSeriesSet) // Animate changes to selection
                }
                // --- End Multi-Select Series Horizontal Scroller ---

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading Events...")
                        .foregroundColor(.gray)
                        .padding(.top, 8)
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
                } else if filteredEvents.isEmpty {
                    VStack {
                        Spacer(minLength: 50)
                        Image(systemName: identifiableUniqueSimpleDates.isEmpty ? "calendar.badge.plus" : "calendar.badge.exclamationmark")
                                .font(.system(size: 50))
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .padding(.bottom, 10)
                        Text(identifiableUniqueSimpleDates.isEmpty ? "No Events Available" : "No Events for Selected Date")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(filteredEvents) { event in 
                                EventCardView(event: event, onSelect: {
                                    onEventSelected?(event) // Call the callback
                                    // Dismissal will be handled by the presenting view if needed,
                                    // or uncomment below if ExploreView should always dismiss itself on selection
                                    // if onEventSelected != nil { dismiss() }
                                })
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .onAppear {
            viewModel.fetchEvents()
            // Auto-select the first date if nothing is selected and dates are available
            if selectedSimpleDate == nil, let firstAvailableDate = identifiableUniqueSimpleDates.first?.simpleDate {
                selectedSimpleDate = firstAvailableDate
            }
        }
        .onChange(of: viewModel.allEvents) { _ in 
            // If selectedSimpleDate is nil or not in the new set of dates, try to select the first available date.
            let currentSelectionStillValid = identifiableUniqueSimpleDates.contains { $0.simpleDate == selectedSimpleDate }
            if selectedSimpleDate == nil || !currentSelectionStillValid {
                 selectedSimpleDate = identifiableUniqueSimpleDates.first?.simpleDate
            }
        }
    }
}

#Preview {
    ExploreView()
} 
