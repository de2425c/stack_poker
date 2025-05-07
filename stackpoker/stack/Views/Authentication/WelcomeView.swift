import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingSignIn = false
    @State private var showingSignUp = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background color matching the dark theme from mockup
                Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Logo/Image section
                    Image("chip")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 180, height: 180)
                        .padding(.top, 60)
                    
                    // Welcome text
                    VStack(spacing: 8) {
                        Text("Welcome\nto Stack!")
                            .font(.system(size: 34, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                        
                        Text("Join 20,000+ Poker Players already\nenjoying the stack app.")
                            .font(.system(size: 15))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(.systemGray))
                    }
                    
                    Spacer()
                    
                    // Buttons
                    VStack(spacing: 16) {
                        // Sign Up Button
                        Button(action: { showingSignUp = true }) {
                            Text("Get Started")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .cornerRadius(12)
                        }
                        
                        // Sign In Button
                        Button(action: { showingSignIn = true }) {
                            Text("Sign In")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
        }
    }
}

// Preview provider
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
    }
} 