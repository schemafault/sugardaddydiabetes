import Foundation
import CoreData

class CoreDataManager {
    static let shared = CoreDataManager()
    private var isUsingInMemoryStore = false
    
    // Try to manually get Core Data model URL
    private func findModelURL() -> URL? {
        // First try with bundle
        if let modelURL = Bundle.main.url(forResource: "DiabetesData", withExtension: "momd") {
            print("Found model at: \(modelURL)")
            return modelURL
        }
        
        // Check if model file exists at common paths
        let fm = FileManager.default
        
        // Try paths where the model might be located
        let possiblePaths = [
            Bundle.main.bundlePath + "/Contents/Resources/DiabetesData.momd",
            Bundle.main.bundlePath + "/DiabetesData.momd",
            Bundle.main.resourcePath! + "/DiabetesData.momd",
            Bundle.main.resourcePath! + "/Models/CoreData/DiabetesData.momd"
        ]
        
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                print("Found model at path: \(path)")
                return URL(fileURLWithPath: path)
            }
        }
        
        // List resource paths to help debug
        if let resourcePath = Bundle.main.resourcePath {
            print("Resource path: \(resourcePath)")
            do {
                let contents = try fm.contentsOfDirectory(atPath: resourcePath)
                print("Resource directory contents: \(contents)")
            } catch {
                print("Error listing resource contents: \(error)")
            }
        }
        
        return nil
    }
    
    lazy var persistentContainer: NSPersistentContainer = {
        // Try to create a container from the model
        let container: NSPersistentContainer
        
        if let modelURL = findModelURL() {
            // If we found the model URL, create a model and container manually
            guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
                print("Failed to create model from URL: \(modelURL)")
                return fallbackToEmptyContainer()
            }
            
            container = NSPersistentContainer(name: "DiabetesData", managedObjectModel: model)
        } else {
            // Create the container directly with the name
            print("Using default container creation with name only")
            container = NSPersistentContainer(name: "DiabetesData")
        }
        
        // Configure store options
        let storeDescription = NSPersistentStoreDescription()
        storeDescription.shouldInferMappingModelAutomatically = true
        storeDescription.shouldMigrateStoreAutomatically = true
        
        container.persistentStoreDescriptions = [storeDescription]
        
        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                print("CoreData error: Failed to load persistent stores: \(error)")
                print("Store description: \(description)")
                // Log more details but don't crash
                if let detailedError = error as NSError? {
                    print("Domain: \(detailedError.domain), Code: \(detailedError.code)")
                    print("User info: \(detailedError.userInfo)")
                }
                
                // Fall back to in-memory store
                print("Falling back to in-memory store")
                self?.setupInMemoryStore(for: container)
            } else {
                print("CoreData: Successfully loaded persistent store")
            }
        }
        return container
    }()
    
    private func fallbackToEmptyContainer() -> NSPersistentContainer {
        print("Creating empty in-memory container")
        // Create a simple model programmatically
        let model = NSManagedObjectModel()
        let container = NSPersistentContainer(name: "InMemoryStore", managedObjectModel: model)
        
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Failed to create in-memory store: \(error)")
            } else {
                print("Successfully created empty in-memory store")
                self.isUsingInMemoryStore = true
            }
        }
        
        return container
    }
    
    private func setupInMemoryStore(for container: NSPersistentContainer) {
        // Remove any existing stores
        for description in container.persistentStoreDescriptions {
            if let url = description.url {
                try? container.persistentStoreCoordinator.destroyPersistentStore(at: url, ofType: description.type)
            }
        }
        
        // Configure in-memory store
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Failed to create in-memory store: \(error)")
            } else {
                print("Successfully created in-memory store")
                self.isUsingInMemoryStore = true
            }
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
        
        // Create a batch insert request for better performance
        readings.forEach { reading in
            // Check if this reading already exists to avoid duplicates
            let fetchRequest: NSFetchRequest<GlucoseReadingEntity> = GlucoseReadingEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", reading.id)
            
            do {
                let existingReadings = try context.fetch(fetchRequest)
                if existingReadings.isEmpty {
                    // Create new reading if not found
                    let entity = GlucoseReadingEntity(context: context)
                    entity.id = reading.id
                    entity.timestamp = reading.timestamp
                    entity.value = reading.value
                    entity.unit = reading.unit
                    entity.isHigh = reading.isHigh
                    entity.isLow = reading.isLow
                }
            } catch {
                print("Error checking for existing reading: \(error)")
            }
        }
        
        saveContext()
    }
    
    // Fetch all glucose readings
    func fetchAllGlucoseReadings() -> [GlucoseReading] {
        let fetchRequest: NSFetchRequest<GlucoseReadingEntity> = GlucoseReadingEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseReadingEntity.timestamp, ascending: false)]
        
        do {
            let entities = try viewContext.fetch(fetchRequest)
            return entities.map { entity in
                GlucoseReading(
                    id: entity.id ?? UUID().uuidString,
                    timestamp: entity.timestamp ?? Date(),
                    value: entity.value,
                    unit: entity.unit ?? "mg/dL",
                    isHigh: entity.isHigh,
                    isLow: entity.isLow
                )
            }
        } catch {
            print("Error fetching readings: \(error)")
            return []
        }
    }
    
    // Fetch readings within a date range
    func fetchGlucoseReadings(from startDate: Date, to endDate: Date) -> [GlucoseReading] {
        let fetchRequest: NSFetchRequest<GlucoseReadingEntity> = GlucoseReadingEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseReadingEntity.timestamp, ascending: false)]
        
        do {
            let entities = try viewContext.fetch(fetchRequest)
            return entities.map { entity in
                GlucoseReading(
                    id: entity.id ?? UUID().uuidString,
                    timestamp: entity.timestamp ?? Date(),
                    value: entity.value,
                    unit: entity.unit ?? "mg/dL",
                    isHigh: entity.isHigh,
                    isLow: entity.isLow
                )
            }
        } catch {
            print("Error fetching readings: \(error)")
            return []
        }
    }
} 