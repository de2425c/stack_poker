import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color("Background")
                    .ignoresSafeArea()
                
                Image("StackLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
            }
            .navigationBarHidden(true)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
            .fullScreenCover(isPresented: $isActive) {
                WelcomeView()
            }
        }
    }
} 