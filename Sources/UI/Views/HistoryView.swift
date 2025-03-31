import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    // CRITICAL: Default to All to ensure users see ALL historical data
    @State private var selectedTimeFrame: TimeFrame = .all
    @State private var searchText: String = ""
    @State private var showFilters: Bool = false
    @State private var filterRange: GlucoseReading.RangeStatus? = nil
    
    enum TimeFrame: String, CaseIterable, Identifiable {
        case day = "24 Hours"
        case week = "Week"
        case month = "Month"
        case all = "All"
        
        var id: String { self.rawValue }
    }
    
    private var filteredReadings: [GlucoseReading] {
        // Check what's in appState.glucoseHistory
        if appState.glucoseHistory.isEmpty {
            print("DEBUG: glucoseHistory in AppState is EMPTY!")
        } else {
            let earliest = appState.glucoseHistory.map { $0.timestamp }.min()!
            let latest = appState.glucoseHistory.map { $0.timestamp }.max()!
            print("DEBUG: AppState.glucoseHistory spans from \(earliest) to \(latest)")
            print("DEBUG: Has \(appState.glucoseHistory.count) readings")
        }
        
        // CRITICAL FIX: Make sure the timeFiltered has a copy of the readings, not a reference
        let timeFiltered = filteredByTime(Array(appState.glucoseHistory))
        let searchFiltered = filteredBySearch(timeFiltered)
        let rangeFiltered = filteredByRange(searchFiltered)
        
        // Sort by timestamp (newest first) for consistency
        return rangeFiltered.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    private func filteredByTime(_ readings: [GlucoseReading]) -> [GlucoseReading] {
        // Get current date and calendar
        let calendar = Calendar.current
        let now = Date()
        
        // If empty, return early
        if readings.isEmpty {
            return []
        }
        
        // Get date range for debug purposes
        let timestamps = readings.map { $0.timestamp }
        let oldest = timestamps.min()!
        let newest = timestamps.max()!
        print("DEBUG: All readings span from \(oldest) to \(newest)")
        print("DEBUG: Total of \(readings.count) readings available")
        
        var result: [GlucoseReading] = []
        
        // Calculate time boundary based on selected filter
        switch selectedTimeFrame {
        case .day:
            let dayAgo = calendar.date(byAdding: .day, value: -1, to: now)!
            print("DEBUG: Filtering readings >= \(dayAgo)")
            // Strictly apply the filter
            result = readings.filter { reading in
                reading.timestamp >= dayAgo
            }
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            print("DEBUG: Filtering readings >= \(weekAgo)")
            // Strictly apply the filter
            result = readings.filter { reading in
                reading.timestamp >= weekAgo
            }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            print("DEBUG: Filtering readings >= \(monthAgo)")
            // Strictly apply the filter
            result = readings.filter { reading in
                reading.timestamp >= monthAgo
            }
        case .all:
            print("DEBUG: Showing all readings, no time filter applied")
            // Return all readings for "All" filter
            result = readings
        }
        
        // Log the result
        print("DEBUG: Time filter returned \(result.count) of \(readings.count) readings")
        
        return result
    }
    
    private func filteredBySearch(_ readings: [GlucoseReading]) -> [GlucoseReading] {
        if searchText.isEmpty { return readings }
        
        return readings.filter { reading in
            // Convert reading value to string for search
            let valueString = String(format: "%.1f", reading.displayValue)
            
            // Convert timestamp to searchable format
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let dateString = dateFormatter.string(from: reading.timestamp)
            
            // Search in value, date, or trend description
            return valueString.localizedCaseInsensitiveContains(searchText) ||
                   dateString.localizedCaseInsensitiveContains(searchText) ||
                   reading.trend.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func filteredByRange(_ readings: [GlucoseReading]) -> [GlucoseReading] {
        guard let rangeFilter = filterRange else { return readings }
        
        return readings.filter { $0.rangeStatus == rangeFilter }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerControls
            
            if filteredReadings.isEmpty {
                emptyStateView
            } else {
                historyContent
            }
            
            // No test data button - using only real API data
        }
        .padding()
        .navigationTitle("Glucose History")
        .navigationSubtitle("\(filteredReadings.count) readings")
    }
    
    private var headerControls: some View {
        VStack(spacing: 8) {
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search readings", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(8)
                .background(Material.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Spacer()
                
                // Timeline filter
                Picker("Time Range", selection: $selectedTimeFrame) {
                    ForEach(TimeFrame.allCases) { timeFrame in
                        Text(timeFrame.rawValue).tag(timeFrame)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedTimeFrame) { _ in
                    // Force UI update when filter changes
                    // This ensures the filter is immediately applied
                    print("Time filter changed to: \(selectedTimeFrame.rawValue)")
                }
                
                // Range filter button
                Menu {
                    Button("All Ranges") {
                        filterRange = nil
                    }
                    .disabled(filterRange == nil)
                    
                    Divider()
                    
                    Button {
                        filterRange = .inRange
                    } label: {
                        HStack {
                            Text("In Range")
                            if filterRange == .inRange {
                                Image(systemName: "checkmark")
                            }
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                        }
                    }
                    
                    Button {
                        filterRange = .high
                    } label: {
                        HStack {
                            Text("High")
                            if filterRange == .high {
                                Image(systemName: "checkmark")
                            }
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                        }
                    }
                    
                    Button {
                        filterRange = .low
                    } label: {
                        HStack {
                            Text("Low")
                            if filterRange == .low {
                                Image(systemName: "checkmark")
                            }
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 10, height: 10)
                        }
                    }
                } label: {
                    Label(
                        filterRange == nil ? "Filter" : "Filtered",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .foregroundColor(filterRange == nil ? .primary : .blue)
                }
                .menuStyle(.borderlessButton)
            }
            
            // Filter indicators
            if filterRange != nil {
                HStack {
                    Text("Filters:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let range = filterRange {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(range.color)
                                .frame(width: 8, height: 8)
                            
                            Text(range == .inRange ? "In Range" : (range == .high ? "High" : "Low"))
                            
                            Button {
                                filterRange = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(range.color.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    private var historyContent: some View {
        VStack(spacing: 0) {
            // Statistics view
            if filteredReadings.count > 1 {
                statisticsView
                    .padding(.bottom, 16)
            }
            
            // Table - Using pre-sorted filteredReadings
            Table(filteredReadings) {
                TableColumn("Time") { reading in
                    Text(formatDate(reading.timestamp))
                        .font(.subheadline)
                }
                .width(min: 150, ideal: 150)
                
                TableColumn("Value") { reading in
                    HStack {
                        Text(String(format: "%.1f", reading.displayValue))
                            .foregroundColor(reading.rangeStatus.color)
                            .fontWeight(.semibold)
                        
                        Text(reading.displayUnit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 100, ideal: 120)
                
                TableColumn("Status") { reading in
                    HStack {
                        Circle()
                            .fill(reading.rangeStatus.color)
                            .frame(width: 8, height: 8)
                        
                        Text(statusText(for: reading.rangeStatus))
                            .font(.subheadline)
                    }
                }
                .width(min: 80, ideal: 100)
                
                TableColumn("Trend") { reading in
                    HStack(spacing: 4) {
                        Image(systemName: reading.trend.icon)
                        Text(reading.trend.description)
                            .font(.subheadline)
                    }
                }
                .width(min: 100, ideal: 120)
            }
            .tableStyle(.bordered)
            .scrollContentBackground(.hidden)
            .background(Material.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var statisticsView: some View {
        HStack(spacing: 16) {
            StatSquare(title: "Average", value: calculateAverage(), icon: "number", color: .blue)
            StatSquare(title: "Highest", value: calculateHighest(), icon: "arrow.up", color: .red)
            StatSquare(title: "Lowest", value: calculateLowest(), icon: "arrow.down", color: .yellow)
            StatSquare(title: "In Range", value: calculateInRangePercentage(), icon: "checkmark.circle", color: .green)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Readings Found")
                .font(.headline)
            
            Text("Try changing your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Clear Filters") {
                searchText = ""
                filterRange = nil
                selectedTimeFrame = .all
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func statusText(for status: GlucoseReading.RangeStatus) -> String {
        switch status {
        case .inRange: return "In Range"
        case .high: return "High"
        case .low: return "Low"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func calculateAverage() -> String {
        let values = filteredReadings.map { $0.displayValue }
        let average = values.reduce(0, +) / Double(values.count)
        return String(format: "%.1f %@", average, filteredReadings.first?.displayUnit ?? "")
    }
    
    private func calculateHighest() -> String {
        let highest = filteredReadings.map { $0.displayValue }.max() ?? 0
        return String(format: "%.1f %@", highest, filteredReadings.first?.displayUnit ?? "")
    }
    
    private func calculateLowest() -> String {
        let lowest = filteredReadings.map { $0.displayValue }.min() ?? 0
        return String(format: "%.1f %@", lowest, filteredReadings.first?.displayUnit ?? "")
    }
    
    private func calculateInRangePercentage() -> String {
        let inRange = filteredReadings.filter { $0.isInRange }.count
        let percentage = Double(inRange) / Double(filteredReadings.count) * 100
        return String(format: "%.1f%%", percentage)
    }
}

struct StatSquare: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Material.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
}