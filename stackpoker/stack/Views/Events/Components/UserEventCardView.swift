import SwiftUI
import FirebaseAuth // Added for Auth.auth().currentUser?.uid access if needed directly in card
import Kingfisher

// MARK: - User Event Card View
struct UserEventCardView: View {
    let event: UserEvent
    var onSelect: (() -> Void)? = nil
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService

    private let accentColor = Color(red: 64/255, green: 156/255, blue: 255/255)

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy • h:mm a"
        return formatter.string(from: event.startDate)
    }
    
    private var statusPill: some View {
        let currentStatus = event.currentStatus
        return Text(currentStatus.displayName.uppercased())
            .font(.system(size: 9, weight: .bold, design: .default))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    LinearGradient(
                        gradient: Gradient(colors: statusGradientColors(currentStatus)),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: statusColor(currentStatus).opacity(0.3), radius: 3, x: 0, y: 1)
            )
    }

    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Event Image (if available)
                if let imageURL = event.imageURL, let url = URL(string: imageURL) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 100)
                                .cornerRadius(20, corners: [.topLeft, .topRight])
                        }
                        .scaledToFill()
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(20, corners: [.topLeft, .topRight])
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.3)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .cornerRadius(20, corners: [.topLeft, .topRight])
                        )
                }
                
                // MARK: - Header Section
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    
                    HStack(spacing: 10) {
                        Label(event.eventType.displayName, systemImage: event.eventType.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        
                        Label(event.isPublic ? "Public" : "Private", systemImage: event.isPublic ? "globe" : "lock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        statusPill
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // MARK: - Info Section - Condensed
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "calendar", text: formattedDate)

                    if let location = event.location, !location.isEmpty {
                        infoRow(icon: "location.fill", text: location, lineLimit: 1)
                    }

                    infoRow(icon: "person.2.fill", 
                            text: "\(event.currentParticipants) attendee\(event.currentParticipants == 1 ? "" : "s")" + 
                                  (event.maxParticipants != nil ? " / \(event.maxParticipants!) max" : ""))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                
                // MARK: - Footer / Action Hint
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
                .padding(.top, 6)
            }
            .frame(minHeight: 130) // Reduced from 180
            .background(
                ZStack {
                    // Base card with rich black and subtle deep blue hint
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(red: 8/255, green: 12/255, blue: 20/255).opacity(0.9), location: 0.0),
                                    .init(color: Color(red: 12/255, green: 16/255, blue: 28/255).opacity(0.7), location: 0.3),
                                    .init(color: Color(red: 16/255, green: 20/255, blue: 32/255).opacity(0.5), location: 0.6),
                                    .init(color: Color(red: 20/255, green: 24/255, blue: 36/255).opacity(0.4), location: 1.0)
                                ]),
                                startPoint: .center,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                    // Large flowing gradient overlay
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.12), location: 0.0),
                                    .init(color: Color.white.opacity(0.06), location: 0.4),
                                    .init(color: Color.white.opacity(0.02), location: 0.7),
                                    .init(color: Color.clear, location: 1.0)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        
                    // Secondary gradient for depth
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.05), location: 0.0),
                                    .init(color: Color.clear, location: 0.4),
                                    .init(color: Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.02), location: 1.0)
                                ]),
                                startPoint: .center,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                    // Enhanced border gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.25), location: 0.0),
                                    .init(color: Color.white.opacity(0.12), location: 0.3),
                                    .init(color: Color.white.opacity(0.06), location: 0.6),
                                    .init(color: Color.white.opacity(0.02), location: 1.0)
                                ]),
                                startPoint: .center,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func infoRow(icon: String, text: String, lineLimit: Int = 2) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(lineLimit)
        }
    }
    
    private func statusColor(_ status: UserEvent.EventStatus) -> Color {
        switch status {
        case .upcoming: return Color(red: 64/255, green: 156/255, blue: 255/255)
        case .active: return .orange
        case .completed: return Color.blue.opacity(0.8)
        case .cancelled: return Color.red.opacity(0.8)
        }
    }
    
    private func statusGradientColors(_ status: UserEvent.EventStatus) -> [Color] {
        switch status {
        case .upcoming: 
            return [
                Color(red: 64/255, green: 156/255, blue: 255/255),
                Color(red: 100/255, green: 180/255, blue: 255/255)
            ]
        case .active: 
            return [.orange, Color.orange.opacity(0.8)]
        case .completed: 
            return [Color.blue.opacity(0.8), Color.blue.opacity(0.6)]
        case .cancelled: 
            return [Color.red.opacity(0.8), Color.red.opacity(0.6)]
        }
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
} 