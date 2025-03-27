import Foundation
import CoreData

class CoreDataManager {
    static let shared = CoreDataManager()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let modelURL = Bundle.main.url(forResource: "DiabetesData", withExtension: "momd")!
        let container = NSPersistentContainer(name: "DiabetesData")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()
    
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