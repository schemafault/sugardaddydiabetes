import Foundation
import CoreData

// This is an alternative CoreData manager that creates the model programmatically
// instead of relying on the .xcdatamodeld file
class ProgrammaticCoreDataManager {
    static let shared = ProgrammaticCoreDataManager()
    
    // Create the model programmatically
    private func createManagedObjectModel() -> NSManagedObjectModel {
        // Create a new empty model
        let model = NSManagedObjectModel()
        
        // Create the GlucoseReadingEntity
        let glucoseEntity = NSEntityDescription()
        glucoseEntity.name = "GlucoseReadingEntity"
        glucoseEntity.managedObjectClassName = "GlucoseReadingEntity"
        
        // Create attributes for glucose entity
        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .stringAttributeType
        idAttribute.isOptional = false
        
        let timestampAttribute = NSAttributeDescription()
        timestampAttribute.name = "timestamp"
        timestampAttribute.attributeType = .dateAttributeType
        timestampAttribute.isOptional = false
        
        let valueAttribute = NSAttributeDescription()
        valueAttribute.name = "value"
        valueAttribute.attributeType = .doubleAttributeType
        valueAttribute.isOptional = false
        valueAttribute.defaultValue = 0.0
        
        let unitAttribute = NSAttributeDescription()
        unitAttribute.name = "unit"
        unitAttribute.attributeType = .stringAttributeType
        unitAttribute.isOptional = false
        
        let isHighAttribute = NSAttributeDescription()
        isHighAttribute.name = "isHigh"
        isHighAttribute.attributeType = .booleanAttributeType
        isHighAttribute.isOptional = true
        
        let isLowAttribute = NSAttributeDescription()
        isLowAttribute.name = "isLow"
        isLowAttribute.attributeType = .booleanAttributeType
        isLowAttribute.isOptional = true
        
        // Add attributes to entity
        glucoseEntity.properties = [
            idAttribute,
            timestampAttribute,
            valueAttribute,
            unitAttribute,
            isHighAttribute,
            isLowAttribute
        ]
        
        // Add uniqueness constraint with explicit array of NSPropertyDescription objects
        let glucoseUniqueConstraint = [idAttribute]
        glucoseEntity.uniquenessConstraints = [glucoseUniqueConstraint]
        
        // Create the PatientProfile entity
        let patientEntity = NSEntityDescription()
        patientEntity.name = "PatientProfile"
        patientEntity.managedObjectClassName = "PatientProfile"
        
        // Create attributes for patient entity
        let patientIdAttribute = NSAttributeDescription()
        patientIdAttribute.name = "id"
        patientIdAttribute.attributeType = .stringAttributeType
        patientIdAttribute.isOptional = false
        
        let nameAttribute = NSAttributeDescription()
        nameAttribute.name = "name"
        nameAttribute.attributeType = .stringAttributeType
        nameAttribute.isOptional = true
        
        let dobAttribute = NSAttributeDescription()
        dobAttribute.name = "dateOfBirth"
        dobAttribute.attributeType = .dateAttributeType
        dobAttribute.isOptional = true
        
        let weightAttribute = NSAttributeDescription()
        weightAttribute.name = "weight"
        weightAttribute.attributeType = .doubleAttributeType
        weightAttribute.isOptional = true
        weightAttribute.defaultValue = 0.0
        
        let weightUnitAttribute = NSAttributeDescription()
        weightUnitAttribute.name = "weightUnit"
        weightUnitAttribute.attributeType = .stringAttributeType
        weightUnitAttribute.isOptional = true
        
        let insulinTypeAttribute = NSAttributeDescription()
        insulinTypeAttribute.name = "insulinType"
        insulinTypeAttribute.attributeType = .stringAttributeType
        insulinTypeAttribute.isOptional = true
        
        let insulinDoseAttribute = NSAttributeDescription()
        insulinDoseAttribute.name = "insulinDose"
        insulinDoseAttribute.attributeType = .stringAttributeType
        insulinDoseAttribute.isOptional = true
        
        let otherMedicationsAttribute = NSAttributeDescription()
        otherMedicationsAttribute.name = "otherMedications"
        otherMedicationsAttribute.attributeType = .stringAttributeType
        otherMedicationsAttribute.isOptional = true
        
        // Add attributes to patient entity
        patientEntity.properties = [
            patientIdAttribute,
            nameAttribute,
            dobAttribute,
            weightAttribute,
            weightUnitAttribute,
            insulinTypeAttribute,
            insulinDoseAttribute,
            otherMedicationsAttribute
        ]
        
        // Add uniqueness constraint for patient
        let patientUniqueConstraint = [patientIdAttribute]
        patientEntity.uniquenessConstraints = [patientUniqueConstraint]
        
        // Add entities to model
        model.entities = [glucoseEntity, patientEntity]
        
        return model
    }
    
