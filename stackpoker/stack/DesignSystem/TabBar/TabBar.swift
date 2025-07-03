import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: HomePage.Tab
    let userId: String
    @Binding var showingMenu: Bool
    let tutorialManager: TutorialManager

    var body: some View {
        ZStack {
            // Background color for the tab bar - now nearly transparent to capture touches
            Color.black.opacity(0.01)
                .frame(height: 80) // Increased height to accommodate larger icons and padding
                .edgesIgnoringSafeArea(.bottom) // Extend to the bottom edge

            // Tab buttons
            HStack {
                TabBarButton(
                    icon: "Feed", // Changed to asset name
                    isSelected: selectedTab == .feed,
                    action: { selectedTab = .feed },
                    tutorialManager: tutorialManager
                )

                TabBarButton(
                    icon: "Events", // Changed to calendar/events icon
                    isSelected: selectedTab == .explore,
                    action: { 
                        selectedTab = .explore
                        tutorialManager.userDidAction(.tappedExploreTab)
                    },
                    tutorialManager: tutorialManager
                )

                // Plus button
                AddButton(userId: userId, showingMenu: $showingMenu, tutorialManager: tutorialManager)
                    .padding(.horizontal, 20) // Add some spacing around the plus button


                TabBarButton(
                    icon: "Groups", // Changed to asset name
                    isSelected: selectedTab == .groups,
                    action: { 
                        selectedTab = .groups
                        tutorialManager.userDidAction(.tappedGroupsTab)
                    },
                    tutorialManager: tutorialManager
                )

                TabBarButton(
                    icon: "Profile", // Changed to asset name
                    isSelected: selectedTab == .profile,
                    action: { 
                        selectedTab = .profile
                        tutorialManager.userDidAction(.tappedProfileTab)
                    },
                    tutorialManager: tutorialManager
                )
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 80) // Ensure ZStack respects the increased height
        .padding(.bottom, 20) // Increased bottom padding to move tab bar higher
    }
}

struct TabBarButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    let tutorialManager: TutorialManager?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) { 
                Group {
                    if icon == "Events" {
                        // Use system calendar icon for Events tab
                        Image(systemName: "calendar")
                            .font(.system(size: 25, weight: .medium))
                    } else {
                        // Use asset image for other tabs
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                    }
                }
                .foregroundColor(isSelected ? .white : Color.gray.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
}



struct SleekMenuButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 0.95)))
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.green.opacity(0.25), radius: 12, y: 4)
                        .overlay(
                            Circle()
                                .stroke(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)), lineWidth: 2)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.green.opacity(0.18), radius: 2, y: 1)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}