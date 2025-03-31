import SwiftUI
import Charts

struct TimeInRangeCalendarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var showingDayDetail: Bool = false
    
    private let calendar = Calendar.current
    private let daysInWeek = 7
    private let weeksToDisplay = 6 // Fixed 6 week grid for consistent calendar layout
    
    // Computed property for days in the selected month
    private var daysInMonth: [Date?] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
        let daysInMonth = calendar.dateComponents([.day], from: monthEnd).day! + 1
        
        // Determine the first weekday of the month (0 = Sunday, 1 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        // Adjust to get the weekday index (0-based, where 0 is Sunday)
        let firstWeekdayIndex = (firstWeekday + 6) % 7
        
        var days = [Date?]()
        
        // Add nil for days before the start of the month
        for _ in 0..<firstWeekdayIndex {
            days.append(nil)
        }
        
        // Add the days of the month
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        
        // Fill the remaining grid with nil
        while days.count < daysInWeek * weeksToDisplay {
            days.append(nil)
        }
        
        return days
    }
    
    // Get time-in-range data for a specific date
    private func timeInRangeForDate(_ date: Date) -> (inRange: Double, high: Double, low: Double)? {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let dayReadings = appState.glucoseHistory.filter { 
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay 
        }
        
        if dayReadings.isEmpty {
            return nil // No data for this day
        }
        
        let totalCount = Double(dayReadings.count)
        let inRange = Double(dayReadings.filter { $0.isInRange }.count) / totalCount * 100
        let high = Double(dayReadings.filter { $0.rangeStatus == .high }.count) / totalCount * 100
        let low = Double(dayReadings.filter { $0.rangeStatus == .low }.count) / totalCount * 100
        
        return (inRange, high, low)
    }
    
    // Get average glucose for a specific date
    private func averageGlucoseForDate(_ date: Date) -> Double? {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let dayReadings = appState.glucoseHistory.filter { 
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay 
        }
        
        if dayReadings.isEmpty {
            return nil // No data for this day
        }
        
        let sum = dayReadings.reduce(0.0) { $0 + $1.displayValue }
        return sum / Double(dayReadings.count)
    }
    
    // Get the most appropriate color for a day based on time-in-range data
    private func colorForDate(_ date: Date) -> Color {
        guard let timeInRange = timeInRangeForDate(date) else {
            return colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)
        }
        
        // High percentage dominates (red), then low (yellow), then in-range (green)
        if timeInRange.high > 30 {
            return Color.red.opacity(min(0.9, timeInRange.high / 100))
        } else if timeInRange.low > 15 {
            return Color.yellow.opacity(min(0.9, timeInRange.low / 100))
        } else {
            return Color.green.opacity(min(0.9, timeInRange.inRange / 100))
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Calendar controls
                calendarHeader
                
                // Weekday headers
                weekdayHeaderRow
                
                // Calendar grid
                calendarGrid
                
                // Legend
                calendarLegend
                
                // Selected day detail - wrapped in fixed height container to prevent UI shifting
                VStack {
                    if let selectedDate = selectedDate {
                        selectedDayDetailView(date: selectedDate)
                            .padding()
                            .background(Material.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        // Empty spacer when no date is selected to maintain consistent height
                        Color.clear
                    }
                }
                .frame(height: 120)
                .padding(.top, 8)
                
                Spacer(minLength: 40) // Extra space at the bottom
            }
        }
        .padding()
        .navigationTitle("Time in Range Calendar")
        .navigationSubtitle("Visualize glucose patterns by day")
        .sheet(isPresented: $showingDayDetail) {
            if let date = selectedDate {
                DayDetailView(date: date)
                    .environmentObject(appState)
            }
        }
    }
    
    // Calendar header with month controls
    private var calendarHeader: some View {
        HStack {
            Button(action: {
                selectedDate = nil
                if let newMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
                    selectedMonth = newMonth
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formatMonth(selectedMonth))
                .font(.title2)
                .bold()
            
            Spacer()
            
            Button(action: {
                selectedDate = nil
                if let newMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
                    selectedMonth = newMonth
                }
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
    
    // Weekday header row
    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(getWeekdaySymbols(), id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // Calendar grid
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: daysInWeek), spacing: 4) {
            ForEach(0..<daysInMonth.count, id: \.self) { index in
                if let date = daysInMonth[index] {
                    calendarDayCell(date: date)
                } else {
                    // Empty cell for days outside current month
                    Rectangle()
                        .fill(Color.clear)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
    
    // Individual day cell in the calendar
    private func calendarDayCell(date: Date) -> some View {
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)
        let dayNumber = calendar.component(.day, from: date)
        let hasData = timeInRangeForDate(date) != nil
        
        return Button(action: {
            // On click, select the date
            selectedDate = date
            
            // For cells with data, make it possible to double-click
            // by adding a Detail button in the day detail view
            if hasData {
                // Add a small delay to allow for a potential second click
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // If the date is still selected, show the detail view
                    if selectedDate == date {
                        showingDayDetail = true
                    }
                }
            }
        }) {
            // Cell content
            ZStack {
                Rectangle()
                    .fill(colorForDate(date))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : (isToday ? Color.secondary : Color.clear), lineWidth: isSelected ? 2 : 1)
                    )
                
                VStack {
                    Text("\(dayNumber)")
                        .font(.system(size: 12, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .primary : .secondary)
                    
                    if let avg = averageGlucoseForDate(date) {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if hasData {
                Button("View Details") {
                    selectedDate = date
                    showingDayDetail = true
                }
            }
        }
        .opacity(hasData ? 1.0 : 0.8)
    }
    
    // Calendar legend
    private var calendarLegend: some View {
        VStack(spacing: 8) {
            // Color legend
            HStack(spacing: 16) {
                legendItem(color: .green.opacity(0.6), label: "In Range")
                legendItem(color: .yellow.opacity(0.6), label: "Low")
                legendItem(color: .red.opacity(0.6), label: "High")
                legendItem(color: .gray.opacity(0.2), label: "No Data")
                
                Spacer()
            }
            
            // Interaction hints
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Tap to select a day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("Click or right-click for details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "hand.tap.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    // Helper to create legend items
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 16, height: 16)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // Selected day detail view
    private func selectedDayDetailView(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(formatDate(date))
                    .font(.headline)
                
                Spacer()
                
                Button("View Details") {
                    showingDayDetail = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if let timeInRange = timeInRangeForDate(date) {
                HStack(spacing: 20) {
                    timeInRangeBar(inRange: timeInRange.inRange, high: timeInRange.high, low: timeInRange.low)
                        .frame(height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let avgGlucose = averageGlucoseForDate(date) {
                            HStack(spacing: 4) {
                                Text("Average:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(String(format: "%.1f %@", avgGlucose, appState.currentUnit))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Text("In Range: \(Int(timeInRange.inRange))%")
                                .foregroundColor(.green)
                            
                            Text("High: \(Int(timeInRange.high))%")
                                .foregroundColor(.red)
                            
                            Text("Low: \(Int(timeInRange.low))%")
                                .foregroundColor(.yellow)
                        }
                        .font(.caption)
                    }
                }
            } else {
                Text("No glucose data available for this day")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // Time in range visualization bar
    private func timeInRangeBar(inRange: Double, high: Double, low: Double) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: max(0, geometry.size.width * inRange / 100))
                
                Rectangle()
                    .fill(Color.red)
                    .frame(width: max(0, geometry.size.width * high / 100))
                
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: max(0, geometry.size.width * low / 100))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    
    // Helper to get weekday symbols
    private func getWeekdaySymbols() -> [String] {
        return Calendar.current.shortWeekdaySymbols
    }
    
    // Helper to format month
    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    // Helper to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

// Detailed view for a specific day
struct DayDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    private let calendar = Calendar.current
    
    // Initialize with state for caching metrics to improve performance
    @State private var cachedReadings: [GlucoseReading] = []
    @State private var cachedTimeInRange: (inRange: Double, high: Double, low: Double) = (0, 0, 0)
    @State private var cachedAverage: Double = 0.0
    @State private var cachedVariability: String = "N/A"
    @State private var metricsCalculated = false
    
    // Get readings for the selected day - only calculated once
    private var dayReadings: [GlucoseReading] {
        if !cachedReadings.isEmpty {
            return cachedReadings
        }
        
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let readings = appState.glucoseHistory
            .filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
            .sorted { $0.timestamp < $1.timestamp }
        
        // This isn't truly reactive, but for this view we only need to calculate once
        // at initialization since the data won't change during the popover's lifetime
        DispatchQueue.main.async {
            self.cachedReadings = readings
            self.calculateMetrics()
        }
        
        return readings
    }
    
    // Calculate all metrics at once to avoid redundant calculations
    private func calculateMetrics() {
        // Calculate time-in-range metrics
        let totalCount = Double(cachedReadings.count)
        if totalCount > 0 {
            let inRange = Double(cachedReadings.filter { $0.isInRange }.count) / totalCount * 100
            let high = Double(cachedReadings.filter { $0.rangeStatus == .high }.count) / totalCount * 100
            let low = Double(cachedReadings.filter { $0.rangeStatus == .low }.count) / totalCount * 100
            cachedTimeInRange = (inRange, high, low)
            
            // Calculate average
            let sum = cachedReadings.reduce(0.0) { $0 + $1.displayValue }
            cachedAverage = sum / totalCount
            
            // Calculate variability (only if we have enough readings)
            if cachedReadings.count > 2 {
                let values = cachedReadings.map { $0.displayValue }
                let mean = values.reduce(0, +) / Double(values.count)
                let sumOfSquaredDifferences = values.reduce(0) { $0 + pow($1 - mean, 2) }
                let standardDeviation = sqrt(sumOfSquaredDifferences / Double(values.count))
                let coefficientOfVariation = (standardDeviation / mean) * 100
                cachedVariability = String(format: "%.1f%%", coefficientOfVariation)
            }
        }
        
        metricsCalculated = true
    }
    
    // Use cached metrics for performance
    private var timeInRange: (inRange: Double, high: Double, low: Double) {
        if !metricsCalculated && !dayReadings.isEmpty {
            calculateMetrics()
        }
        return cachedTimeInRange
    }
    
    // Use cached average for performance
    private var averageGlucose: Double {
        if !metricsCalculated && !dayReadings.isEmpty {
            calculateMetrics()
        }
        return cachedAverage
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if dayReadings.isEmpty {
                    // No data view
                    VStack(spacing: 20) {
                        Spacer(minLength: 60)
                        
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                            .padding()
                        
                        Text("No Readings Available")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("There is no glucose data available for \(formatDate(date))")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Data available view - Optimized to remove the performance-heavy readings list
                    VStack(spacing: 20) {
                        // Day summary
                        daySummaryView
                        
                        // Chart of readings for the day
                        dayChartView
                        
                        // Note about number of readings instead of full list
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.headline)
                            
                            HStack {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.secondary)
                                Text("\(dayReadings.count) readings recorded on this day")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Material.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding()
                }
            }
            .navigationTitle(formatDate(date))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // Day summary metrics
    private var daySummaryView: some View {
        VStack(spacing: 16) {
            // Time-in-range bar
            timeInRangeBar
            
            // Metrics grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                metricValue(title: "Readings", value: "\(dayReadings.count)", icon: "list.bullet")
                
                metricValue(
                    title: "Average",
                    value: String(format: "%.1f %@", averageGlucose, appState.currentUnit),
                    icon: "number"
                )
                
                if let minReading = dayReadings.min(by: { $0.displayValue < $1.displayValue }) {
                    metricValue(
                        title: "Lowest",
                        value: String(format: "%.1f", minReading.displayValue),
                        icon: "arrow.down",
                        color: .yellow
                    )
                }
                
                if let maxReading = dayReadings.max(by: { $0.displayValue < $1.displayValue }) {
                    metricValue(
                        title: "Highest",
                        value: String(format: "%.1f", maxReading.displayValue),
                        icon: "arrow.up",
                        color: .red
                    )
                }
                
                metricValue(
                    title: "In Range",
                    value: String(format: "%.1f%%", timeInRange.inRange),
                    icon: "checkmark.circle",
                    color: .green
                )
                
                metricValue(
                    title: "Variability",
                    value: calculateVariability(),
                    icon: "waveform.path",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // Time in range bar visualization
    private var timeInRangeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time in Range")
                .font(.headline)
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: max(0, geometry.size.width * timeInRange.inRange / 100))
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: max(0, geometry.size.width * timeInRange.high / 100))
                    
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: max(0, geometry.size.width * timeInRange.low / 100))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .frame(height: 24)
            
            HStack {
                Text("In Range: \(Int(timeInRange.inRange))%")
                    .foregroundColor(.green)
                Spacer()
                Text("High: \(Int(timeInRange.high))%")
                    .foregroundColor(.red)
                Spacer()
                Text("Low: \(Int(timeInRange.low))%")
                    .foregroundColor(.yellow)
            }
            .font(.caption)
        }
    }
    
    // Chart view showing glucose throughout the day - optimized with drawingGroup
    private var dayChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glucose Readings")
                .font(.headline)
            
            // Simple line chart showing the day's glucose values
            Chart {
                ForEach(dayReadings) { reading in
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", reading.displayValue)
                    )
                    .foregroundStyle(reading.rangeStatus.color.gradient)
                    .symbol {
                        Circle()
                            .fill(reading.rangeStatus.color)
                            .frame(width: 8, height: 8)
                    }
                    .interpolationMethod(.catmullRom)
                }
                
                // Add threshold lines
                let lowThreshold = getThreshold("lowThreshold")
                let highThreshold = getThreshold("highThreshold")
                
                RuleMark(y: .value("Low", lowThreshold))
                    .foregroundStyle(.yellow.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                
                RuleMark(y: .value("High", highThreshold))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .frame(height: 200)
            .chartYScale(domain: 3...27)
            // Use drawingGroup for Metal-accelerated rendering
            .drawingGroup()
        }
        .padding()
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // List of all readings for the day
    private var readingsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Readings")
                .font(.headline)
                .padding(.horizontal)
            
            if dayReadings.isEmpty {
                Text("No readings available for this day")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(dayReadings) { reading in
                        readingRow(reading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        
                        if reading.id != dayReadings.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .background(Material.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    // Individual reading row
    private func readingRow(_ reading: GlucoseReading) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTime(reading.timestamp))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(String(format: "%.1f %@", reading.displayValue, reading.displayUnit))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(reading.rangeStatus.color)
            
            HStack(spacing: 8) {
                Image(systemName: reading.trend.icon)
                    .foregroundColor(reading.rangeStatus.color)
                
                Circle()
                    .fill(reading.rangeStatus.color)
                    .frame(width: 10, height: 10)
            }
        }
    }
    
    // Helper to create consistent metric cards
    private func metricValue(title: String, value: String, icon: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // Helper to get cached glucose variability
    private func calculateVariability() -> String {
        if !metricsCalculated && !dayReadings.isEmpty {
            calculateMetrics()
        }
        return cachedVariability
    }
    
    // Helper to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
    
    // Helper to format time
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    // Get threshold values from UserDefaults
    private func getThreshold(_ key: String) -> Double {
        let defaultValue = key == "lowThreshold" ? 
            (appState.currentUnit == "mmol" ? 4.0 : 70.0) :
            (appState.currentUnit == "mmol" ? 10.0 : 180.0)
        
        if let thresholdString = UserDefaults.standard.string(forKey: key) {
            return Double(thresholdString) ?? defaultValue
        }
        return defaultValue
    }
}

#Preview {
    TimeInRangeCalendarView()
        .environmentObject(AppState())
}