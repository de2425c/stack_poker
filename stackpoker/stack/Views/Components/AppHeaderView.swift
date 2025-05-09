import SwiftUI

struct AppHeaderView: View {
    let title: String
    let showNotificationBadge: Bool
    let actionButtonIcon: String
    let notificationAction: () -> Void
    let actionButtonAction: () -> Void
    let paddingTop: CGFloat
    
    init(
        title: String,
        showNotificationBadge: Bool = false,
        actionButtonIcon: String = "plus",
        paddingTop: CGFloat = 16,
        notificationAction: @escaping () -> Void = {},
        actionButtonAction: @escaping () -> Void = {}
    ) {
        self.title = title
        self.showNotificationBadge = showNotificationBadge
        self.actionButtonIcon = actionButtonIcon
        self.paddingTop = paddingTop
        self.notificationAction = notificationAction
        self.actionButtonAction = actionButtonAction
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Clean, modern header
            HStack {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Notification bell with badge
                if showNotificationBadge {
                    Button(action: notificationAction) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .padding(8)
                            
                            // Badge
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .padding(.trailing, 12)
                }
                
                // Action button (typically "plus" for adding content)
                Button(action: actionButtonAction) {
                    Image(systemName: actionButtonIcon)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .padding(8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, paddingTop)
            .padding(.bottom, 16)
            
            // Optional search bar can be added below by the parent view
        }
    }
}

// Optional companion view for search bar that matches the header
struct AppSearchBarView: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
                
                TextField("Search", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
            }
            .padding(.trailing, 8)
            .background(Color(red: 32/255, green: 34/255, blue: 38/255))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)
        VStack {
            AppHeaderView(
                title: "Preview",
                showNotificationBadge: true,
                actionButtonAction: {}
            )
            
            AppSearchBarView(searchText: .constant(""))
            
            Spacer()
        }
    }
} 