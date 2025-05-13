import SwiftUI

struct ExploreView: View {
    @State private var searchText = ""
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // App header with search bar
                VStack(spacing: 16) {
                    // App title
                    Text("Explore")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .padding(.leading, 12)
                        
                        TextField("Search players, games, content...", text: $searchText)
                            .foregroundColor(.white)
                            .font(.system(size: 16, design: .default))
                            .padding(10)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 40/255, green: 42/255, blue: 45/255, alpha: 1.0)))
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.top, 55)
                .padding(.bottom, 16)
                
                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        // Coming soon message
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .padding()
                            
                            Text("Explore Feature")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Coming Soon")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.gray)
                                .padding(.bottom, 8)
                            
                            Text("Discover players, games, and content")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Extra padding for tab bar
                }
            }
        }
    }
}

#Preview {
    ExploreView()
} 