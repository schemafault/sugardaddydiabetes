import Foundation
import CoreData

// This file extends the generated InsulinShotEntity with helpful methods
// to ensure consistent access patterns between programmatic and model-based approaches

@objc(InsulinShotEntity)
public class InsulinShotEntity: NSManagedObject {
    // Implement the missing fetchRequest method
    @nonobjc public class func fetchRequest() -> NSFetchRequest<InsulinShotEntity> {
        return NSFetchRequest<InsulinShotEntity>(entityName: "InsulinShotEntity")
    }
}

extension InsulinShotEntity {
    // Convert a InsulinShotEntity to an InsulinShot domain model
    func toDomainModel() -> InsulinShot? {
        guard let idString = self.value(forKey: "id") as? String,
              let id = UUID(uuidString: idString),
              let timestamp = self.value(forKey: "timestamp") as? Date else {
            return nil
        }
        
        let dosage = self.value(forKey: "dosage") as? Double
        let notes = self.value(forKey: "notes") as? String
        
        return InsulinShot(id: id, timestamp: timestamp, dosage: dosage, notes: notes)
    }
    
    // Create or update an InsulinShotEntity from an InsulinShot domain model
    static func from(insulinShot: InsulinShot, context: NSManagedObjectContext) -> InsulinShotEntity {
        // Try to find existing entity
        let fetchRequest: NSFetchRequest<InsulinShotEntity> = InsulinShotEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", insulinShot.id.uuidString)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let existingEntity = results.first {
                // Update existing entity
                existingEntity.setValue(insulinShot.timestamp, forKey: "timestamp")
                existingEntity.setValue(insulinShot.dosage, forKey: "dosage")
                existingEntity.setValue(insulinShot.notes, forKey: "notes")
                return existingEntity
            }
        } catch {
            print("❌ Error searching for existing InsulinShotEntity: \(error)")
        }
        
        // Create new entity
        let entity = InsulinShotEntity(context: context)
        entity.setValue(insulinShot.id.uuidString, forKey: "id")
        entity.setValue(insulinShot.timestamp, forKey: "timestamp")
        entity.setValue(insulinShot.dosage, forKey: "dosage")
        entity.setValue(insulinShot.notes, forKey: "notes")
        return entity
    }
} 