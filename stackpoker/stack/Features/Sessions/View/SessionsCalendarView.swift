import SwiftUI
import FirebaseFirestore

struct SessionsCalendarView: View {
    @ObservedObject var sessionStore: SessionStore
    @Binding var selectedDate: Date? // Use binding from parent
    @State private var currentMonth: Date
    
    // Initializer to set currentMonth
    init(sessionStore: SessionStore, selectedDate: Binding<Date?>) {
        self.sessionStore = sessionStore
        self._selectedDate = selectedDate
        self._currentMonth = State(initialValue: selectedDate.wrappedValue ?? Date())
    }
    
    // Get PNL for each day in current month
    private var dailyPNL: [String: Double] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var pnlByDate: [String: Double] = [:]
        
        // CORRECT: Loop through ALL sessions, not just the current month's
        for session in sessionStore.sessions {
            let dateKey = formatter.string(from: session.startDate)
            pnlByDate[dateKey, default: 0] += session.profit
        }
        
        return pnlByDate
    }
    
    // Get session count for each day
    private var dailySessionCount: [String: Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var countByDate: [String: Int] = [:]
        
        // CORRECT: Loop through ALL sessions, not just the current month's
        for session in sessionStore.sessions {
            let dateKey = formatter.string(from: session.startDate)
            countByDate[dateKey, default: 0] += 1
        }
        
        return countByDate
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 15) {
                monthNavigationHeader
                calendarGrid
            }
            .padding(.horizontal, 8) // Reduced horizontal padding
            .padding(.bottom, 10)
        }
        .onAppear {
            if sessionStore.sessions.isEmpty {
                sessionStore.fetchSessions()
            }
        }
    }
    
    // MARK: - Month Navigation Header
    private var monthNavigationHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium)) // LARGER
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44) // LARGER
            }
            
            Spacer()
            
            Text(monthYearString)
                .font(.system(size: 20, weight: .semibold)) // LARGER
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .medium)) // LARGER
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44) // LARGER
            }
        }
        .padding(.vertical, 12) // INCREASED PADDING
    }
    
    // MARK: - Calendar Grid
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        var symbols = calendar.shortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday
        
        if symbols.count == 7 {
            let rotatedSymbols = Array(symbols[firstWeekday-1..<symbols.count]) + Array(symbols[0..<firstWeekday-1])
            return rotatedSymbols
        }
        return symbols
    }
    
    private func generateDaysInMonthGrid() -> [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)!.count
        
        let firstWeekdayOfMonth = calendar.component(.weekday, from: firstOfMonth)
        let firstDayOfSystemWeek = calendar.firstWeekday
        
        let weekdayOffset = (firstWeekdayOfMonth - firstDayOfSystemWeek + 7) % 7
        
        var days: [Date?] = []
        
        for _ in 0..<weekdayOffset {
            days.append(nil)
        }
        
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { daySymbol in
                    Text(String(daySymbol.prefix(1)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 5)
            
            let days = generateDaysInMonthGrid()
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        let calendar = Calendar.current
                        let dayComponent = calendar.component(.day, from: date)
                        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
                        let pnl = getPNL(for: date)
                        let sessionCount = getSessionCount(for: date)
                        let isToday = calendar.isDateInToday(date)
                        
                        SessionCalendarDayView(
                            day: dayComponent,
                            isSelected: isSelected,
                            pnl: pnl,
                            sessionCount: sessionCount,
                            isToday: isToday,
                            onTap: {
                                if sessionCount > 0 {
                                    if let selected = selectedDate, calendar.isDate(selected, inSameDayAs: date) {
                                        selectedDate = nil
                                    } else {
                                        selectedDate = date
                                    }
                                }
                            }
                        )
                    } else {
                        Text("")
                            .frame(height: 44)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Helper Functions
    private func getPNL(for date: Date) -> Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        return dailyPNL[dateKey] ?? 0
    }
    
    private func getSessionCount(for date: Date) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        return dailySessionCount[dateKey] ?? 0
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
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

// MARK: - Session Calendar Day View
struct SessionCalendarDayView: View {
    let day: Int
    let isSelected: Bool
    let pnl: Double
    let sessionCount: Int
    let isToday: Bool
    let onTap: () -> Void
    
    private var pnlColor: Color {
        if pnl > 0 {
            return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        } else if pnl < 0 {
            return Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
        } else if sessionCount > 0 {
            return .gray
        } else {
            return .clear
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)

                VStack(spacing: 2) {
                    Text("\(day)")
                        .font(.system(size: 16, weight: isSelected || isToday ? .semibold : .medium))
                        .foregroundColor(textColor)
                    
                    if sessionCount > 0 {
                        // ALWAYS show number for non-zero PNL
                        if pnl != 0 {
                            Text(formatCompactPNL(pnl))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(pnlColor)
                        } else {
                            // Show dot ONLY for break-even days
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
        .frame(height: 44)
        .buttonStyle(PlainButtonStyle())
        .disabled(sessionCount == 0)
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
        } else if sessionCount > 0 {
            return .white.opacity(0.9)
        } else {
            return .white.opacity(0.5)
        }
    }
    
    private func formatCompactPNL(_ amount: Double) -> String {
        let absAmount = abs(amount)
        let sign = amount > 0 ? "+" : ""
        
        if absAmount >= 1000 {
            return "\(sign)\(Int(round(absAmount/1000)))k"
        } else {
            return "\(sign)\(Int(round(absAmount)))"
        }
    }
}

 