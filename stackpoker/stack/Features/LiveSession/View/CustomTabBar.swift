import SwiftUI

struct LiveSessionTabBar: View {
    @Binding var selectedTab: EnhancedLiveSessionView.LiveSessionTab
    let isPublicSession: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "Session", icon: "timer", tab: .session)
            tabButton(title: "Notes", icon: "note.text", tab: .notes)
            
            // Conditionally show Live or Posts tab
            if isPublicSession {
                tabButton(title: "Live", icon: "eye.fill", tab: .live)
            } else {
                tabButton(title: "Posts", icon: "text.bubble", tab: .posts)
            }
            
            tabButton(title: "Details", icon: "gearshape", tab: .details)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            // Use a Material blur for a modern floating effect
            .ultraThinMaterial
        )
        .clipShape(Capsule()) // Rounded capsule shape for the floating bar
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5) // Soft shadow
    }
    
    private func tabButton(title: String, icon: String, tab: EnhancedLiveSessionView.LiveSessionTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
            }
            .frame(width: 80)
        }
        .contentShape(Rectangle())
    }
}