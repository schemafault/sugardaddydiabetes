import Foundation

enum LibreViewError: LocalizedError {
    case authenticationFailed
    case invalidCredentials
    case networkError
    case rateLimited
    case serviceUnavailable
    case unknown
    case noCredentials
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Authentication failed"
        case .invalidCredentials: return "Invalid username or password"
        case .networkError: return "Network error occurred"
        case .rateLimited: return "Too many login attempts. Please try again in a few minutes"
        case .serviceUnavailable: return "LibreView service is temporarily unavailable"
        case .unknown: return "An unknown error occurred"
        case .noCredentials: return "No credentials found. Please enter your LibreView credentials"
        }
    }
}

actor LibreViewService {
    private let baseURL = "https://api.libreview.io"
    private let headers = [
        "Content-Type": "application/json",
        "Product": "llu.android",
        "Version": "4.7.0",
        "Accept-Encoding": "gzip"
    ]
    
    private var authToken: String?
    private var tokenExpiry: Date?
    private let tokenLifetime: TimeInterval = 50 * 60 // 50 minutes
    
    // A function to safely get credentials from UserDefaults
    private func getCredentials() throws -> (username: String, password: String) {
        guard let username = UserDefaults.standard.string(forKey: "username"),
              !username.isEmpty,
              let password = UserDefaults.standard.string(forKey: "password"),
              !password.isEmpty else {
            throw LibreViewError.noCredentials
        }
        return (username, password)
    }
    
    func checkAuthentication() async throws -> Bool {
        do {
            let credentials = try getCredentials()
            _ = try await authenticate(username: credentials.username, password: credentials.password)
            return true
        } catch let error as LibreViewError {
            throw error
        } catch {
            throw LibreViewError.unknown
        }
    }
    
    private func authenticate(username: String, password: String) async throws -> String {
        // Don't proceed with empty credentials
        guard !username.isEmpty && !password.isEmpty else {
            throw LibreViewError.invalidCredentials
        }
        
        let url = URL(string: "\(baseURL)/llu/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let body = ["email": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LibreViewError.unknown
            }
            
            switch httpResponse.statusCode {
            case 200:
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                authToken = authResponse.data.authTicket.token
                tokenExpiry = Date().addingTimeInterval(tokenLifetime)
                return authResponse.data.authTicket.token
            case 401:
                throw LibreViewError.invalidCredentials
            case 429:
                throw LibreViewError.rateLimited
            case 503:
                throw LibreViewError.serviceUnavailable
            default:
                throw LibreViewError.unknown
            }
        } catch let decodingError as DecodingError {
            print("Decoding error: \(decodingError)")
            throw LibreViewError.authenticationFailed
        } catch let libreError as LibreViewError {
            throw libreError
        } catch {
            print("Network error: \(error.localizedDescription)")
            throw LibreViewError.networkError
        }
    }
    
    func fetchGlucoseData() async throws -> [GlucoseReading] {
        guard let token = try await getValidToken() else {
            throw LibreViewError.authenticationFailed
        }
        
        let url = URL(string: "\(baseURL)/llu/connections")!
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers.merging(["Authorization": "Bearer \(token)"]) { $1 }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LibreViewError.networkError
            }
            
            let connectionsResponse = try JSONDecoder().decode(ConnectionsResponse.self, from: data)
            guard let patientId = connectionsResponse.data.first?.patientId else {
                return []
            }
            
            return try await fetchGlucoseGraph(patientId: patientId, token: token)
        } catch {
            print("Error fetching connections: \(error)")
            throw LibreViewError.networkError
        }
    }
    
    private func fetchGlucoseGraph(patientId: String, token: String) async throws -> [GlucoseReading] {
        let url = URL(string: "\(baseURL)/llu/connections/\(patientId)/graph")!
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers.merging(["Authorization": "Bearer \(token)"]) { $1 }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LibreViewError.networkError
            }
            
            // Log the entire response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw glucose graph data received")
                
                // Use jsonString for debugging by logging a snippet
                print("Graph data sample: \(jsonString.prefix(100))")
                
                // Extract a sample of the graph data for diagnosis
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let graphData = dataObj["graphData"] as? [[String: Any]],
                   let firstReading = graphData.first {
                    print("Sample reading format: \(firstReading)")
                }
            }
            
            // Create and configure a flexible decoder
            let decoder = JSONDecoder()
            
            // Try with ISO8601 date decoding strategy first
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                
                // Try decoding as date string first
                do {
                    let dateStr = try container.decode(String.self)
                    
                    // Try multiple date formatters
                    let formatters: [DateFormatter] = [
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
                        }()
                    ]
                    
                    // Try ISO8601 first
                    let iso8601 = ISO8601DateFormatter()
                    iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    
                    if let date = iso8601.date(from: dateStr) {
                        return date
                    }
                    
                    // Try other formatters
                    for formatter in formatters {
                        if let date = formatter.date(from: dateStr) {
                            return date
                        }
                    }
                    
                    // If all formatters fail, try numeric timestamp
                    if let timestamp = Double(dateStr) {
                        return Date(timeIntervalSince1970: timestamp / 1000.0)
                    }
                    
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Date string does not match any expected format."
                        )
                    )
                } catch {
                    // If string fails, try number (timestamp)
                    do {
                        let timestamp = try container.decode(Double.self)
                        return Date(timeIntervalSince1970: timestamp / 1000.0)
                    } catch {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(
                                codingPath: decoder.codingPath,
                                debugDescription: "Date value is neither string nor timestamp."
                            )
                        )
                    }
                }
            }
            
            do {
                let graphResponse = try decoder.decode(GraphResponse.self, from: data)
                return graphResponse.data.graphData
            } catch {
                print("Primary decoding method failed: \(error)")
                
                // Fallback approach: manual parsing with more detailed logging
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataDict = json["data"] as? [String: Any],
                   let graphDataArray = dataDict["graphData"] as? [[String: Any]] {
                    
                    print("Falling back to manual JSON parsing for \(graphDataArray.count) readings")
                    var readings: [GlucoseReading] = []
                    
                    for (index, reading) in graphDataArray.enumerated() {
                        if index < 5 {
                            print("Reading \(index): \(reading)")
                        }
                        
                        // Extract value - handle multiple possible fields
                        let glucoseValue: Double
                        if let value = reading["Value"] as? Double {
                            glucoseValue = value
                        } else if let valueInMgPerDl = reading["ValueInMgPerDl"] as? Double {
                            glucoseValue = valueInMgPerDl
                        } else {
                            print("Missing valid glucose value in reading \(index)")
                            continue
                        }
                        
                        // Determine unit based on GlucoseUnits field
                        let unit: String
                        if let glucoseUnits = reading["GlucoseUnits"] as? Int {
                            // 0 = mmol/L, 1 = mg/dL (based on the logs)
                            unit = glucoseUnits == 0 ? "mmol/L" : "mg/dL"
                        } else {
                            // Default to mmol/L since the values look like mmol/L values
                            unit = "mmol/L"
                        }
                        
                        // Build a complete reading dictionary
                        var readingDict: [String: Any] = [
                            "id": UUID().uuidString,
                            "Value": glucoseValue,
                            "Unit": unit,
                            "IsHigh": (reading["isHigh"] as? Bool) ?? ((reading["isHigh"] as? Int) == 1),
                            "IsLow": (reading["isLow"] as? Bool) ?? ((reading["isLow"] as? Int) == 1)
                        ]
                        
                        // Handle timestamp with comprehensive fallbacks
                        if let timestamp = reading["Timestamp"] {
                            readingDict["Timestamp"] = timestamp
                            
                            // Log timestamp format for debugging
                            if index == 0 {
                                print("Timestamp type: \(type(of: timestamp))")
                                print("Timestamp value: \(timestamp)")
                            }
                            
                            // If timestamp is a string in format "MM/dd/yyyy hh:mm:ss a"
                            if let timestampStr = timestamp as? String {
                                let dateFormatter = DateFormatter()
                                // Try American format first (as seen in the logs)
                                dateFormatter.dateFormat = "M/d/yyyy h:mm:ss a"
                                
                                if let date = dateFormatter.date(from: timestampStr) {
                                    // Format in ISO8601 for our decoder
                                    let iso8601Formatter = ISO8601DateFormatter()
                                    readingDict["Timestamp"] = iso8601Formatter.string(from: date)
                                    if index == 0 {
                                        print("Converted timestamp: \(readingDict["Timestamp"] ?? "unknown")")
                                        print("Parsed date: \(date)")
                                    }
                                } else {
                                    // Try alternative formats
                                    let alternateFormatters = [
                                        "M/d/yyyy h:mm:ss a",
                                        "yyyy-MM-dd HH:mm:ss",
                                        "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                                    ]
                                    
                                    var parsedDate: Date? = nil
                                    for formatString in alternateFormatters {
                                        dateFormatter.dateFormat = formatString
                                        if let date = dateFormatter.date(from: timestampStr) {
                                            parsedDate = date
                                            break
                                        }
                                    }
                                    
                                    if let date = parsedDate {
                                        let iso8601Formatter = ISO8601DateFormatter()
                                        readingDict["Timestamp"] = iso8601Formatter.string(from: date)
                                        if index == 0 {
                                            print("Converted with alternate format: \(readingDict["Timestamp"] ?? "unknown")")
                                        }
                                    } else {
                                        print("Failed to parse timestamp: \(timestampStr)")
                                    }
                                }
                            }
                        } else {
                            // Use current date if no timestamp
                            print("Missing Timestamp in reading \(index)")
                            let now = Date()
                            let formatter = ISO8601DateFormatter()
                            readingDict["Timestamp"] = formatter.string(from: now)
                        }
                        
                        do {
                            let readingData = try JSONSerialization.data(withJSONObject: readingDict)
                            let glucoseReading = try JSONDecoder().decode(GlucoseReading.self, from: readingData)
                            readings.append(glucoseReading)
                            if index == 0 {
                                print("Successfully decoded first reading: \(glucoseReading)")
                            }
                        } catch {
                            print("Error decoding reading \(index): \(error)")
                        }
                    }
                    
                    if !readings.isEmpty {
                        print("Successfully parsed \(readings.count) readings manually")
                        
                        // Sort readings by timestamp to ensure most recent first
                        let sortedReadings = readings.sorted { reading1, reading2 in
                            return reading1.timestamp > reading2.timestamp
                        }
                        
                        if let firstReading = sortedReadings.first {
                            print("Most recent reading: \(firstReading.value) \(firstReading.unit) at \(firstReading.timestamp)")
                        }
                        
                        return sortedReadings
                    } else {
                        print("No readings could be parsed")
                    }
                } else {
                    print("Couldn't extract graph data array from response")
                }
                
                throw LibreViewError.networkError
            }
        } catch {
            print("Error fetching graph data: \(error)")
            throw LibreViewError.networkError
        }
    }
    
    private func getValidToken() async throws -> String? {
        if let token = authToken,
           let expiry = tokenExpiry,
           Date() < expiry {
            return token
        }
        
        let credentials = try getCredentials()
        return try await authenticate(username: credentials.username, password: credentials.password)
    }
}

// API Response Models
private struct AuthResponse: Codable {
    let data: AuthData
    
    struct AuthData: Codable {
        let authTicket: AuthTicket
        
        struct AuthTicket: Codable {
            let token: String
            let expires: Int
            let duration: Int
        }
    }
}

private struct ConnectionsResponse: Codable {
    let data: [Connection]
    
    struct Connection: Codable {
        let patientId: String
    }
}

private struct GraphResponse: Codable {
    let data: GraphData
    
    struct GraphData: Codable {
        let graphData: [GlucoseReading]
    }
} 