    lazy var persistentContainer: NSPersistentContainer = {
        print("🗄️ Initializing CoreData persistent container...")
        let model = createManagedObjectModel()
        let container = NSPersistentContainer(name: "GlucoseData", managedObjectModel: model)
        
        // Set up Application Support directory path
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupportDir.appendingPathComponent("GlucoseData.sqlite")
        
        print("📂 CoreData store location: \(storeURL.path)")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: appSupportDir.path) {
            do {
                try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: nil)
                print("📁 Created Application Support directory")
            } catch {
                print("❌ Failed to create directory: \(error.localizedDescription)")
            }
        }
        
        // Create a SQLite store description
        let sqliteStoreDescription = NSPersistentStoreDescription(url: storeURL)
        sqliteStoreDescription.type = NSSQLiteStoreType
        sqliteStoreDescription.shouldMigrateStoreAutomatically = true
        sqliteStoreDescription.shouldInferMappingModelAutomatically = true
        
        // Set the store description on the container
        container.persistentStoreDescriptions = [sqliteStoreDescription]
        
        // Load the persistent store synchronously
        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("❌ Failed to load persistent store: \(error.localizedDescription)")
                
                if let nsError = error as NSError? {
                    print("⚠️ Error details - domain: \(nsError.domain), code: \(nsError.code)")
                    print("⚠️ User info: \(nsError.userInfo)")
                }
                
                // If SQLite fails, try creating an in-memory store as fallback
                print("⚠️ Setting up in-memory store as fallback")
                let inMemoryDescription = NSPersistentStoreDescription()
                inMemoryDescription.type = NSInMemoryStoreType
                
                // Remove the failed store
                for store in container.persistentStoreCoordinator.persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
                
                // Add and load the in-memory store
                container.persistentStoreDescriptions = [inMemoryDescription]
                container.loadPersistentStores { _, loadError in
                    if let loadError = loadError {
                        print("❌ Also failed to load in-memory store: \(loadError)")
                    } else {
                        print("✅ Successfully loaded in-memory store (data will not persist between app launches)")
                    }
                }
            } else {
                print("✅ Successfully loaded persistent SQLite store at \(storeURL.path)")
                // Check if SQLite file exists now
                if FileManager.default.fileExists(atPath: storeURL.path) {
                    print("✅ SQLite file exists on disk")
                    
                    // Get file size
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
                        if let size = attributes[FileAttributeKey.size] as? NSNumber {
                            print("📊 SQLite file size: \(size.intValue / 1024) KB")
                        }
                    } catch {
                        print("❌ Error getting file attributes: \(error)")
                    }
                } else {
                    print("⚠️ SQLite file does not exist at expected location")
                }
            }
        }
        
        return container
    }()
    
    // We now handle in-memory store setup directly in the persistentContainer initialization
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // Save data to CoreData
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            print("💾 Saving changes to CoreData...")
            do {
                try context.save()
                print("✅ Changes saved successfully")
                
                // Verify persistence - check if SQLite file exists and has been updated
                let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let storeURL = appSupportDir.appendingPathComponent("GlucoseData.sqlite")
                
                if FileManager.default.fileExists(atPath: storeURL.path) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
                        if let size = attributes[FileAttributeKey.size] as? NSNumber,
                           let modDate = attributes[FileAttributeKey.modificationDate] as? Date {
                            print("📊 SQLite file size: \(size.intValue / 1024) KB, Last modified: \(modDate)")
                        }
                    } catch {
                        print("❌ Error checking file attributes: \(error)")
                    }
                }
            } catch {
                let nsError = error as NSError
                print("❌ Failed to save changes: \(nsError), \(nsError.userInfo)")
            }
        } else {
            print("⚠️ No changes to save")
        }
    }
    
    // Save glucose readings to CoreData
    func saveGlucoseReadings(_ readings: [GlucoseReading]) {
        guard !readings.isEmpty else {
            print("⚠️ No readings to save")
            return
        }
        
        print("🔄 Saving \(readings.count) readings to CoreData...")
        let context = persistentContainer.viewContext
        
        // DEBUG: Log the date range of readings being saved
        if !readings.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let firstDate = readings.map({ $0.timestamp }).min(),
               let lastDate = readings.map({ $0.timestamp }).max() {
                print("📅 INCOMING DATA: Date range \(formatter.string(from: firstDate)) to \(formatter.string(from: lastDate))")
            }
        }
        
        // Start a background task
        Task {
            // Get all existing IDs in a single fetch to avoid multiple queries
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
            fetchRequest.propertiesToFetch = ["id"]
            fetchRequest.resultType = .dictionaryResultType
            
            var existingIds = Set<String>()
            
            do {
                let results = try context.fetch(fetchRequest)
                for case let result as [String: Any] in results {
                    if let id = result["id"] as? String {
                        existingIds.insert(id)
                    }
                }
                print("📋 Found \(existingIds.count) existing readings in database")
                
                // Print time range of existing data (debug)
                if !existingIds.isEmpty {
                    let timeRangeRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
                    timeRangeRequest.propertiesToFetch = ["timestamp"]
                    
                    let timestampResults = try context.fetch(timeRangeRequest)
                    var timestamps: [Date] = []
                    
                    for case let result as NSManagedObject in timestampResults {
                        if let timestamp = result.value(forKey: "timestamp") as? Date {
                            timestamps.append(timestamp)
                        }
                    }
                    
                    if let earliest = timestamps.min(), let latest = timestamps.max() {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        print("⏱️ Existing data range: \(formatter.string(from: earliest)) to \(formatter.string(from: latest))")
                    }
                }
            } catch {
                print("❌ Error fetching existing IDs: \(error)")
                existingIds = [] // Continue with empty set if fetch fails
            }
            
            // Batch processing to reduce memory pressure
            var newReadingsCount = 0
            let batchSize = 50
            
            for i in stride(from: 0, to: readings.count, by: batchSize) {
                let batchEnd = min(i + batchSize, readings.count)
                let batch = readings[i..<batchEnd]
                
                // Add new readings (those not in existingIds)
                for reading in batch {
                    // Skip if this reading already exists
                    if existingIds.contains(reading.id) {
                        continue
                    }
                    
                    // Create a new entity for this reading
                    let entity = NSEntityDescription.insertNewObject(forEntityName: "GlucoseReadingEntity", into: context)
                    entity.setValue(reading.id, forKey: "id")
                    entity.setValue(reading.timestamp, forKey: "timestamp")
                    entity.setValue(reading.value, forKey: "value")
                    entity.setValue(reading.unit, forKey: "unit")
                    entity.setValue(reading.isHigh, forKey: "isHigh")
                    entity.setValue(reading.isLow, forKey: "isLow")
                    
                    newReadingsCount += 1
                    existingIds.insert(reading.id) // Track newly added IDs
                }
                
                // Save each batch to avoid memory issues with large datasets
                if newReadingsCount > 0 && context.hasChanges {
                    saveContext()
                }
            }
            
            print("✅ Added \(newReadingsCount) new readings")
            
            // Perform final verification
            verifyDataIntegrity()
        }
    }
    
    // Helper method to verify data is correctly stored
    private func verifyDataIntegrity() {
        let context = persistentContainer.viewContext
        
        // Count request
        let countRequest = NSFetchRequest<NSNumber>(entityName: "GlucoseReadingEntity")
        countRequest.resultType = .countResultType
        
        // Date range request
        let rangeRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        rangeRequest.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: true)
        ]
        
        do {
            // Get total count
            let countResult = try context.fetch(countRequest)
            let totalCount = countResult.first?.intValue ?? 0
            
            print("📊 Database now contains \(totalCount) readings total")
            
            // Get first and last reading to determine date range
            let rangeResults = try context.fetch(rangeRequest)
            
            if let firstObj = rangeResults.first as? NSManagedObject,
               let lastObj = rangeResults.last as? NSManagedObject,
               let firstDate = firstObj.value(forKey: "timestamp") as? Date,
               let lastDate = lastObj.value(forKey: "timestamp") as? Date {
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                let daysBetween = Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0
                
                print("📅 Data spans \(daysBetween) days:")
                print("   Earliest: \(formatter.string(from: firstDate))")
                print("   Latest: \(formatter.string(from: lastDate))")
                
                // Count readings per day (for first few days)
                let calendar = Calendar.current
                var dayMap: [Date: Int] = [:]
                
                for case let obj as NSManagedObject in rangeResults {
                    if let date = obj.value(forKey: "timestamp") as? Date {
                        let day = calendar.startOfDay(for: date)
                        dayMap[day, default: 0] += 1
                    }
                }
                
                print("📆 Readings by day (showing first 5):")
                let sortedDays = dayMap.keys.sorted(by: >)
                for day in sortedDays.prefix(5) {
                    formatter.dateFormat = "yyyy-MM-dd"
                    print("   \(formatter.string(from: day)): \(dayMap[day] ?? 0) readings")
                }
            }
        } catch {
            print("❌ Error verifying data integrity: \(error)")
        }
    }
    
    // Fetch all glucose readings
    func fetchAllGlucoseReadings() -> [GlucoseReading] {
        print("📚 Fetching all glucose readings from database...")
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        // Sort by timestamp descending (newest first)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        // DEBUG: Add print for SQLite file
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupportDir.appendingPathComponent("GlucoseData.sqlite")
        print("📂 CRITICAL DEBUG: Checking CoreData store at \(storeURL.path)")
        
        if fileManager.fileExists(atPath: storeURL.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: storeURL.path)
                if let size = attributes[.size] as? NSNumber {
                    let sizeKB = size.intValue / 1024
                    print("📊 CRITICAL DEBUG: Database file exists! Size: \(sizeKB) KB")
                    if let modDate = attributes[.modificationDate] as? Date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        print("📅 CRITICAL DEBUG: Last modified: \(formatter.string(from: modDate))")
                    }
                }
            } catch {
                print("❌ CRITICAL DEBUG: Error checking file: \(error)")
            }
        } else {
            print("❌ CRITICAL DEBUG: CoreData SQLite file DOES NOT EXIST!")
        }
        
        do {
            // Execute fetch request
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try viewContext.fetch(fetchRequest)
            let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
            print("⏱️ Fetch completed in \(String(format: "%.3f", fetchTime)) seconds")
            
            // Map CoreData objects to model objects
            let readings = result.compactMap { object -> GlucoseReading? in
                guard let object = object as? NSManagedObject else { return nil }
                
                return GlucoseReading(
                    id: object.value(forKey: "id") as? String ?? UUID().uuidString,
                    timestamp: object.value(forKey: "timestamp") as? Date ?? Date(),
                    value: object.value(forKey: "value") as? Double ?? 0.0,
                    unit: object.value(forKey: "unit") as? String ?? "mg/dL",
                    isHigh: object.value(forKey: "isHigh") as? Bool ?? false,
                    isLow: object.value(forKey: "isLow") as? Bool ?? false
                )
            }
            
            print("📊 Fetched \(readings.count) readings from database")
            
            // Analyze date range
            if !readings.isEmpty {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                if let earliest = readings.map({ $0.timestamp }).min(),
                   let latest = readings.map({ $0.timestamp }).max() {
                    let calendar = Calendar.current
                    let days = calendar.dateComponents([.day], from: earliest, to: latest).day ?? 0
                    
                    print("📅 Date range: \(dateFormatter.string(from: earliest)) to \(dateFormatter.string(from: latest))")
                    print("📆 Spanning \(days) days")
                    
                    // Check unique days
                    let uniqueDays = Set(readings.map { calendar.startOfDay(for: $0.timestamp) })
                    print("🗓️ Covering \(uniqueDays.count) unique days")
                    
                    // Count readings per day (for the most recent 5 days)
                    var dayMap: [Date: Int] = [:]
                    for reading in readings {
                        let day = calendar.startOfDay(for: reading.timestamp)
                        dayMap[day, default: 0] += 1
                    }
                    
                    print("📊 Readings by day (most recent 5):")
                    let sortedDays = dayMap.keys.sorted(by: >)
                    for day in sortedDays.prefix(5) {
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        print("   \(dateFormatter.string(from: day)): \(dayMap[day] ?? 0) readings")
                    }
                    
                    // Print sample of readings
                    if readings.count > 0 {
                        let sample = min(5, readings.count)
                        print("🔍 Sample of first \(sample) readings:")
                        for i in 0..<sample {
                            let reading = readings[i]
                            print("  - \(dateFormatter.string(from: reading.timestamp)): \(reading.value) \(reading.unit)")
                        }
                    }
                }
            } else {
                print("⚠️ Warning: No readings found in database")
            }
            
            return readings
        } catch {
            print("❌ Error fetching readings: \(error)")
            return []
        }
    }
    
    // Fetch readings within a date range
    func fetchGlucoseReadings(from startDate: Date, to endDate: Date) -> [GlucoseReading] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        
        // Create a predicate that includes all readings in the date range
        fetchRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("🔍 Fetching readings from \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate))")
        
        do {
            let result = try viewContext.fetch(fetchRequest)
            let readings = result.compactMap { object -> GlucoseReading? in
                guard let object = object as? NSManagedObject else { return nil }
                
                return GlucoseReading(
                    id: object.value(forKey: "id") as? String ?? UUID().uuidString,
                    timestamp: object.value(forKey: "timestamp") as? Date ?? Date(),
                    value: object.value(forKey: "value") as? Double ?? 0.0,
                    unit: object.value(forKey: "unit") as? String ?? "mg/dL",
                    isHigh: object.value(forKey: "isHigh") as? Bool ?? false,
                    isLow: object.value(forKey: "isLow") as? Bool ?? false
                )
            }
            
            print("✅ Found \(readings.count) readings in date range")
            
            // Print diagnostic info if there are readings
            if !readings.isEmpty {
                // Date range of actual results
                if let earliest = readings.map({ $0.timestamp }).min(),
                   let latest = readings.map({ $0.timestamp }).max() {
                    print("📅 Results span: \(dateFormatter.string(from: earliest)) to \(dateFormatter.string(from: latest))")
                }
                
                // Show count by day
                let calendar = Calendar.current
                var dayMap: [Date: Int] = [:]
                for reading in readings {
                    let day = calendar.startOfDay(for: reading.timestamp)
                    dayMap[day, default: 0] += 1
                }
                
                if !dayMap.isEmpty {
                    print("📊 Readings by day:")
                    let sortedDays = dayMap.keys.sorted()
                    for day in sortedDays {
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        print("   \(dateFormatter.string(from: day)): \(dayMap[day] ?? 0) readings")
                    }
                }
            }
            
            return readings
        } catch {
            print("❌ Error fetching readings by date range: \(error)")
            return []
        }
    }
    
    // MARK: - Patient Profile Methods
    
    /// Save or update a patient profile in CoreData
    func savePatientProfile(id: String, name: String?, dateOfBirth: Date?, weight: Double?, weightUnit: String?, insulinType: String?, insulinDose: String?, otherMedications: String?) {
        let context = persistentContainer.viewContext

        // Check if profile already exists
        let fetchRequest: NSFetchRequest<PatientProfile> = PatientProfile.fetchRequest() // Use generated fetch request
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        do {
            let existingProfiles = try context.fetch(fetchRequest)

            let profileEntity: PatientProfile // Use the generated class type

            if let existingProfile = existingProfiles.first {
                // Update existing profile
                profileEntity = existingProfile
            } else {
                // Create new profile
                profileEntity = PatientProfile(context: context) // Use generated initializer
                profileEntity.id = id
            }

            // Set or update values
            profileEntity.name = name
            profileEntity.dateOfBirth = dateOfBirth
            // Handle Double for weight - Core Data generated class might use NSDecimalNumber or Double directly. Assuming Double for now.
            // If 'weight' is primitive Double in Core Data, direct assignment is fine.
            // If it's non-primitive (e.g., NSDecimalNumber), conversion might be needed. Check generated class if build fails here.
            if let weight = weight {
                 profileEntity.weight = weight // Assuming weight is Double or NSNumber
            } else {
                 profileEntity.weight = 0 // Or handle nil appropriately, maybe don't set? Needs decision based on model logic. Setting to 0 for now.
            }
            profileEntity.weightUnit = weightUnit
            profileEntity.insulinType = insulinType
            profileEntity.insulinDose = insulinDose
            profileEntity.otherMedications = otherMedications

            // Save the context
            try context.save()
            print("✅ Saved patient profile with ID: \(id)") // id is non-optional here
        } catch {
            print("❌ Failed to save patient profile: \(error)")
        }
    }

    /// Fetch the patient profile from CoreData
    /// Since this is a single-user app, we'll just fetch the first profile found
    func fetchPatientProfile() -> PatientProfile? { // Return the generated NSManagedObject subclass
        let context = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<PatientProfile> = PatientProfile.fetchRequest() // Use generated fetch request

        // Optional: Add sorting if multiple profiles could somehow exist and you want a specific one
        // fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PatientProfile.creationDate, ascending: true)]

        do {
            let results = try context.fetch(fetchRequest)

            guard let profileEntity = results.first else {
                print("ℹ️ No patient profile found")
                return nil
            }

            // Return the managed object directly
            return profileEntity

            // No need to manually map properties anymore
            /*
            // Extract values from the entity
            let id = profileEntity.id ?? UUID().uuidString // Access properties directly
            let name = profileEntity.name ?? ""
            let dateOfBirth = profileEntity.dateOfBirth
            let weight = profileEntity.weight // Assuming Double
            let weightUnit = profileEntity.weightUnit
            let insulinType = profileEntity.insulinType
            let insulinDose = profileEntity.insulinDose
            let otherMedications = profileEntity.otherMedications

            // Create and return the profile
            // This intermediate struct is no longer needed if it was defined in the deleted file
            return PatientProfile(
                id: id,
                name: name,
                dateOfBirth: dateOfBirth,
                weight: weight,
                weightUnit: weightUnit,
                insulinType: insulinType,
                insulinDose: insulinDose,
                otherMedications: otherMedications
            )
            */
        } catch {
            print("❌ Failed to fetch patient profile: \(error)")
            return nil
        }
    }
} 