import SwiftUI
import FirebaseAuth

struct EventInvitesView: View {
    @EnvironmentObject var userEventService: UserEventService
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom navigation header
                HStack {
                    Text("Event Invites")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                if userEventService.pendingInvites.isEmpty && !isLoading {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Pending Invites")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("When someone invites you to an event, it will appear here.")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                } else {
                    // Invites list
                    ScrollView {
                        VStack(spacing: 16) {
                            // Add top spacing
                            Color.clear.frame(height: 20)
                            
                            ForEach(userEventService.pendingInvites) { invite in
                                EventInviteCard(
                                    invite: invite,
                                    onAccept: {
                                        acceptInvite(inviteId: invite.id)
                                    },
                                    onDecline: {
                                        declineInvite(inviteId: invite.id)
                                    }
                                )
                            }
                            
                            // Bottom padding
                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .onAppear {
            fetchInvites()
        }
        .refreshable {
            fetchInvites()
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(error ?? "An unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func fetchInvites() {
        isLoading = true
        error = nil
        
        Task {
            do {
                try await userEventService.fetchPendingEventInvites()
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func acceptInvite(inviteId: String) {
        Task {
            do {
                try await userEventService.acceptEventInvite(inviteId: inviteId)
                try? await userEventService.fetchUserEvents()
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func declineInvite(inviteId: String) {
        Task {
            do {
                try await userEventService.declineEventInvite(inviteId: inviteId)
                try? await userEventService.fetchUserEvents()
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct EventInviteCard: View {
    let invite: EventInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @StateObject private var userEventService = UserEventService()
    @State private var event: UserEvent?
    @State private var isLoadingEvent = true
    @State private var isProcessing = false
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatInviteDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Invite header
            HStack(spacing: 12) {
                // Event type icon
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
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: event?.eventType.icon ?? "calendar")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(invite.inviterName) invited you")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Sent \(formatInviteDate(invite.sentAt))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Invite method badge
                Text(invite.inviteMethod.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.8))
                    )
            }
            
            // Event details
            if let event = event {
                VStack(alignment: .leading, spacing: 12) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .lineLimit(3)
                    }
                    
                    HStack(spacing: 16) {
                        // Date info
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                            
                            Text(formatDate(event.startDate))
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        
                        // Location info
                        if let location = event.location, !location.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "location")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                                
                                Text(location)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // Participant info
                    if let maxParticipants = event.maxParticipants {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                            
                            Text("\(event.currentParticipants)/\(maxParticipants) participants")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }
                }
            } else if isLoadingEvent {
                // Loading placeholder
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 20)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 16)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 16)
                        .frame(maxWidth: 200)
                        .cornerRadius(4)
                }
                .redacted(reason: .placeholder)
            } else {
                Text("Event details unavailable")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .italic()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    isProcessing = true
                    onDecline()
                }) {
                    Text("Decline")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.8))
                        )
                }
                .disabled(isProcessing)
                
                Button(action: {
                    isProcessing = true
                    onAccept()
                }) {
                    Text("Accept")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
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
                        )
                }
                .disabled(isProcessing)
            }
            .opacity(isProcessing ? 0.6 : 1.0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.1),
                            Color.clear,
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            loadEventDetails()
        }
    }
    
    private func loadEventDetails() {
        isLoadingEvent = true
        
        Task {
            do {
                let fetchedEvent = try await userEventService.fetchEvent(eventId: invite.eventId)
                await MainActor.run {
                    self.event = fetchedEvent
                    self.isLoadingEvent = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingEvent = false
                }
            }
        }
    }
}

#Preview {
    EventInvitesView()
} 