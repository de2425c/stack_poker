import SwiftUI

struct MyEventsCalendarView: View {
    let events: [CombinedEventItem]
    @Binding var selectedDate: Date
    @State private var currentMonth: Date
    
    // Initializer to set currentMonth
    init(events: [CombinedEventItem], selectedDate: Binding<Date>) {
        self.events = events
        self._selectedDate = selectedDate
        self._currentMonth = State(initialValue: selectedDate.wrappedValue)
    }
    
    // Get event count for each day in current month
    private var dailyEventCount: [String: Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var countByDate: [String: Int] = [:]
        
        // Loop through ALL events, not just the current month's
        for eventItem in events {
            let dateKey = formatter.string(from: eventItem.date)
            countByDate[dateKey, default: 0] += 1
        }
        
        return countByDate
    }
    
    // Calculate total event count for current month
    private var monthlyEventCount: Int {
        let calendar = Calendar.current
        
        var total: Int = 0
        
        for eventItem in events {
            if calendar.isDate(eventItem.date, equalTo: currentMonth, toGranularity: .month) {
                total += 1
            }
        }
        
        return total
    }

    var body: some View {
        VStack(spacing: 12) {
            monthNavigationHeader
            calendarGrid
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
    
    // MARK: - Month Navigation Header
    private var monthNavigationHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(monthYearString)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(formatMonthlyEventCount(monthlyEventCount))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                }
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
            }
        }
    }
    
    // MARK: - Calendar Grid
    private var weekdaySymbols: [String] {
        return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }
    
    private func generateDaysInMonthGrid() -> [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)!.count
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        
        // Convert to Monday-first indexing (Monday = 0, Sunday = 6)
        let mondayFirstWeekday = (firstWeekday == 1) ? 6 : firstWeekday - 2
        
        var days: [Date?] = []
        
        // Add empty slots for days before the first day of the month
        for _ in 0..<mondayFirstWeekday {
            days.append(nil)
        }
        
        // Add all days of the month
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 10) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { daySymbol in
                    Text(daySymbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar days
            let days = generateDaysInMonthGrid()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        let calendar = Calendar.current
                        let dayComponent = calendar.component(.day, from: date)
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let eventCount = getEventCount(for: date)
                        let isToday = calendar.isDateInToday(date)
                        
                        MyEventsCalendarDayView(
                            day: dayComponent,
                            isSelected: isSelected,
                            eventCount: eventCount,
                            isToday: isToday,
                            onTap: {
                                selectedDate = date
                            }
                        )
                    } else {
                        Text("")
                            .frame(height: 48)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getEventCount(for date: Date) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        return dailyEventCount[dateKey] ?? 0
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private func formatMonthlyEventCount(_ count: Int) -> String {
        if count == 0 {
            return "No events"
        } else if count == 1 {
            return "1 event"
        } else {
            return "\(count) events"
        }
    }
    
    private func previousMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentMonth = newDate
            }
        }
    }
    
    private func nextMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentMonth = newDate
            }
        }
    }
}

// MARK: - My Events Calendar Day View
struct MyEventsCalendarDayView: View {
    let day: Int
    let isSelected: Bool
    let eventCount: Int
    let isToday: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textColor)
                
                if eventCount > 0 {
                    Text("\(eventCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var backgroundColor: Color {
        if eventCount > 0 {
            return Color(red: 64/255, green: 156/255, blue: 255/255) // Blue for events
        } else if isToday {
            return Color.blue.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private var textColor: Color {
        if eventCount > 0 {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .white.opacity(0.6)
        }
    }
} 