import SwiftUI

struct RefreshControl: View {
    @Binding var isRefreshing: Bool
    let action: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.frame(in: .global).minY > 50 {
                Color.clear
                    .preference(key: RefreshKey.self, value: true)
            } else {
                Color.clear
                    .preference(key: RefreshKey.self, value: false)
            }
        }
        .onPreferenceChange(RefreshKey.self) { value in
            if value {
                isRefreshing = true
                action()
            }
        }
    }
}

private struct RefreshKey: PreferenceKey {
    static var defaultValue: Bool = false
    
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
} 