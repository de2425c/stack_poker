import SwiftUI
import UniformTypeIdentifiers

struct CSVImportFlow: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionStore: SessionStore
    
    @State private var currentImportType: ImportType = .pokerbase
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var importStatusMessage: String?
    @State private var showingImportResult = false
    @State private var importSuccessCount = 0
    
    let userId: String
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                if isImporting {
                    // Loading overlay
                    importingOverlay
                } else {
                    // Main content
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            headerSection
                            
                            // Import options
                            importOptionsSection
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Import Poker Data")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .text, .data]
        ) { result in
            handleFileImport(result)
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text(importStatusMessage ?? "")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.15)))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            }
            
            VStack(spacing: 8) {
                Text("Import Your Sessions")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Select the app you previously used to track your poker sessions. We'll import your data securely.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }
    
    // MARK: - Import Options Section
    private var importOptionsSection: some View {
        VStack(spacing: 16) {
            Text("Choose Your Previous App")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                ForEach([ImportType.pokerbase, .pokerAnalytics, .pbt, .regroup], id: \.self) { importType in
                    ImportOptionCard(
                        importType: importType,
                        isSelected: currentImportType == importType,
                        onTap: {
                            currentImportType = importType
                            showFileImporter = true
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Importing Overlay
    private var importingOverlay: some View {
        VStack(spacing: 24) {
            // Animated loading indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isImporting)
            }
            
            VStack(spacing: 8) {
                Text("Importing Sessions...")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Please wait while we process your data")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - File Import Handler
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImporting = true
            
            switch currentImportType {
            case .pokerbase:
                sessionStore.importSessionsFromPokerbaseCSV(fileURL: url) { importResult in
                    DispatchQueue.main.async {
                        handleImportResult(importResult)
                    }
                }
            case .pokerAnalytics:
                sessionStore.importSessionsFromPokerAnalyticsCSV(fileURL: url) { importResult in
                    DispatchQueue.main.async {
                        handleImportResult(importResult)
                    }
                }
            case .pbt:
                sessionStore.importSessionsFromPBTCSV(fileURL: url) { importResult in
                    DispatchQueue.main.async {
                        handleImportResult(importResult)
                    }
                }
            case .regroup:
                sessionStore.importSessionsFromRegroupCSV(fileURL: url) { importResult in
                    DispatchQueue.main.async {
                        handleImportResult(importResult)
                    }
                }
            }
            
        case .failure(let error):
            isImporting = false
            importStatusMessage = "Failed to select file: \(error.localizedDescription)"
            showingImportResult = true
        }
    }
    
    private func handleImportResult(_ result: Result<Int, Error>) {
        isImporting = false
        switch result {
        case .success(let count):
            importSuccessCount = count
            importStatusMessage = "Successfully imported \(count) session\(count == 1 ? "" : "s")! 🎉\n\nYour poker history is now available in Stack."
            showingImportResult = true
        case .failure(let error):
            importStatusMessage = "Import failed: \(error.localizedDescription)"
            showingImportResult = true
        }
    }
}

// MARK: - Import Option Card
private struct ImportOptionCard: View {
    let importType: ImportType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // App icon
                ZStack {
                    Circle()
                        .fill(importType.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(importType.color)
                }
                
                // App info
                VStack(alignment: .leading, spacing: 4) {
                    Text(importType.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Import \(importType.fileType) files")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Arrow
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
                            .stroke(
                                isSelected ? importType.color.opacity(0.5) : importType.color.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    CSVImportFlow(userId: "preview-user")
} 