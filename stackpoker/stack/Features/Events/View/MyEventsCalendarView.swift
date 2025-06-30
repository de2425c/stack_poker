import SwiftUI

struct MyEventsCalendarView: View {
    let events: [CombinedEventItem]
    @Binding var selectedDate: Date
    @State private var currentMonth: Date

    init(events: [CombinedEventItem], selectedDate: Binding<Date>) {
        self.events = events
        self._selectedDate = selectedDate
        self._currentMonth = State(initialValue: selectedDate.wrappedValue)
    }
    
    private var eventsByDate: [Date: [CombinedEventItem]] {
        let calendar = Calendar.current
        return Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.date)
        }
    }
    
    private func getEventCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return eventsByDate[startOfDay]?.count ?? 0
    }

    var body: some View {
        VStack(spacing: 16) {
            monthNavigationHeader
            calendarGrid
        }
        .padding(.horizontal, 20)
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(monthYearString)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 8)
    }

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(Array(zip(["S", "M", "T", "W", "T", "F", "S"], 0..<7)), id: \.1) { day, index in
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            calendarDaysGrid
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var calendarDaysGrid: some View {
        let calendar = Calendar.current
        
        if let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) {
            let firstOfMonth = monthInterval.start
            let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
            let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Text("").frame(height: 40)
                }
                
                ForEach(1...daysInMonth, id: \.self) { day in
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let eventCount = getEventCount(for: date)
                        let isToday = calendar.isDateInToday(date)
                        
                        MyEventsCalendarDayView(
                            day: day,
                            isSelected: isSelected,
                            eventCount: eventCount,
                            isToday: isToday,
                            onTap: {
                                selectedDate = date
                            }
                        )
                    } else {
                        EmptyView()
                    }
                }
            }
        } else {
            Text("Invalid calendar month")
                .foregroundColor(.gray)
                .padding()
        }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    private func previousMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newDate
        }
    }
}


struct MyEventsCalendarDayView: View {
    let day: Int
    let isSelected: Bool
    let eventCount: Int
    let isToday: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)
                
                Text("\(day)")
                    .font(.system(size: 14, weight: isSelected || isToday ? .semibold : .medium))
                    .foregroundColor(textColor)
                
                if eventCount > 0 && !isSelected {
                    VStack {
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(0..<min(eventCount, 3), id: \.self) { index in
                                Circle()
                                    .fill(dotColor)
                                    .frame(width: 4, height: 4)
                            }
                            if eventCount > 3 {
                                Text("+")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(dotColor)
                            }
                        }
                        .offset(y: -2)
                    }
                }
            }
        }
        .frame(height: 40)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .white.opacity(0.2)
        } else if isToday {
            return .blue.opacity(0.3)
        } else {
            return .clear
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .white.opacity(0.8)
        }
    }
    
    private var dotColor: Color {
        return Color(red: 64/255, green: 156/255, blue: 255/255)
    }
} 