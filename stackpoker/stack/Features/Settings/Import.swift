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
        case .pokerbase: return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
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
                
                VStack(spacing: 20) {
                    Text("Select Import Format")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    Text("Choose the app you want to import your poker session data from:")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 16) {
                        ForEach([ImportType.pokerbase, .pokerAnalytics, .pbt, .regroup, .pokerIncomeUltimate], id: \.self) { importType in
                            Button(action: {
                                onImportSelected(importType)
                                dismiss()
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "tray.and.arrow.down")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(importType.color)
                                        .frame(width: 30)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(importType.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("Import \(importType.fileType) files")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(importType.color.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("Import CSV")
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



// Add at the bottom of the file, outside any struct
extension Int {
    var formattedWithCommas: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}