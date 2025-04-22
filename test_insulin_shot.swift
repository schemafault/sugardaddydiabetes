import Foundation

// A minimal version of our InsulinShot struct for testing
struct InsulinShot: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let dosage: Double?
    let notes: String?
    
    init(id: UUID = UUID(), timestamp: Date, dosage: Double? = nil, notes: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.dosage = dosage
        self.notes = notes?.isEmpty ?? true ? nil : notes
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
    
    var formattedDosage: String {
        if let dosage = dosage {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 1
            let formattedNumber = numberFormatter.string(from: NSNumber(value: dosage)) ?? "\(dosage)"
            return "\(formattedNumber) units"
        } else {
            return "No dosage logged"
        }
    }
}

// Test creating and formatting insulin shots
func testInsulinShot() {
    let now = Date()
    
    // Test with dosage
    let shot1 = InsulinShot(timestamp: now, dosage: 10.5)
    print("Shot 1 - ID: \(shot1.id)")
    print("Shot 1 - Time: \(shot1.formattedTime)")
    print("Shot 1 - Dosage: \(shot1.formattedDosage)")
    print("Shot 1 - Notes: \(shot1.notes ?? "No notes")")
    
    // Test without dosage
    let shot2 = InsulinShot(timestamp: now, notes: "Before dinner")
    print("\nShot 2 - ID: \(shot2.id)")
    print("Shot 2 - Time: \(shot2.formattedTime)")
    print("Shot 2 - Dosage: \(shot2.formattedDosage)")
    print("Shot 2 - Notes: \(shot2.notes ?? "No notes")")
    
    // Test encoding/decoding
    do {
        let encoder = JSONEncoder()
        let data = try encoder.encode(shot1)
        
        let decoder = JSONDecoder()
        let decodedShot = try decoder.decode(InsulinShot.self, from: data)
        
        print("\nDecoded Shot - ID: \(decodedShot.id)")
        print("Decoded Shot - Time: \(decodedShot.formattedTime)")
        print("Decoded Shot - Dosage: \(decodedShot.formattedDosage)")
        
        print("\nTest passed!")
    } catch {
        print("Error encoding/decoding: \(error)")
    }
}

// Run the test
testInsulinShot() 