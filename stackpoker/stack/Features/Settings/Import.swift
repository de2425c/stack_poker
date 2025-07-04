import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher


// MARK: - Import Type Definition (moved outside of SettingsView for accessibility)
enum ImportType: Hashable {
    case pokerbase, pokerAnalytics, pbt, regroup, pokerIncomeUltimate
    
    var title: String {
        switch self {
        case .pokerbase: return "Pokerbase"
        case .pokerAnalytics: return "Poker Analytics"
        case .pbt: return "Poker Bankroll Tracker"
        case .regroup: return "Regroup"
        case .pokerIncomeUltimate: return "Poker Income Ultimate"
        }
    }
    
    var fileType: String {
        switch self {
        case .pokerbase: return "CSV"
        case .pokerAnalytics: return "TSV/CSV"
        case .pbt: return "CSV"
        case .regroup: return "CSV"
        case .pokerIncomeUltimate: return "via Email"
        }
    }
    
    var color: Color {
        switch self {
        case .pokerbase: return Color(red: 64/255, green: 156/255, blue: 255/255)
        case .pokerAnalytics: return .cyan
        case .pbt: return .purple
        case .regroup: return .orange
        case .pokerIncomeUltimate: return .yellow
        }
    }
}



// MARK: - Import Options Sheet
struct ImportOptionsSheet: View {
    let onImportSelected: (ImportType) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern Header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.15))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                            }
                            
                            VStack(spacing: 8) {
                                Text("Select Import Format")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Choose your previous poker tracking app to import your session history")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(2)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                        
                        // Import Options
                        VStack(spacing: 12) {
                            ForEach([ImportType.pokerbase, .pokerAnalytics, .pbt, .regroup, .pokerIncomeUltimate], id: \.self) { importType in
                                ModernImportCard(importType: importType) {
                                    onImportSelected(importType)
                                    dismiss()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Modern Import Card
private struct ModernImportCard: View {
    let importType: ImportType
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(importType.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(importType.color)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(importType.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Import \(importType.fileType) files")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ModernCardButtonStyle())
    }
}

// MARK: - Modern Card Button Style
private struct ModernCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}



// Add at the bottom of the file, outside any struct
extension Int {
    var formattedWithCommas: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}