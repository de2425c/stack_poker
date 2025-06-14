import SwiftUI
import FirebaseAuth

struct EventInviteView: View {
    let event: UserEvent
    @EnvironmentObject var userEventService: UserEventService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var groupService: GroupService
    @Environment(\.dismiss) var dismiss

    @State private var showingInviteUsers = false
    @State private var showingInviteGroup = false
    @State private var showCopiedMessage = false

    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Invite to \(event.title)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("Share your event with others")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                    ScrollView {
                        VStack(spacing: 24) {
                            // Invite Actions
                            VStack(spacing: 16) {
                                Button(action: { showingInviteUsers = true }) {
                                    inviteOptionRow(icon: "person.badge.plus", title: "Invite Users", subtitle: "Directly invite by username")
                                }
                                
                                Button(action: { showingInviteGroup = true }) {
                                    inviteOptionRow(icon: "person.3", title: "Invite a Group", subtitle: "Invite all members of a group")
                                }
                            }

                            // Share Link Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Share Link")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)

                                HStack {
                                    Text("https://stackpoker.gg/events/\(event.id)")
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Button(action: copyLink) {
                                        Text(showCopiedMessage ? "Copied!" : "Copy")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(showCopiedMessage ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color(red: 64/255, green: 156/255, blue: 255/255))
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                
                                // Informational blurb about sharing with non-app users
                                Text("Share this link with anyone, even if they don't have the Stack app. They can view and interact with your event through their web browser.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .lineSpacing(4)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Invite & Share")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingInviteUsers) {
                InviteUsersView(event: event)
                    .environmentObject(userEventService)
                    .environmentObject(userService)
            }
            .sheet(isPresented: $showingInviteGroup) {
                InviteGroupView(event: event)
                    .environmentObject(userEventService)
                    .environmentObject(groupService)
            }
        }
    }

    private func inviteOptionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
    }

    private func copyLink() {
        UIPasteboard.general.string = "https://stackpoker.gg/events/\(event.id)"
        withAnimation {
            showCopiedMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                self.showCopiedMessage = false
            }
        }
    }
} 