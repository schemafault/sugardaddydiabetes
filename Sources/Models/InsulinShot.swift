import Foundation

struct InsulinShot: Identifiable, Codable { // Assuming Codable for potential future use
    let id: UUID
    let timestamp: Date
    let dosage: Double? // Optional dosage in units
    let notes: String?  // Optional user notes

    // Initializer
    init(id: UUID = UUID(), timestamp: Date, dosage: Double? = nil, notes: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.dosage = dosage
        // Ensure empty strings are stored as nil for optional notes
        self.notes = notes?.isEmpty ?? true ? nil : notes
    }
}

// Example extension for display formatting, if needed later
extension InsulinShot {
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    var formattedDosage: String {
        if let dosage = dosage {
            // Use NumberFormatter for locale-aware decimal formatting if needed
            // Using simple string interpolation for now
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 1 // Or adjust as needed
            let formattedNumber = numberFormatter.string(from: NSNumber(value: dosage)) ?? "\(dosage)"
            return "\(formattedNumber) units"
        } else {
            return "No dosage logged"
        }
    }
} 