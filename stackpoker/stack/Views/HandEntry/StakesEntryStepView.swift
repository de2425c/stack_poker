import SwiftUI

struct StakesEntryStepView: View {
    @EnvironmentObject var viewModel: HandEntryViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Add extra spacing at the top
                
                // Table size section with animated selection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .font(.system(size: 20))
                        
                        Text("Table Size")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 12) {
                        ForEach([2, 6, 9], id: \.self) { size in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.tableSize = size
                                }
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16))
                                    
                                    Text("\(size)-max")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(viewModel.tableSize == size ? 
                                              Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.2) : 
                                              Color.black.opacity(0.25))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.tableSize == size ? 
                                                        Color(red: 123/255, green: 255/255, blue: 99/255) : 
                                                        Color.gray.opacity(0.3), 
                                                        lineWidth: 1)
                                        )
                                )
                                .foregroundColor(viewModel.tableSize == size ? 
                                                 Color(red: 123/255, green: 255/255, blue: 99/255) : 
                                                 .white.opacity(0.8))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 3, y: 2)
                
                // Blinds section with improved input fields
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .font(.system(size: 20))
                        
                        Text("Blinds")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 16) {
                        blindField(title: "Small Blind", value: $viewModel.smallBlind, icon: "s.circle.fill")
                        blindField(title: "Big Blind", value: $viewModel.bigBlind, icon: "b.circle.fill")
                    }
                    
                    // Common blind presets
                    Text("Common Presets")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                    
                    HStack(spacing: 8) {
                        ForEach([("$1/$2", 1.0, 2.0), 
                                 ("$2/$5", 2.0, 5.0), 
                                 ("$5/$10", 5.0, 10.0)], id: \.0) { preset in
                            Button(action: {
                                withAnimation {
                                    viewModel.smallBlind = preset.1
                                    viewModel.bigBlind = preset.2
                                }
                            }) {
                                Text(preset.0)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.black.opacity(0.3))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 3, y: 2)
                
                // Helper text
                Text("These settings determine the size of your poker game and the blind structure.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func blindField(title: String, value: Binding<Double>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
                
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.8))
                    .font(.system(size: 14))
                
                Text("$")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
                
                TextField("Amount", value: value, formatter: currencyFormatter)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }
}

struct StakesEntryStepView_Previews: PreviewProvider {
    static var previews: some View {
        StakesEntryStepView()
            .environmentObject(HandEntryViewModel())
            .background(AppBackgroundView())
            .preferredColorScheme(.dark)
    }
} 
