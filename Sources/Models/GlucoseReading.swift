import Foundation
import SwiftUI

struct GlucoseReading: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let value: Double
    let unit: String
    let isHigh: Bool
    let isLow: Bool
    
    init(id: String, timestamp: Date, value: Double, unit: String, isHigh: Bool, isLow: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.isHigh = isHigh
        self.isLow = isLow
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp = "Timestamp"
        case value = "Value"
        case unit = "Unit"
        case isHigh = "IsHigh"
        case isLow = "IsLow"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        
        // Parse timestamp - handle multiple formats
        let decodedTimestamp: Date
        do {
            // First try direct Date decoding
            decodedTimestamp = try container.decode(Date.self, forKey: .timestamp)
            print("Successfully decoded timestamp directly: \(decodedTimestamp)")
        } catch {
            // If that fails, try string-based timestamp
            do {
                let timestampString = try container.decode(String.self, forKey: .timestamp)
                print("Decoding timestamp from string: \(timestampString)")
                
                // Try parsing with ISO8601
                let iso8601Formatter = ISO8601DateFormatter()
                iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTime]
                
                if let date = iso8601Formatter.date(from: timestampString) {
                    decodedTimestamp = date
                    print("Parsed with ISO8601: \(date)")
                } else {
                    // Try alternative date formats
                    let formatters: [DateFormatter] = [
                        {
                            // Add the format seen in the API: "3/25/2025 10:47:08 PM"
                            let formatter = DateFormatter()
                            formatter.dateFormat = "M/d/yyyy h:mm:ss a"
                            return formatter
                        }(),
                        {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            return formatter
                        }(),
                        {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                            return formatter
                        }(),
                        {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                            return formatter
                        }(),
                        {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
                            return formatter
                        }()
                    ]
                    
                    var parsedDate: Date? = nil
                    var usedFormatter: DateFormatter? = nil
                    
                    for formatter in formatters {
                        if let date = formatter.date(from: timestampString) {
                            parsedDate = date
                            usedFormatter = formatter
                            break
                        }
                    }
                    
                    // If all formatters fail, try numeric timestamp
                    if parsedDate == nil, let numericTimestamp = Double(timestampString) {
                        parsedDate = Date(timeIntervalSince1970: numericTimestamp / 1000.0)
                        print("Parsed numeric timestamp \(timestampString) to \(parsedDate!)")
                    }
                    
                    if let validDate = parsedDate {
                        decodedTimestamp = validDate
                        print("Parsed timestamp \(timestampString) to \(validDate)" + (usedFormatter != nil ? " using \(usedFormatter!.dateFormat!)" : ""))
                    } else {
                        print("Failed to parse timestamp: \(timestampString), using current date")
                        decodedTimestamp = Date()
                    }
                }
            } catch {
                print("Failed to decode timestamp: \(error)")
                decodedTimestamp = Date()
            }
        }
        
        // Set all properties once
        timestamp = decodedTimestamp
        value = try container.decode(Double.self, forKey: .value)
        unit = try container.decode(String.self, forKey: .unit)
        isHigh = try container.decode(Bool.self, forKey: .isHigh)
        isLow = try container.decode(Bool.self, forKey: .isLow)
    }
    
    var valueInMgPerDl: Double {
        if unit == "mmol/L" {
            return value * 18.0182
        }
        return value
    }
    
    var valueInMmolPerL: Double {
        if unit == "mg/dL" {
            return value / 18.0182
        }
        return value
    }
    
    var displayValue: Double {
        UserDefaults.standard.string(forKey: "unit") == "mmol" ? valueInMmolPerL : valueInMgPerDl
    }
    
    var displayUnit: String {
        UserDefaults.standard.string(forKey: "unit") == "mmol" ? "mmol/L" : "mg/dL"
    }
    
    var isInRange: Bool {
        let value = displayValue
        let lowThreshold = Double(UserDefaults.standard.string(forKey: "lowThreshold") ?? "70") ?? 70
        let highThreshold = Double(UserDefaults.standard.string(forKey: "highThreshold") ?? "180") ?? 180
        return value >= lowThreshold && value <= highThreshold
    }
    
    enum RangeStatus {
        case low
        case inRange
        case high
        
        var color: Color {
            switch self {
            case .low: return .yellow
            case .inRange: return .green
            case .high: return .red
            }
        }
    }
    
    var rangeStatus: RangeStatus {
        let value = displayValue
        let lowThreshold = Double(UserDefaults.standard.string(forKey: "lowThreshold") ?? "70") ?? 70
        let highThreshold = Double(UserDefaults.standard.string(forKey: "highThreshold") ?? "180") ?? 180
        
        if value < lowThreshold {
            return .low
        } else if value > highThreshold {
            return .high
        } else {
            return .inRange
        }
    }
    
    enum GlucoseTrend {
        case notComputable
        case falling
        case stable
        case rising
        
        var description: String {
            switch self {
            case .notComputable: return "Not Computable"
            case .falling: return "Falling"
            case .stable: return "Stable"
            case .rising: return "Rising"
            }
        }
        
        var icon: String {
            switch self {
            case .notComputable: return "questionmark.circle"
            case .falling: return "arrow.down.circle"
            case .stable: return "equal.circle"
            case .rising: return "arrow.up.circle"
            }
        }
    }
    
    var trend: GlucoseTrend {
        // For now, we'll use a simple algorithm based on high/low flags
        if isHigh {
            return .rising
        } else if isLow {
            return .falling
        } else {
            return .stable
        }
    }
} 