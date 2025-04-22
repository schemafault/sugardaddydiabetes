import Foundation

struct PatientProfile: Identifiable, Codable {
    let id: String
    var name: String?
    var dateOfBirth: Date?
    var weight: Double?
    var weightUnit: String?
    var insulinType: String?
    var insulinDose: String?
    var otherMedications: String?
    
    init(id: String = UUID().uuidString,
         name: String? = nil,
         dateOfBirth: Date? = nil,
         weight: Double? = nil,
         weightUnit: String? = nil,
         insulinType: String? = nil,
         insulinDose: String? = nil,
         otherMedications: String? = nil) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.weight = weight
        self.weightUnit = weightUnit
        self.insulinType = insulinType
        self.insulinDose = insulinDose
        self.otherMedications = otherMedications
    }
    
    // Helper for formatted age
    var formattedAge: String? {
        guard let dob = dateOfBirth else { return nil }
        
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
        if let years = ageComponents.year, years > 0 {
            return "\(years) years"
        }
        return nil
    }
    
    // Helper for formatted weight
    var formattedWeight: String? {
        guard let weight = weight else { return nil }
        
        let unit = weightUnit ?? "kg"
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        
        if let formatted = formatter.string(from: NSNumber(value: weight)) {
            return "\(formatted) \(unit)"
        }
        return nil
    }
} 