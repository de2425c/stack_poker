// MARK: - Save Home Game Session View

import SwiftUI
import FirebaseAuth
import PhotosUI // Keep if used elsewhere in the file
import Combine // Keep if used elsewhere in the file
import Foundation // Keep if used elsewhere in the file
import FirebaseFirestore

struct SaveHomeGameSessionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var sessionStore: SessionStore

    let pnl: Double
    let buyIn: Double
    let cashOut: Double
    let duration: TimeInterval
    let date: Date

    @State private var sessionName: String = ""
    @State private var sessionStakes: String = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var showErrorAlert = false
    
    var body: some View {
        ZStack {
            // Background
            AppBackgroundView()
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Custom navigation bar
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer()
                    
                    Text("Save Home Game")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: saveSession) {
                        Text("Save")
                            .foregroundColor(.black)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                Capsule()
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                    }
                    .disabled(sessionName.isEmpty || sessionStakes.isEmpty || isSaving)
                    .opacity((sessionName.isEmpty || sessionStakes.isEmpty || isSaving) ? 0.6 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Scroll content
                ScrollView {
                    // Add top spacing for navigation bar clearance
                    Color.clear.frame(height: 60)
                    
                    VStack(spacing: 24) {
                        // Session Details Card
                        VStack(spacing: 20) {
                            // Section header
                            HStack {
                                Text("SESSION DETAILS")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                Spacer()
                            }
                            .padding(.bottom, 4)
                            
                            // Details with dividers
                            detailRow(label: "Profit/Loss", value: formatMoney(pnl), 
                                      valueColor: pnl >= 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red)
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Buy-in", value: formatMoney(buyIn))
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Cash Out", value: formatMoney(cashOut))
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Duration", value: formatDuration(duration))
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            detailRow(label: "Date", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear,
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal, 16)
                        
                        // Session Info Input Card
                        VStack(spacing: 20) {
                            // Section header
                            HStack {
                                Text("SESSION INFO")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                Spacer()
                            }
                            .padding(.bottom, 4)
                            
                            // Name input using GlassyInputField
                            GlassyInputField(
                                icon: "gamecontroller.fill",
                                title: "SESSION NAME",
                                labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
                            ) {
                                TextField("", text: $sessionName)
                                    .placeholder(when: sessionName.isEmpty) {
                                        Text("e.g., Friday Night Game").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .padding(.vertical, 10)
                                    .foregroundColor(.white)
                            }
                            
                            // Stakes input using GlassyInputField
                            GlassyInputField(
                                icon: "dollarsign.circle.fill",
                                title: "STAKES",
                                labelColor: Color(red: 123/255, green: 255/255, blue: 99/255)
                            ) {
                                TextField("", text: $sessionStakes)
                                    .placeholder(when: sessionStakes.isEmpty) {
                                        Text("e.g., 1/2 NLH").foregroundColor(.gray.opacity(0.7))
                                    }
                                    .font(.system(size: 17))
                                    .padding(.vertical, 10)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 1.0)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear,
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal, 16)
                        
                        // Save button for larger screens
                        Button(action: saveSession) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text("Save Session")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill((sessionName.isEmpty || sessionStakes.isEmpty || isSaving) ? 
                                          Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5) : 
                                          Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                        }
                        .disabled(sessionName.isEmpty || sessionStakes.isEmpty || isSaving)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 16)
                }
            }
            
            // Loading overlay
            if isSaving {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                        .scaleEffect(1.5)
                    
                    Text("Saving Session...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.95)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            }
        }
        .alert("Error Saving Session", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(error ?? "An unknown error occurred.")
        }
        .statusBar(hidden: false)
        // Add tap to dismiss keyboard
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        // Fix keyboard movement issues
        .ignoresSafeArea(.keyboard)
    }
    
    // Helper function to create consistent detail rows
    private func detailRow(label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(valueColor)
        }
    }
    
    // Helper function to format money (copied for self-containment)
    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    // Helper function to format duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "0m" }
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func saveSession() {
        isSaving = true
        error = nil
        
        // Get current user ID directly from Auth
        guard let userId = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.error = "Failed to get user ID"
                self.showErrorAlert = true
                self.isSaving = false
            }
            return
        }
        
        // Create the dictionary for SessionStore with accurate buyIn and cashOut values
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "Home Game",
            "gameName": sessionName,
            "stakes": sessionStakes,
            "startDate": Timestamp(date: date.addingTimeInterval(-duration)),
            "startTime": Timestamp(date: date.addingTimeInterval(-duration)),
            "endTime": Timestamp(date: date),
            "hoursPlayed": duration / 3600,
            "buyIn": buyIn,
            "cashout": cashOut,
            "profit": pnl,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Call the SessionStore method with completion handler
        sessionStore.addSession(sessionData) { saveError in
            DispatchQueue.main.async {
                self.isSaving = false
                if let saveError = saveError {
                    self.error = "Failed to save session: \(saveError.localizedDescription)"
                    self.showErrorAlert = true
                } else {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}

