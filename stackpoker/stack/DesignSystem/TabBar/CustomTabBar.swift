import SwiftUI

// Custom Tab Bar - a reusable component
struct CustomTabBar: View {
    @Binding var selectedTab: HomePage.Tab
    let userId: String
    @Binding var showingMenu: Bool
    @ObservedObject var tutorialManager: TutorialManager
    
    // To animate the plus button
    @State private var plusButtonRotated = false

    var body: some View {
        HStack {
            // Feed Button
            button(for: .feed, systemImage: "house.fill", title: "Feed")
            
            // Explore Button
            button(for: .explore, systemImage: "magnifyingglass", title: "Explore")

            // Center "Add" button with menu
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.blue]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: .purple.opacity(0.5), radius: 10, x: 0, y: 5)
                
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(plusButtonRotated ? 45 : 0))
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showingMenu.toggle()
                    plusButtonRotated.toggle()
                }
            }
            .offset(y: -30)
            
            // Groups Button
            button(for: .groups, systemImage: "person.3.fill", title: "Groups")
            
            // Profile Button
            button(for: .profile, systemImage: "person.crop.circle.fill", title: "Profile")
        }
        .padding(.horizontal)
        .frame(height: 50)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 20)
    }

    private func button(for tab: HomePage.Tab, systemImage: String, title: String) -> some View {
        Button(action: { selectedTab = tab }) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .frame(height: 24)
                
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundColor(selectedTab == tab ? .white : .gray)
        .frame(maxWidth: .infinity)
    }
} 