import SwiftUI
import Charts

struct AGPView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var timeRange: TimeRange = .twoWeeks
    @State private var showAnnotations: Bool = true
    @State private var showLegend: Bool = true
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case oneWeek = "1 Week"
        case twoWeeks = "2 Weeks"
        case oneMonth = "1 Month"
        
        var id: String { self.rawValue }
        
        var days: Int {
            switch self {
            case .oneWeek: return 7
            case .twoWeeks: return 14
            case .oneMonth: return 30
            }
        }
    }
    
    // Data for the AGP chart
    private var agpData: AGPChartData {
        calculateAGPData(from: filteredReadings)
    }
    
    // Filter readings based on selected time range
    private var filteredReadings: [GlucoseReading] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -timeRange.days, to: today) else {
            return appState.glucoseHistory
        }
        
        return appState.glucoseHistory.filter { $0.timestamp >= startDate }
    }
    
    // Time in range metrics
    private var timeInRange: (inRange: Double, high: Double, low: Double) {
        let totalCount = Double(filteredReadings.count)
        guard totalCount > 0 else { return (0, 0, 0) }
        
        let inRange = Double(filteredReadings.filter { $0.isInRange }.count) / totalCount * 100
        let high = Double(filteredReadings.filter { $0.rangeStatus == .high }.count) / totalCount * 100
        let low = Double(filteredReadings.filter { $0.rangeStatus == .low }.count) / totalCount * 100
        
        return (inRange, high, low)
    }
    
    // Average glucose value
    private var averageGlucose: Double {
        let values = filteredReadings.map { $0.displayValue }
        return values.reduce(0, +) / Double(max(values.count, 1))
    }
    
    // Estimated A1C (approximation based on average glucose)
    private var estimatedA1C: Double {
        let avgMgdl = appState.currentUnit == "mmol" ? averageGlucose * 18.0182 : averageGlucose
        return (avgMgdl + 46.7) / 28.7
    }
    
    // Glucose Management Indicator (another estimation based on average glucose)
    private var gmi: Double {
        let avgMgdl = appState.currentUnit == "mmol" ? averageGlucose * 18.0182 : averageGlucose
        return 3.31 + (0.02392 * avgMgdl)
    }
    
    // Glucose variability (standard deviation divided by mean)
    private var glucoseVariability: Double {
        let values = filteredReadings.map { $0.displayValue }
        guard !values.isEmpty else { return 0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let sumOfSquaredDifferences = values.reduce(0) { $0 + pow($1 - mean, 2) }
        let standardDeviation = sqrt(sumOfSquaredDifferences / Double(values.count))
        
        return (standardDeviation / mean) * 100
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Controls section
                controlsSection
                
                // Primary AGP Chart
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ambulatory Glucose Profile")
                        .font(.headline)
                    
                    Text("Daily glucose patterns aggregated over \(timeRange.days) days")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    agpChartView
                        .frame(height: 300)
                        .padding(.horizontal, 16) // Add more horizontal padding
                }
                .padding()
                .background(Material.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Metrics section
                metricsSection
                
                // Explanation section
                if showAnnotations {
                    explanationSection
                }
            }
            .padding()
        }
        .navigationTitle("AGP Analysis")
        .navigationSubtitle("Based on \(filteredReadings.count) readings over \(timeRange.days) days")
    }
    
    // Controls for the AGP view
    private var controlsSection: some View {
        HStack {
            Picker("Time Range", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            
            Spacer()
            
            Toggle("Annotations", isOn: $showAnnotations)
                .toggleStyle(.button)
                .controlSize(.small)
            
            Toggle("Legend", isOn: $showLegend)
                .toggleStyle(.button)
                .controlSize(.small)
        }
    }
    
    // The main AGP chart
    private var agpChartView: some View {
        ZStack(alignment: .topLeading) {
            // Chart with percentile bands
            Chart {
                // Target range rectangle
                RectangleMark(
                    xStart: .value("Start", normalizeTimeOfDay(Date(), hour: 0, minute: 0)),
                    xEnd: .value("End", normalizeTimeOfDay(Date(), hour: 23, minute: 59)),
                    yStart: .value("Low", getThreshold("lowThreshold")),
                    yEnd: .value("High", getThreshold("highThreshold"))
                )
                .foregroundStyle(Color.green.opacity(0.1))
                
                // 10th to 90th percentile band (widest)
                if !agpData.timePoints.isEmpty {
                    ForEach(agpData.timePoints) { point in
                        AreaMark(
                            x: .value("Time", point.time),
                            yStart: .value("10th", point.p10),
                            yEnd: .value("90th", point.p90)
                        )
                        .foregroundStyle(Color.blue.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                }
                
                // 25th to 75th percentile band (middle)
                if !agpData.timePoints.isEmpty {
                    ForEach(agpData.timePoints) { point in
                        AreaMark(
                            x: .value("Time", point.time),
                            yStart: .value("25th", point.p25),
                            yEnd: .value("75th", point.p75)
                        )
                        .foregroundStyle(Color.blue.opacity(0.2))
                        .interpolationMethod(.catmullRom)
                    }
                }
                
                // Median line (50th percentile)
                if !agpData.timePoints.isEmpty {
                    ForEach(agpData.timePoints) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Median", point.median)
                        )
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)
                    }
                }
                
                // Threshold lines
                RuleMark(y: .value("Low Threshold", getThreshold("lowThreshold")))
                    .foregroundStyle(.yellow.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .leading) {
                        if showAnnotations {
                            Text("Low")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .padding(.leading, 4)
                        }
                    }
                
                RuleMark(y: .value("High Threshold", getThreshold("highThreshold")))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .leading) {
                        if showAnnotations {
                            Text("High")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 4)
                        }
                    }
            }
            .chartXScale(domain: normalizeTimeOfDay(Date(), hour: 0, minute: 0)...normalizeTimeOfDay(Date(), hour: 23, minute: 59))
            .chartYScale(domain: 3...27)
            // Add explicit plot area insets to make room for the left labels
            .chartPlotStyle { content in
                content
                    .padding(.leading, 40) // Important: This creates space for the annotations
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary)
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatTime(date))
                            .font(.caption)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [3, 6, 9, 12, 15, 18, 21, 24, 27]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary)
                    AxisValueLabel {
                        if let reading = value.as(Double.self) {
                            Text(String(format: "%.0f", reading))
                                .font(.caption)
                        }
                    }
                }
            }
            
            // Legend overlay if enabled
            if showLegend {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Percentiles")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 8) {
                        legendItem(color: .blue, text: "Median")
                        legendItem(color: .blue.opacity(0.2), text: "25-75th")
                        legendItem(color: .blue.opacity(0.1), text: "10-90th")
                    }
                }
                .padding(8)
                .background(Material.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
        }
    }
    
    // Metrics cards showing key statistics
    private var metricsSection: some View {
        VStack(spacing: 16) {
            Text("Glucose Metrics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                metricCard(
                    title: "Average Glucose",
                    value: String(format: "%.1f %@", averageGlucose, appState.currentUnit),
                    description: "Mean of all readings",
                    icon: "number"
                )
                
                metricCard(
                    title: "GMI",
                    value: String(format: "%.1f%%", gmi),
                    description: "Glucose Management Indicator",
                    icon: "percent"
                )
                
                metricCard(
                    title: "Glucose Variability",
                    value: String(format: "%.1f%%", glucoseVariability),
                    description: "CV% (< 36% is stable)",
                    icon: "waveform.path"
                )
                
                metricCard(
                    title: "Time in Range",
                    value: String(format: "%.1f%%", timeInRange.inRange),
                    description: "Target: > 70%",
                    icon: "checkmark.circle"
                )
                
                metricCard(
                    title: "Time Above Range",
                    value: String(format: "%.1f%%", timeInRange.high),
                    description: "Target: < 25%",
                    icon: "arrow.up.circle"
                )
                
                metricCard(
                    title: "Time Below Range",
                    value: String(format: "%.1f%%", timeInRange.low),
                    description: "Target: < 5%",
                    icon: "arrow.down.circle"
                )
            }
        }
        .padding()
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // Explanatory section about how to interpret the AGP
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Understanding the AGP")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                explanationItem(
                    title: "Median (50th percentile)",
                    description: "The middle line shows the typical glucose level throughout the day."
                )
                
                explanationItem(
                    title: "Inter-quartile range (25th-75th percentile)",
                    description: "The middle band shows the range where glucose is 50% of the time. Narrow bands indicate more consistent glucose levels."
                )
                
                explanationItem(
                    title: "10th-90th percentile",
                    description: "The outer band shows the range where glucose is 80% of the time. Wide bands indicate more glucose variability."
                )
                
                explanationItem(
                    title: "Glucose Variability",
                    description: "CV% below 36% indicates stable glucose. Higher values suggest more glucose fluctuations."
                )
            }
        }
        .padding()
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // Helper function to create consistent legend items
    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 4)
            
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // Helper function to create consistent metric cards
    private func metricCard(title: String, value: String, description: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(.primary)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    // Helper function to create explanation items
    private func explanationItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // Function to calculate AGP data from readings
    private func calculateAGPData(from readings: [GlucoseReading]) -> AGPChartData {
        // Create time slots for every 15 minutes throughout the day
        let slots = 24 * 4 // 15-minute intervals across 24 hours
        var timePoints: [AGPTimePoint] = []
        
        // For each time slot, gather all readings that fall into that slot
        for slotIndex in 0..<slots {
            let hour = slotIndex / 4
            let minute = (slotIndex % 4) * 15
            
            // All readings that match this time slot across different days
            let slotReadings = getReadingsForTimeSlot(hour: hour, minute: minute, readings: readings)
            
            if !slotReadings.isEmpty {
                // Calculate percentiles for this time slot
                let values = slotReadings.map { $0.displayValue }.sorted()
                let median = calculatePercentile(values: values, percentile: 50)
                let p25 = calculatePercentile(values: values, percentile: 25)
                let p75 = calculatePercentile(values: values, percentile: 75)
                let p10 = calculatePercentile(values: values, percentile: 10)
                let p90 = calculatePercentile(values: values, percentile: 90)
                
                // Create a time point for this slot
                let timePoint = AGPTimePoint(
                    time: normalizeTimeOfDay(Date(), hour: hour, minute: minute),
                    median: median,
                    p25: p25,
                    p75: p75,
                    p10: p10,
                    p90: p90
                )
                
                timePoints.append(timePoint)
            }
        }
        
        return AGPChartData(timePoints: timePoints)
    }
    
    // Get all readings that match a specific time slot
    private func getReadingsForTimeSlot(hour: Int, minute: Int, readings: [GlucoseReading]) -> [GlucoseReading] {
        let calendar = Calendar.current
        
        return readings.filter { reading in
            let readingHour = calendar.component(.hour, from: reading.timestamp)
            let readingMinute = calendar.component(.minute, from: reading.timestamp)
            
            // Check if this reading falls within the 15-minute window
            if readingHour == hour {
                let minuteStart = minute
                let minuteEnd = minute + 14
                return readingMinute >= minuteStart && readingMinute <= minuteEnd
            }
            
            return false
        }
    }
    
    // Calculate a specific percentile from an array of values
    private func calculatePercentile(values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        
        if values.count == 1 {
            return values[0]
        }
        
        let index = (percentile / 100.0) * Double(values.count - 1)
        if index.truncatingRemainder(dividingBy: 1) == 0 {
            return values[Int(index)]
        } else {
            let lower = Int(floor(index))
            let upper = Int(ceil(index))
            let weight = index - Double(lower)
            return values[lower] * (1 - weight) + values[upper] * weight
        }
    }
    
    // Helper to normalize a time to today for consistent charting
    private func normalizeTimeOfDay(_ date: Date, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
    }
    
    // Format time for display
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

// Data structures for the AGP chart
struct AGPTimePoint: Identifiable {
    var id = UUID()
    let time: Date
    let median: Double   // 50th percentile
    let p25: Double      // 25th percentile
    let p75: Double      // 75th percentile
    let p10: Double      // 10th percentile
    let p90: Double      // 90th percentile
}

struct AGPChartData {
    let timePoints: [AGPTimePoint]
}

#Preview {
    AGPView()
        .environmentObject(AppState())
}