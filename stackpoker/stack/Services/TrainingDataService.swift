import Foundation
import FirebaseFirestore

class TrainingDataService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var trainingDataEntries: [HandTrainingData] = []
    
    func saveTrainingData(_ data: HandTrainingData) async throws {
        // Convert to JSON first
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(data)
        var dict = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] ?? [:]
        
        // Convert parsedJSON to dictionary for Firestore
        if let jsonData = dict["parsedJSON"] as? Data,
           let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            dict["parsedJSON"] = jsonDict
        }
        
        // Use server timestamp
        dict["timestamp"] = FieldValue.serverTimestamp()
        
        // Save to Firestore
        try await db.collection("training_data").addDocument(data: dict)
    }
    
    func fetchTrainingData() async {
        do {
            let snapshot = try await db.collection("training_data")
                .order(by: "timestamp", descending: true)
                .getDocuments()
                
            // Process documents
            let entries = try snapshot.documents.compactMap { document -> HandTrainingData? in
                var data = document.data()
                data["id"] = document.documentID
                
                // Convert Timestamp to Date
                if let timestamp = data["timestamp"] as? Timestamp {
                    data["timestamp"] = timestamp.dateValue()
                } else {
                    data["timestamp"] = Date()
                }
                
                // Handle the parsedJSON dictionary
                if let parsedJSON = data["parsedJSON"] as? [String: Any] {
                    let jsonData = try JSONSerialization.data(withJSONObject: parsedJSON)
                    data["parsedJSON"] = jsonData
                }
                
                // Convert to JSON data
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                
                // Decode to model
                return try JSONDecoder().decode(HandTrainingData.self, from: jsonData)
            }
            
            DispatchQueue.main.async {
                self.trainingDataEntries = entries
            }
        } catch {
            print("Error fetching training data: \(error)")
        }
    }
    
    func deleteTrainingData(id: String) async throws {
        try await db.collection("training_data").document(id).delete()
        
        DispatchQueue.main.async {
            self.trainingDataEntries.removeAll { $0.id == id }
        }
    }
    
    func exportTrainingDataAsJSONL() async throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("training_data.jsonl")
        
        // Create empty file
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        
        // Open for writing
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        
        // Write each entry as a separate JSON line
        for entry in trainingDataEntries {
            let exportObj: [String: Any] = [
                "original_text": entry.originalText,
                "parsed_json": entry.parsedJSON,
                "is_verified": entry.isVerified,
                "user_edited": entry.userEdited,
                "timestamp": entry.timestamp.timeIntervalSince1970,
                "user_id": entry.userId,
                "parsing_accuracy": entry.parsingAccuracy as Any,
                "notes": entry.notes as Any
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: exportObj)
            
            if let jsonLine = String(data: jsonData, encoding: .utf8) {
                try fileHandle.write(contentsOf: (jsonLine + "\n").data(using: .utf8)!)
            }
        }
        
        try fileHandle.close()
        return fileURL
    }
} 