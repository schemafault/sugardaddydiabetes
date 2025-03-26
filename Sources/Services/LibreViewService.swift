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
            
            // Fetch readings from the API
            let readings = try await fetchGlucoseGraph(patientId: patientId, token: token)
            
            // Transform readings for better time range filtering if needed
            let transformedReadings = transformReadingsForBetterFiltering(readings)
            
            return transformedReadings
        } catch {
            print("Error fetching connections: \(error)")
            throw LibreViewError.networkError
        }
    }
    
    private func fetchGlucoseGraph(patientId: String, token: String) async throws -> [GlucoseReading] {
        // Request 7 days of data to get whatever history is available
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        
        // Format dates for API request
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateStr = dateFormatter.string(from: startDate)
        let endDateStr = dateFormatter.string(from: endDate)
        
        print("Requesting glucose data from \(startDateStr) to \(endDateStr) (7 days)")
        
        // Create URL with date range parameters (properly escaped)
        var urlComponents = URLComponents(string: "\(baseURL)/llu/connections/\(patientId)/graph")!
        urlComponents.queryItems = [
            URLQueryItem(name: "period", value: "custom"),
            URLQueryItem(name: "startDate", value: startDateStr),
            URLQueryItem(name: "endDate", value: endDateStr)
        ]
        
        guard let url = urlComponents.url else {
            throw LibreViewError.networkError
        }
        
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers.merging(["Authorization": "Bearer \(token)"]) { $1 }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LibreViewError.networkError
            }
            
            // Check if we got a successful response
            if httpResponse.statusCode != 200 {
                print("API returned error status code: \(httpResponse.statusCode)")
                
                // If the request failed, try with no date parameters as fallback
                if httpResponse.statusCode >= 400 {
                    print("Falling back to default request without date parameters")
                    return try await fetchBasicGraph(patientId: patientId, token: token)
                }
                
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
                        let rawUnit: String
                        
                        // Determine unit based on GlucoseUnits field first
                        if let glucoseUnits = reading["GlucoseUnits"] as? Int {
                            // 0 = mmol/L, 1 = mg/dL (based on the logs)
                            rawUnit = glucoseUnits == 0 ? "mmol/L" : "mg/dL"
                            if index < 5 {
                                print("Reading \(index) uses unit code: \(glucoseUnits) -> \(rawUnit)")
                            }
                        } else {
                            // Default to mmol/L since the values look like mmol/L values
                            rawUnit = "mmol/L"
                            if index < 5 {
                                print("Reading \(index) defaulting to mmol/L")
                            }
                        }
                        
                        // Now extract the value with unit awareness
                        if let value = reading["Value"] as? Double {
                            glucoseValue = value
                            if index < 5 {
                                print("Reading \(index) raw Value: \(value) \(rawUnit)")
                            }
                        } else if let valueInMgPerDl = reading["ValueInMgPerDl"] as? Double {
                            // If we have ValueInMgPerDl, it's always in mg/dL regardless of GlucoseUnits
                            if rawUnit == "mmol/L" {
                                // Convert mg/dL to mmol/L if needed
                                glucoseValue = valueInMgPerDl / 18.0182
                                if index < 5 {
                                    print("Reading \(index) converting from mg/dL: \(valueInMgPerDl) to mmol/L: \(glucoseValue)")
                                }
                            } else {
                                // Just use the mg/dL value directly
                                glucoseValue = valueInMgPerDl
                                if index < 5 {
                                    print("Reading \(index) raw ValueInMgPerDl: \(valueInMgPerDl) mg/dL")
                                }
                            }
                        } else {
                            print("Missing valid glucose value in reading \(index)")
                            continue
                        }
                        
                        // Build a complete reading dictionary
                        var readingDict: [String: Any] = [
                            "id": UUID().uuidString,
                            "Value": glucoseValue,
                            "Unit": rawUnit,
                            "IsHigh": (reading["isHigh"] as? Bool) ?? ((reading["isHigh"] as? Int) == 1),
                            "IsLow": (reading["isLow"] as? Bool) ?? ((reading["isLow"] as? Int) == 1)
                        ]
                        
                        // Handle timestamp with comprehensive fallbacks
                        if let timestamp = reading["Timestamp"] {
                            // Print raw timestamp for ALL readings to see patterns
                            print("Reading \(index) raw timestamp: \(timestamp) (type: \(type(of: timestamp)))")
                            
                            readingDict["Timestamp"] = timestamp
                            
                            // If timestamp is a string in format "MM/dd/yyyy hh:mm:ss a"
                            if let timestampStr = timestamp as? String {
                                print("Reading \(index) timestamp string: \(timestampStr)")
                                let dateFormatter = DateFormatter()
                                // Try American format first (as seen in the logs)
                                dateFormatter.dateFormat = "M/d/yyyy h:mm:ss a"
                                
                                if let date = dateFormatter.date(from: timestampStr) {
                                    print("Reading \(index) parsed date: \(date) using default format")
                                    // Store as ISO8601 string for JSON serialization (Date objects can't be serialized directly)
                                    let iso8601Formatter = ISO8601DateFormatter()
                                    readingDict["Timestamp"] = iso8601Formatter.string(from: date)
                                } else {
                                    // Try alternative formats
                                    let alternateFormatters = [
                                        "M/d/yyyy h:mm:ss a",
                                        "M/d/yyyy h:mm a",
                                        "yyyy-MM-dd HH:mm:ss",
                                        "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                                    ]
                                    
                                    var parsedDate: Date? = nil
                                    var successfulFormat: String? = nil
                                    
                                    for formatString in alternateFormatters {
                                        dateFormatter.dateFormat = formatString
                                        if let date = dateFormatter.date(from: timestampStr) {
                                            parsedDate = date
                                            successfulFormat = formatString
                                            break
                                        }
                                    }
                                    
                                    if let date = parsedDate, let format = successfulFormat {
                                        print("Reading \(index) parsed date: \(date) using format: \(format)")
                                        // Store as ISO8601 string for JSON serialization
                                        let iso8601Formatter = ISO8601DateFormatter()
                                        readingDict["Timestamp"] = iso8601Formatter.string(from: date)
                                    } else {
                                        print("⚠️ Failed to parse timestamp: \(timestampStr) for reading \(index)")
                                        // Use a fallback date with hours difference
                                        let fallbackDate = Calendar.current.date(byAdding: .hour, value: -index, to: Date()) ?? Date()
                                        let iso8601Formatter = ISO8601DateFormatter()
                                        readingDict["Timestamp"] = iso8601Formatter.string(from: fallbackDate)
                                    }
                                }
                            } else if let timestampNum = timestamp as? Double {
                                // Handle numeric timestamp (milliseconds since epoch)
                                let date = Date(timeIntervalSince1970: timestampNum / 1000.0)
                                print("Reading \(index) timestamp from numeric: \(date)")
                                // Store as ISO8601 string for JSON serialization
                                let iso8601Formatter = ISO8601DateFormatter()
                                readingDict["Timestamp"] = iso8601Formatter.string(from: date)
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
                            let decoder = JSONDecoder()
                            
                            // Configure the decoder to properly handle ISO-8601 dates
                            decoder.dateDecodingStrategy = .iso8601
                            
                            // Try to decode and catch specific date decoding errors
                            do {
                                let glucoseReading = try decoder.decode(GlucoseReading.self, from: readingData)
                                readings.append(glucoseReading)
                                
                                if index < 5 || index % 10 == 0 {
                                    print("Successfully decoded reading with timestamp: \(glucoseReading.timestamp)")
                                }
                                
                                if index == 0 {
                                    print("First reading: \(glucoseReading)")
                                }
                            } catch {
                                print("Error decoding reading \(index), trying fallback method: \(error)")
                                
                                // Fall back to manual timestamp parsing
                                let iso8601String = readingDict["Timestamp"] as? String ?? ""
                                print("Original ISO string: \(iso8601String)")
                                
                                // Try to create a date directly from the string
                                let iso8601Formatter = ISO8601DateFormatter()
                                iso8601Formatter.formatOptions = [.withInternetDateTime]
                                
                                if let timestamp = iso8601Formatter.date(from: iso8601String) {
                                    // Create reading with manually constructed date
                                    let id = readingDict["id"] as? String ?? UUID().uuidString
                                    let value = readingDict["Value"] as? Double ?? 0.0
                                    let unit = readingDict["Unit"] as? String ?? "mmol/L"
                                    let isHigh = readingDict["IsHigh"] as? Bool ?? false
                                    let isLow = readingDict["IsLow"] as? Bool ?? false
                                    
                                    let directReading = GlucoseReading(
                                        id: id,
                                        timestamp: timestamp,
                                        value: value,
                                        unit: unit,
                                        isHigh: isHigh,
                                        isLow: isLow
                                    )
                                    
                                    readings.append(directReading)
                                    print("Added reading with manually parsed timestamp: \(timestamp)")
                                } else {
                                    print("Failed to parse ISO timestamp: \(iso8601String)")
                                }
                            }
                        } catch {
                            print("JSON serialization error for reading \(index): \(error)")
                        }
                    }
                    
                    if !readings.isEmpty {
                        print("Successfully parsed \(readings.count) readings manually")
                        
                        // Log timestamp ranges
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        
                        // Log some raw timestamp strings from the original data
                        print("Original timestamp examples from API:")
                        for (i, reading) in readings.prefix(3).enumerated() {
                            print("  Example \(i): \(reading.timestamp) (type: \(type(of: reading.timestamp)))")
                        }
                        
                        // Check if we have multiple days
                        let allTimestamps = readings.map { $0.timestamp }
                        if let earliest = allTimestamps.min(), let latest = allTimestamps.max() {
                            print("Date range in parsed data: ")
                            print("  Earliest: \(dateFormatter.string(from: earliest))")  
                            print("  Latest: \(dateFormatter.string(from: latest))")
                            
                            let daysBetween = Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0
                            print("  Span: \(daysBetween) days")
                            
                            // Check for unique dates
                            let uniqueDates = Set(allTimestamps.map { dateFormatter.string(from: $0).prefix(10) })
                            print("  Unique dates: \(uniqueDates.count)")
                            if uniqueDates.count < 2 {
                                print("⚠️ WARNING: Not enough unique dates in the data!")
                            }
                        }
                        
                        // Check for duplicate timestamps and fix them if needed
                        var seenTimestamps = Set<Date>()
                        var readingsWithUniqueTimestamps: [GlucoseReading] = []
                        
                        for (index, reading) in readings.enumerated() {
                            // If we've already seen this exact timestamp, create a new one with a slight offset
                            if seenTimestamps.contains(reading.timestamp) {
                                // Modify timestamp by adding index seconds for uniqueness
                                let newTimestamp = reading.timestamp.addingTimeInterval(TimeInterval(index))
                                let uniqueReading = GlucoseReading(
                                    id: reading.id,
                                    timestamp: newTimestamp,
                                    value: reading.value,
                                    unit: reading.unit,
                                    isHigh: reading.isHigh,
                                    isLow: reading.isLow
                                )
                                readingsWithUniqueTimestamps.append(uniqueReading)
                                print("Fixed duplicate timestamp for reading \(index): \(reading.timestamp) -> \(newTimestamp)")
                            } else {
                                // This is a unique timestamp
                                seenTimestamps.insert(reading.timestamp)
                                readingsWithUniqueTimestamps.append(reading)
                            }
                        }
                        
                        // Sort readings by timestamp to ensure most recent first
                        let sortedReadings = readingsWithUniqueTimestamps.sorted { reading1, reading2 in
                            return reading1.timestamp > reading2.timestamp
                        }
                        
                        // Log stats about the timestamps
                        print("Original readings count: \(readings.count), unique timestamps: \(seenTimestamps.count)")
                        print("Final readings with unique timestamps: \(readingsWithUniqueTimestamps.count)")
                        
                        if let firstReading = sortedReadings.first {
                            print("Most recent reading: \(firstReading.value) \(firstReading.unit) at \(firstReading.timestamp)")
                        }
                        
                        // After all processing, check timestamp distribution
                        if !readings.isEmpty {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            
                            // Log raw timestamp format
                            print("\nRaw timestamp examples from parsed readings:")
                            for (i, reading) in readings.prefix(3).enumerated() {
                                print("  Example \(i): \(reading.timestamp) (type: \(type(of: reading.timestamp)))")
                            }
                            
                            // Check if we have multiple days
                            let allTimestamps = readings.map { $0.timestamp }
                            if let earliest = allTimestamps.min(), let latest = allTimestamps.max() {
                                print("\nDate range in parsed data:")
                                print("  Earliest: \(dateFormatter.string(from: earliest))")  
                                print("  Latest: \(dateFormatter.string(from: latest))")
                                
                                let daysBetween = Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0
                                print("  Span: \(daysBetween) days")
                                
                                // Check for unique dates
                                let uniqueDays = Set(allTimestamps.map { Calendar.current.startOfDay(for: $0) })
                                print("  Unique days: \(uniqueDays.count)")
                                
                                // Check for unique timestamps (should match readings count)
                                let uniqueTimestamps = Set(allTimestamps)
                                print("  Unique timestamps: \(uniqueTimestamps.count) out of \(readings.count) readings")
                                
                                if uniqueDays.count < 2 {
                                    print("⚠️ WARNING: Not enough unique dates in the data!")
                                    print("  This will cause filtering issues!")
                                }
                            }
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
    
    func transformReadingsForBetterFiltering(_ readings: [GlucoseReading]) -> [GlucoseReading] {
        // Since we're only focusing on today, yesterday, and the past 24 hours,
        // we don't need to transform the data anymore. Just return the original readings.
        let calendar = Calendar.current
        
        // Log the date range in the original data for debugging
        let timestamps = readings.map { $0.timestamp }
        if timestamps.isEmpty { return readings }
        
        if let earliest = timestamps.min(), let latest = timestamps.max() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let daysBetween = calendar.dateComponents([.day], from: earliest, to: latest).day ?? 0
            
            print("Original data spans \(daysBetween) days from \(dateFormatter.string(from: earliest)) to \(dateFormatter.string(from: latest))")
            print("Using \(readings.count) actual readings from LibreView API")
            
            // Count readings by day for debugging
            let uniqueDays = Set(timestamps.map { calendar.startOfDay(for: $0) })
            print("Found data for \(uniqueDays.count) unique days:")
            
            // Get counts by day
            var dayCount: [Date: Int] = [:]
            for timestamp in timestamps {
                let day = calendar.startOfDay(for: timestamp)
                dayCount[day, default: 0] += 1
            }
            
            // Print day counts sorted by date
            for day in dayCount.keys.sorted() {
                dateFormatter.dateFormat = "yyyy-MM-dd"
                print("  • \(dateFormatter.string(from: day)): \(dayCount[day] ?? 0) readings")
            }
        }
        
        return readings
    }
    
    private func fetchBasicGraph(patientId: String, token: String) async throws -> [GlucoseReading] {
        // Use the basic graph endpoint with no date parameters as a last resort
        let url = URL(string: "\(baseURL)/llu/connections/\(patientId)/graph")!
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers.merging(["Authorization": "Bearer \(token)"]) { $1 }
        
        print("Using basic graph endpoint as last resort")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LibreViewError.networkError
        }
        
        // Create and configure a flexible decoder
        let decoder = JSONDecoder()
        
        // Use the same date decoding strategy as the main method
        decoder.dateDecodingStrategy = .custom { decoder in
            // Same implementation as above
            // Duplicate the code here
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
            print("Basic graph endpoint decoding failed: \(error)")
            return []
        }
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