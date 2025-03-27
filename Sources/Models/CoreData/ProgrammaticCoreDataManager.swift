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
        let entity = NSEntityDescription()
        entity.name = "GlucoseReadingEntity"
        entity.managedObjectClassName = "GlucoseReadingEntity"
        
        // Create attributes
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
        entity.properties = [
            idAttribute,
            timestampAttribute,
            valueAttribute,
            unitAttribute,
            isHighAttribute,
            isLowAttribute
        ]
        
        // Add uniqueness constraint with explicit array of NSPropertyDescription objects
        let uniqueConstraint = [idAttribute]
        entity.uniquenessConstraints = [uniqueConstraint]
        
        // Add entity to model
        model.entities = [entity]
        
        return model
    }
    
    lazy var persistentContainer: NSPersistentContainer = {
        let model = createManagedObjectModel()
        let container = NSPersistentContainer(name: "GlucoseData", managedObjectModel: model)
        
        // Configure for in-memory storage initially
        // We'll switch to disk-based if possible
        let storeDescription = NSPersistentStoreDescription()
        storeDescription.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [storeDescription]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Failed to load persistent store: \(error)")
            } else {
                print("Successfully loaded in-memory store")
                
                // After successful in-memory load, try to set up persistent store
                self.setupPersistentStore(for: container)
            }
        }
        
        return container
    }()
    
    private func setupPersistentStore(for container: NSPersistentContainer) {
        // Try to create a SQLite store
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupportDir.appendingPathComponent("GlucoseData.sqlite")
        
        do {
            // Create directory if needed
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            
            // Create store description
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            
            // Load the store
            try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [
                    NSMigratePersistentStoresAutomaticallyOption: true,
                    NSInferMappingModelAutomaticallyOption: true
                ]
            )
            
            print("Successfully set up persistent SQLite store at \(storeURL)")
        } catch {
            print("Failed to set up persistent store: \(error)")
            print("Continuing with in-memory store")
        }
    }
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // Save data to CoreData
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // Save glucose readings to CoreData
    func saveGlucoseReadings(_ readings: [GlucoseReading]) {
        let context = persistentContainer.viewContext
        
        readings.forEach { reading in
            // Check if this reading already exists to avoid duplicates
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
            fetchRequest.predicate = NSPredicate(format: "id == %@", reading.id)
            
            do {
                let existingReadings = try context.fetch(fetchRequest)
                if existingReadings.isEmpty {
                    // Create new reading if not found
                    let entity = NSEntityDescription.insertNewObject(forEntityName: "GlucoseReadingEntity", into: context)
                    entity.setValue(reading.id, forKey: "id")
                    entity.setValue(reading.timestamp, forKey: "timestamp")
                    entity.setValue(reading.value, forKey: "value")
                    entity.setValue(reading.unit, forKey: "unit")
                    entity.setValue(reading.isHigh, forKey: "isHigh")
                    entity.setValue(reading.isLow, forKey: "isLow")
                }
            } catch {
                print("Error checking for existing reading: \(error)")
            }
        }
        
        saveContext()
    }
    
    // Fetch all glucose readings
    func fetchAllGlucoseReadings() -> [GlucoseReading] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let result = try viewContext.fetch(fetchRequest)
            return result.compactMap { object -> GlucoseReading? in
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
        } catch {
            print("Error fetching readings: \(error)")
            return []
        }
    }
    
    // Fetch readings within a date range
    func fetchGlucoseReadings(from startDate: Date, to endDate: Date) -> [GlucoseReading] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        fetchRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let result = try viewContext.fetch(fetchRequest)
            return result.compactMap { object -> GlucoseReading? in
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
        } catch {
            print("Error fetching readings: \(error)")
            return []
        }
    }
} 