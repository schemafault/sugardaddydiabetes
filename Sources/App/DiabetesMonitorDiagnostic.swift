import Foundation
import CoreData
import SwiftUI

/// This is a diagnostic class to help analyze potential duplicate readings
/// without modifying any existing data
class DiabetesDataDiagnostic {
    static let shared = DiabetesDataDiagnostic()
    
    /// Scans the database for potential duplicate readings based on timestamp
    /// without modifying any data
    func analyzeDuplicateReadings(coreDataManager: ProgrammaticCoreDataManager) {
        print("🔍 DIAGNOSTIC: Beginning duplicate reading analysis...")
        
        let viewContext = coreDataManager.viewContext
        
        // Create a fetch request for all glucose readings
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            let result = try viewContext.fetch(fetchRequest)
            let allReadings = result.compactMap { object -> (id: String, timestamp: Date, value: Double)? in
                guard let object = object as? NSManagedObject,
                      let id = object.value(forKey: "id") as? String,
                      let timestamp = object.value(forKey: "timestamp") as? Date,
                      let value = object.value(forKey: "value") as? Double else {
                    return nil
                }
                
                return (id, timestamp, value)
            }
            
            print("📊 DIAGNOSTIC: Found \(allReadings.count) total readings in database")
            
            // Look for readings with duplicate timestamps (to the second)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            // Group readings by timestamp strings (accurate to the second)
            var readingsByTimestamp: [String: [(id: String, timestamp: Date, value: Double)]] = [:]
            
            for reading in allReadings {
                let timestampKey = dateFormatter.string(from: reading.timestamp)
                if readingsByTimestamp[timestampKey] == nil {
                    readingsByTimestamp[timestampKey] = []
                }
                readingsByTimestamp[timestampKey]?.append(reading)
            }
            
            // Find duplicates
            var totalDuplicates = 0
            var duplicateGroups: [String: [(id: String, timestamp: Date, value: Double)]] = [:]
            
            for (timestamp, readings) in readingsByTimestamp where readings.count > 1 {
                duplicateGroups[timestamp] = readings
                totalDuplicates += readings.count - 1 // Count duplicates (original doesn't count)
            }
            
            print("📊 DIAGNOSTIC: Found \(duplicateGroups.count) timestamp groups with duplicates")
            print("📊 DIAGNOSTIC: Total duplicate readings: \(totalDuplicates)")
            print("📊 DIAGNOSTIC: Unique timestamps: \(readingsByTimestamp.count)")
            
            // Show some examples of duplicates
            if !duplicateGroups.isEmpty {
                print("🔍 DIAGNOSTIC: Examples of duplicate readings:")
                
                let exampleCount = min(5, duplicateGroups.count)
                let exampleTimestamps = Array(duplicateGroups.keys.sorted().prefix(exampleCount))
                
                for timestamp in exampleTimestamps {
                    print("  📅 Timestamp: \(timestamp)")
                    for (index, reading) in duplicateGroups[timestamp]!.enumerated() {
                        print("    - Reading \(index+1): ID \(reading.id), Value \(reading.value)")
                    }
                    print("")
                }
                
                // Analyze date distribution of duplicates
                analyzeTimestampDistribution(duplicateGroups: duplicateGroups)
            }
            
        } catch {
            print("❌ DIAGNOSTIC: Error analyzing readings: \(error)")
        }
    }
    
    /// Analyzes the distribution of duplicate timestamps
    private func analyzeTimestampDistribution(duplicateGroups: [String: [(id: String, timestamp: Date, value: Double)]]) {
        print("📆 DIAGNOSTIC: Analyzing timestamp distribution of duplicates...")
        
        var countByDay: [String: Int] = [:]
        
        // Extract all timestamps
        let allDuplicateDates = duplicateGroups.values.flatMap { $0 }.map { $0.timestamp }
        
        // Group by day
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for date in allDuplicateDates {
            let dayKey = dateFormatter.string(from: date)
            countByDay[dayKey, default: 0] += 1
        }
        
        // Sort days and print distribution
        let sortedDays = countByDay.keys.sorted()
        print("📊 DIAGNOSTIC: Duplicate readings by day:")
        
        for day in sortedDays {
            print("  • \(day): \(countByDay[day] ?? 0) duplicates")
        }
    }
    
    // MARK: - Database Cleanup Functions
    
    /// Creates a backup of the Core Data database before cleaning up duplicates
    /// Returns the backup path if successful
    func backupDatabase() -> String? {
        guard let persistentStoreURL = getPersistentStoreURL() else {
            print("❌ CLEANUP: Error - Could not determine database location")
            return nil
        }
        
        let fileManager = FileManager.default
        
        // Create a backup filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Use the parent directory of the database file
        let databaseDirectory = persistentStoreURL.deletingLastPathComponent()
        let backupFileName = "DiabetesData_Backup_\(timestamp).sqlite"
        let backupURL = databaseDirectory.appendingPathComponent(backupFileName)
        
        do {
            // Copy the database file to the backup location
            try fileManager.copyItem(at: persistentStoreURL, to: backupURL)
            print("✅ CLEANUP: Database backup created at: \(backupURL.path)")
            return backupURL.path
        } catch {
            print("❌ CLEANUP: Failed to create database backup: \(error)")
            return nil
        }
    }
    
    /// Helper to get the URL of the persistent store
    private func getPersistentStoreURL() -> URL? {
        // First try to get the sqlite file directly
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        
        // Check the default location for Core Data SQLite stores
        if let appBundle = Bundle.main.bundleIdentifier,
           let appSupportURL = appSupportURL?.appendingPathComponent(appBundle) {
            let dbURL = appSupportURL.appendingPathComponent("DiabetesData.sqlite")
            
            if FileManager.default.fileExists(atPath: dbURL.path) {
                print("📦 CLEANUP: Found database at: \(dbURL.path)")
                return dbURL
            }
        }
        
        // We can't access the private coreDataManager property directly
        // Instead, we'll use the known database names and search common locations
        
        // Search in common locations - explicitly typed as [URL?]
        let potentialLocations: [URL?] = [
            // App Support
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            // Documents
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            // Application directory
            Bundle.main.bundleURL.deletingLastPathComponent(),
            // Temporary directory
            URL(fileURLWithPath: NSTemporaryDirectory())
        ]
        
        // Common filenames to check
        let databaseNames = [
            "DiabetesData.sqlite",
            "DiabetesMonitor.sqlite",
            "persistentStore.sqlite"
        ]
        
        // Use compactMap to filter out nil values and then check each potential location
        for baseURL in potentialLocations.compactMap({ $0 }) {
            for name in databaseNames {
                let potentialURL = baseURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: potentialURL.path) {
                    print("📦 CLEANUP: Found database at: \(potentialURL.path)")
                    return potentialURL
                }
            }
        }
        
        print("❌ CLEANUP: Could not locate the database file")
        return nil
    }
    
    /// Clean up duplicate readings in the database
    /// This preserves exactly one reading per unique timestamp
    /// Returns a tuple containing (success, uniqueCount, duplicatesRemoved)
    func cleanupDuplicateReadings(coreDataManager: ProgrammaticCoreDataManager) -> (success: Bool, uniqueCount: Int, duplicatesRemoved: Int) {
        print("🧹 CLEANUP: Starting database cleanup operation...")
        
        let viewContext = coreDataManager.viewContext
        
        // Create a fetch request for all glucose readings
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseReadingEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            // First fetch all readings
            let result = try viewContext.fetch(fetchRequest)
            print("📊 CLEANUP: Fetched \(result.count) total readings")
            
            // Group readings by timestamp string (accurate to the second)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            var readingsByTimestamp: [String: [NSManagedObject]] = [:]
            var totalReadings = 0
            
            // Group readings by timestamp
            for case let object as NSManagedObject in result {
                guard let timestamp = object.value(forKey: "timestamp") as? Date else {
                    continue
                }
                
                totalReadings += 1
                let timestampKey = dateFormatter.string(from: timestamp)
                
                if readingsByTimestamp[timestampKey] == nil {
                    readingsByTimestamp[timestampKey] = []
                }
                readingsByTimestamp[timestampKey]?.append(object)
            }
            
            print("📊 CLEANUP: Found \(readingsByTimestamp.count) unique timestamps out of \(totalReadings) total readings")
            
            // Count how many will be deleted
            var duplicatesToDelete = 0
            for (_, readings) in readingsByTimestamp {
                if readings.count > 1 {
                    duplicatesToDelete += readings.count - 1
                }
            }
            
            print("📊 CLEANUP: Will preserve \(readingsByTimestamp.count) readings and delete \(duplicatesToDelete) duplicates")
            
            // Begin a batch delete operation
            var objectsToDelete: [NSManagedObject] = []
            
            // For each timestamp group, keep the first reading and delete the rest
            for (timestamp, readings) in readingsByTimestamp where readings.count > 1 {
                // Keep the first reading in each group
                let keep = readings[0]
                let duplicates = Array(readings.dropFirst())
                
                // Add duplicates to the delete list
                objectsToDelete.append(contentsOf: duplicates)
                
                // Log information about preserved reading
                if let id = keep.value(forKey: "id") as? String,
                   let value = keep.value(forKey: "value") as? Double {
                    print("✅ CLEANUP: Keeping reading ID \(id) with value \(value) for timestamp \(timestamp)")
                }
            }
            
            // Perform the deletion in batches to avoid memory issues
            let batchSize = 1000
            let totalBatches = (objectsToDelete.count + batchSize - 1) / batchSize
            var deletedCount = 0
            
            for batchIndex in 0..<totalBatches {
                let start = batchIndex * batchSize
                let end = min(start + batchSize, objectsToDelete.count)
                let currentBatch = Array(objectsToDelete[start..<end])
                
                for object in currentBatch {
                    viewContext.delete(object)
                }
                
                // Save after each batch
                try viewContext.save()
                deletedCount += currentBatch.count
                print("🧹 CLEANUP: Deleted batch \(batchIndex + 1)/\(totalBatches) (\(deletedCount)/\(objectsToDelete.count) entries)")
            }
            
            // Final save to ensure all changes are persisted
            try viewContext.save()
            
            print("✅ CLEANUP: Successfully completed database cleanup")
            print("✅ CLEANUP: Preserved \(readingsByTimestamp.count) unique readings")
            print("✅ CLEANUP: Removed \(deletedCount) duplicate readings")
            
            return (true, readingsByTimestamp.count, deletedCount)
        } catch {
            print("❌ CLEANUP: Error cleaning up database: \(error)")
            return (false, 0, 0)
        }
    }
} 