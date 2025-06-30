import SwiftUI
import FirebaseAuth

struct EventHistoryView: View {
    let completedEvents: [UserEvent]
    let completedPublicEventRSVPs: [PublicEventRSVP]
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedUserEvent: UserEvent? = nil
    
    // MARK: - Combined History Items
    private struct HistoryItem: Identifiable {
        let id = UUID()
        let date: Date
        let isUserEvent: Bool
        let userEvent: UserEvent?
        let publicEventRSVP: PublicEventRSVP?
        
        init(userEvent: UserEvent) {
            self.date = userEvent.startDate
            self.isUserEvent = true
            self.userEvent = userEvent
            self.publicEventRSVP = nil
        }
        
        init(publicEventRSVP: PublicEventRSVP) {
            self.date = publicEventRSVP.eventDate
            self.isUserEvent = false
            self.userEvent = nil
            self.publicEventRSVP = publicEventRSVP
        }
    }
    
    private var allHistoryItems: [HistoryItem] {
        var items: [HistoryItem] = []
        
        // Add completed UserEvents
        items.append(contentsOf: completedEvents.map { HistoryItem(userEvent: $0) })
        
        // Add completed public event RSVPs
        items.append(contentsOf: completedPublicEventRSVPs.map { HistoryItem(publicEventRSVP: $0) })
        
        // Sort by date, most recent first
        return items.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom navigation header
                HStack {
                    Text("Event History")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Content
                if allHistoryItems.isEmpty {
                    VStack {
                        Spacer(minLength: 50)
                        Image(systemName: "clock")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                            .padding(.bottom, 16)
                        
                        Text("No Completed Events")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
                        
                        Text("Your completed events will appear here")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(allHistoryItems) { historyItem in
                                if historyItem.isUserEvent, let userEvent = historyItem.userEvent {
                                    UserEventCardView(event: userEvent, onSelect: {
                                        selectedUserEvent = userEvent
                                    })
                                        .environmentObject(userEventService)
                                        .environmentObject(userService)
                                        .environmentObject(sessionStore)
                                } else if let publicRSVP = historyItem.publicEventRSVP {
                                    // Create a fake Event for display
                                    let calendar = Calendar.current
                                    let fakeEvent = Event(
                                        id: publicRSVP.publicEventId,
                                        buyin_string: "TBD",
                                        simpleDate: SimpleDate(
                                            year: calendar.component(.year, from: publicRSVP.eventDate),
                                            month: calendar.component(.month, from: publicRSVP.eventDate),
                                            day: calendar.component(.day, from: publicRSVP.eventDate)
                                        ),
                                        event_name: publicRSVP.eventName,
                                        series_name: nil,
                                        description: nil,
                                        time: nil,
                                        buyin_usd: nil
                                    )
                                    
                                    EventCardView(event: fakeEvent, onSelect: {
                                        // Could show detail if needed
                                    })
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .sheet(item: $selectedUserEvent) { userEvent in
            UserEventDetailView(event: userEvent)
                .environmentObject(userEventService)
                .environmentObject(userService)
        }
    }
}

#Preview {
    EventHistoryView(completedEvents: [], completedPublicEventRSVPs: [])
        .environmentObject(UserEventService())
        .environmentObject(UserService())
        .environmentObject(SessionStore(userId: "preview"))
} 