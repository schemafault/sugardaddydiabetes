import Foundation

/// Model representing a patient's medical profile
struct PatientProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var dateOfBirth: Date?
    var weight: Double?
    var weightUnit: String?
    var insulinType: String?
    var insulinDose: String?
    var otherMedications: String?
    
    init(id: String = UUID().uuidString, 
         name: String = "", 
         dateOfBirth: Date? = nil, 
         weight: Double? = nil, 
         weightUnit: String? = "kg", 
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
}

// MARK: - Helper Properties
extension PatientProfile {
    /// Age calculated from date of birth
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }
    
    /// Formatted weight with unit
    var formattedWeight: String? {
        guard let weight = weight, let unit = weightUnit else { return nil }
        return "\(weight) \(unit)"
    }
}

// MARK: - Export Formatting
extension PatientProfile {
    /// Dictionary representation for export purposes
    var exportDictionary: [String: Any] {
        var result: [String: Any] = [
            "name": name
        ]
        
        if let age = age {
            result["age"] = age
        }
        
        if let dob = dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            result["dateOfBirth"] = formatter.string(from: dob)
        }
        
        if let weight = weight {
            result["weight"] = weight
        }
        
        if let weightUnit = weightUnit {
            result["weightUnit"] = weightUnit
        }
        
        if let insulinType = insulinType {
            result["insulinType"] = insulinType
        }
        
        if let insulinDose = insulinDose {
            result["insulinDose"] = insulinDose
        }
        
        if let otherMedications = otherMedications {
            result["otherMedications"] = otherMedications
        }
        
        return result
    }
} 