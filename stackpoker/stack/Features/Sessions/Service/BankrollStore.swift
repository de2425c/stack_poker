import Foundation
import FirebaseFirestore

@MainActor
class BankrollStore: ObservableObject {
    @Published var bankrollSummary: BankrollSummary = BankrollSummary()
    @Published var transactions: [BankrollTransaction] = []
    @Published var isLoading: Bool = false
    
    let userId: String
    private let db = Firestore.firestore()
    
    init(userId: String) {
        guard !userId.isEmpty else {
            print("BankrollStore: userId is empty, skipping initialization")
            self.userId = userId
            return
        }
        self.userId = userId
        fetchBankrollData()
    }
    
    // MARK: - Data Fetching
    
    func fetchBankrollData() {
        guard !userId.isEmpty else {
            print("BankrollStore: Cannot fetch bankroll data - userId is empty")
            return
        }
        
        isLoading = true
        
        // Fetch bankroll summary
        fetchBankrollSummary()
        
        // Set up real-time listener for transactions
        setupTransactionsListener()
    }
    
    private func fetchBankrollSummary() {
        db.collection("users")
            .document(userId)
            .collection("bankroll")
            .document("summary")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error fetching bankroll summary: \(error)")
                        self.isLoading = false
                        return
                    }
                    
                    if let data = snapshot?.data() {
                        self.bankrollSummary = BankrollSummary.from(dictionary: data) ?? BankrollSummary()
                    } else {
                        // Create initial summary document if it doesn't exist
                        self.createInitialBankrollSummary()
                    }
                    
                    self.isLoading = false
                }
            }
    }
    
    private func setupTransactionsListener() {
        db.collection("users")
            .document(userId)
            .collection("bankroll")
            .document("summary")
            .collection("transactions")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error fetching bankroll transactions: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.transactions = []
                        return
                    }
                    
                    self.transactions = documents.compactMap { document in
                        BankrollTransaction.from(dictionary: document.data())
                    }
                }
            }
    }
    
    private func createInitialBankrollSummary() {
        let initialSummary = BankrollSummary()
        
        do {
            try db.collection("users")
                .document(userId)
                .collection("bankroll")
                .document("summary")
                .setData(initialSummary.dictionary)
        } catch {
            print("Error creating initial bankroll summary: \(error)")
        }
    }
    
    // MARK: - Bankroll Adjustment
    
    func adjustBankroll(amount: Double, note: String?) async throws {
        guard !userId.isEmpty else {
            throw BankrollError.invalidUserId
        }
        
        guard amount != 0 else {
            throw BankrollError.invalidAmount
        }
        
        let transaction = BankrollTransaction(amount: amount, note: note)
        let newTotal = bankrollSummary.currentTotal + amount
        
        guard newTotal >= 0 else {
            throw BankrollError.insufficientFunds
        }
        
        let batch = db.batch()
        
        // Add transaction
        let transactionRef = db.collection("users")
            .document(userId)
            .collection("bankroll")
            .document("summary")
            .collection("transactions")
            .document(transaction.id)
        
        batch.setData(transaction.dictionary, forDocument: transactionRef)
        
        // Update summary
        let summaryRef = db.collection("users")
            .document(userId)
            .collection("bankroll")
            .document("summary")
        
        let updatedSummary = BankrollSummary(currentTotal: newTotal, lastUpdated: Date())
        batch.setData(updatedSummary.dictionary, forDocument: summaryRef)
        
        try await batch.commit()
    }
    
    // MARK: - Transaction Deletion
    
    func deleteTransaction(_ transactionId: String) async throws {
        guard !userId.isEmpty else {
            throw BankrollError.invalidUserId
        }
        
        let transactionRef = db.collection("users")
            .document(userId)
            .collection("bankroll")
            .document("summary")
            .collection("transactions")
            .document(transactionId)
        
        let summaryRef = db.collection("users")
            .document(userId)
            .collection("bankroll")
            .document("summary")
        
        try await db.runTransaction { (firestoreTransaction, errorPointer) -> Any? in
            let transactionDocument: DocumentSnapshot
            do {
                try transactionDocument = firestoreTransaction.getDocument(transactionRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard let transactionToDelete = BankrollTransaction.from(dictionary: transactionDocument.data() ?? [:]) else {
                let error = BankrollError.networkError // Or a more specific "not found" error
                errorPointer?.pointee = error as NSError
                return nil
            }
            
            // Re-fetch summary within transaction for consistency
            let summaryDocument: DocumentSnapshot
            do {
                try summaryDocument = firestoreTransaction.getDocument(summaryRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            let currentSummary = BankrollSummary.from(dictionary: summaryDocument.data() ?? [:]) ?? BankrollSummary()
            
            // Reverse the transaction amount to update the total
            let newTotal = currentSummary.currentTotal - transactionToDelete.amount
            
            // Perform deletion and update in the transaction
            firestoreTransaction.deleteDocument(transactionRef)
            firestoreTransaction.updateData(["currentTotal": newTotal], forDocument: summaryRef)
            
            return nil
        }
    }
    
    // MARK: - Convenience Methods
    
    func addToBankroll(amount: Double, note: String? = nil) async throws {
        try await adjustBankroll(amount: abs(amount), note: note)
    }
    
    func subtractFromBankroll(amount: Double, note: String? = nil) async throws {
        try await adjustBankroll(amount: -abs(amount), note: note)
    }
}

// MARK: - Error Handling

enum BankrollError: Error, LocalizedError {
    case invalidUserId
    case invalidAmount
    case insufficientFunds
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidUserId:
            return "Invalid user ID"
        case .invalidAmount:
            return "Amount must be greater than zero"
        case .insufficientFunds:
            return "Insufficient bankroll funds"
        case .networkError:
            return "Network error occurred"
        }
    }
} 