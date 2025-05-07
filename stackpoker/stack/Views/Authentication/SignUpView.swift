import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingEmailVerification = false
    @StateObject private var authService = AuthService()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Create Account")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Sign up to get started")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                        
                        // Registration Form
                        VStack(spacing: 16) {
                            TextField("Email", text: $email)
                                .textFieldStyle(CustomTextFieldStyle())
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                            
                            SecureField("Password", text: $password)
                                .textFieldStyle(CustomTextFieldStyle())
                            
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(CustomTextFieldStyle())
                            
                            Button(action: signUp) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text("Create Account")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .disabled(isLoading)
                        }
                        .padding(.top, 32)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarItems(leading: Button(action: { 
                if !showingEmailVerification {
                    dismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
            })
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showingEmailVerification) {
            EmailVerificationView()
        }
    }
    
    private func signUp() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            showingError = true
            return
        }
        
        isLoading = true
        Task {
            do {
                try await authService.signUpWithEmail(email: email, password: password)
                DispatchQueue.main.async {
                    showingEmailVerification = true
                    isLoading = false
                }
            } catch let error as AuthError {
                DispatchQueue.main.async {
                    errorMessage = error.message
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
} 