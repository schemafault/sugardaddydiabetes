import SwiftUI
import Charts

struct EnhancedGlucoseChartView: View {
    @EnvironmentObject private var appState: AppState
    let readings: [GlucoseReading]
    
    @State private var chartType: ChartType = .line
    @State private var showComparison: Bool = false
    @State private var selectedDate: Date? = nil
    @State private var showAverage: Bool = false
    
    enum ChartType {
        case line
        case bar
    }
    
    // Helper properties to simplify threshold calculations
    private var currentUnit: String {
        UserDefaults.standard.string(forKey: "unit") ?? "mg/dL"
    }
    
    private var thresholds: (low: Double, high: Double) {
        // Parse thresholds from UserDefaults
        let lowThresholdString = UserDefaults.standard.string(forKey: "lowThreshold") ?? 
                                (currentUnit == "mmol" ? "4.0" : "70")
        let highThresholdString = UserDefaults.standard.string(forKey: "highThreshold") ?? 
                                 (currentUnit == "mmol" ? "10.0" : "180")
        
        let lowThreshold = Double(lowThresholdString) ?? (currentUnit == "mmol" ? 4.0 : 70.0)
        let highThreshold = Double(highThresholdString) ?? (currentUnit == "mmol" ? 10.0 : 180.0)
        
        return (low: lowThreshold, high: highThreshold)
    }
    
    private var displayThresholds: (low: Double, high: Double) {
        // Convert to mmol/L for display
        let isMMOL = currentUnit == "mmol"
        let displayLow = isMMOL ? thresholds.low : thresholds.low / 18.0182
        let displayHigh = isMMOL ? thresholds.high : thresholds.high / 18.0182
        
        return (low: displayLow, high: displayHigh)
    }
    
    // Unique days available in the data
    private var availableDays: [Date] {
        let calendar = Calendar.current
        return Array(Set(readings.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
    }
    
    // Readings for the selected comparison day
    private var comparisonReadings: [GlucoseReading] {
        guard let selectedDate = selectedDate else { return [] }
        
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        
        return readings.filter {
            calendar.isDate(calendar.startOfDay(for: $0.timestamp), inSameDayAs: selectedDay)
        }.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    // Get normalized time for comparison purposes
    private func normalizeTimeOfDay(_ reading: GlucoseReading) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: reading.timestamp)
        
        // Create today with the same time components
        let today = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: components.hour ?? 0,
                             minute: components.minute ?? 0,
                             second: components.second ?? 0,
                             of: today) ?? today
    }
    
    // Calculate average glucose readings
    private var averageReadings: [AverageGlucosePoint] {
        // Group all readings by hour and minute (15 minute intervals)
        let calendar = Calendar.current
        var timeSlots: [String: [Double]] = [:]
        
        for reading in readings {
            let hour = calendar.component(.hour, from: reading.timestamp)
            let minute = calendar.component(.minute, from: reading.timestamp)
            // Group into 15-minute buckets
            let bucket = minute / 15
            let key = "\(hour):\(bucket)"
            
            if timeSlots[key] == nil {
                timeSlots[key] = []
            }
            timeSlots[key]?.append(reading.displayValue)
        }
        
        // Create average data points
        var averagePoints: [AverageGlucosePoint] = []
        
        for (key, values) in timeSlots {
            if values.isEmpty { continue }
            
            let components = key.split(separator: ":")
            if components.count != 2 { continue }
            
            guard let hour = Int(components[0]),
                  let bucket = Int(components[1]) else { continue }
            
            let minute = bucket * 15
            let today = calendar.startOfDay(for: Date())
            if let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) {
                let avgValue = values.reduce(0.0, +) / Double(values.count)
                averagePoints.append(AverageGlucosePoint(time: time, value: avgValue))
            }
        }
        
        return averagePoints.sorted(by: { $0.time < $1.time })
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Comparison controls
                if showComparison {
                    Menu {
                        ForEach(availableDays, id: \.self) { day in
                            Button(action: {
                                selectedDate = day
                            }) {
                                HStack {
                                    Text(formatDay(day))
                                    if let selected = selectedDate, calendar.isDate(day, inSameDayAs: selected) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Button("Clear", role: .destructive) {
                            selectedDate = nil
                        }
                    } label: {
                        Label(selectedDate == nil ? "Select Day" : formatDay(selectedDate!), 
                              systemImage: "calendar")
                    }
                    .disabled(availableDays.isEmpty)
                    
                    Toggle("Avg", isOn: $showAverage)
                        .toggleStyle(.button)
                        .disabled(readings.count < 10) // Need enough data for meaningful average
                }
                
                Spacer()
                
                // Comparison toggle
                Toggle("Compare", isOn: $showComparison)
                    .toggleStyle(.button)
                    .padding(.horizontal, 4)
                
                // Chart type
                Picker("", selection: $chartType) {
                    Image(systemName: "waveform.path")
                        .imageScale(.medium)
                        .tag(ChartType.line)
                    Image(systemName: "chart.bar.fill")
                        .imageScale(.medium)
                        .tag(ChartType.bar)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            .padding(.horizontal)
            
            Chart {
                // Main data
                ForEach(readings) { reading in
                    if chartType == .line {
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Glucose", reading.displayValue)
                        )
                        .foregroundStyle(reading.rangeStatus.color)
                    } else {
                        BarMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Glucose", reading.displayValue)
                        )
                        .foregroundStyle(reading.rangeStatus.color)
                    }
                }
                
                // Comparison data (if enabled)
                if showComparison && selectedDate != nil && !comparisonReadings.isEmpty {
                    ForEach(comparisonReadings) { reading in
                        LineMark(
                            x: .value("Time", normalizeTimeOfDay(reading)),
                            y: .value("Comparison", reading.displayValue)
                        )
                        .foregroundStyle(.blue.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .accessibilityLabel("Comparison data")
                }
                
                // Average data (if enabled)
                if showComparison && showAverage {
                    ForEach(averageReadings) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Average", point.value)
                        )
                        .foregroundStyle(.purple.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .accessibilityLabel("Average glucose curve")
                }
                
                // Threshold lines
                RuleMark(y: .value("Low Threshold", displayThresholds.low))
                    .foregroundStyle(.yellow.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                
                RuleMark(y: .value("High Threshold", displayThresholds.high))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .chartXScale(range: .plotDimension(padding: 40))
            .chartYScale(domain: 3...27)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatTime(date))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [3, 6, 9, 12, 15, 18, 21, 24, 27]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let reading = value.as(Double.self) {
                            Text(String(format: "%.0f", reading))
                        }
                    }
                }
            }
            .chartForegroundStyleScale([
                "Glucose": Color.primary,
                "Comparison": Color.blue,
                "Average": Color.purple
            ])
            .frame(height: 300)
            
            // Legend when comparison is enabled
            if showComparison && (selectedDate != nil || showAverage) {
                HStack(spacing: 16) {
                    LegendItem(color: .primary, label: "Today")
                    
                    if selectedDate != nil {
                        LegendItem(color: .blue, label: "Comparison: \(formatDay(selectedDate!))")
                    }
                    
                    if showAverage {
                        LegendItem(color: .purple, label: "Average")
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: date)
    }
    
    private var calendar: Calendar {
        return Calendar.current
    }
}

// Model for average glucose points
struct AverageGlucosePoint: Identifiable {
    var id = UUID()
    var time: Date
    var value: Double
}

// Simple legend item for the chart
struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    EnhancedGlucoseChartView(readings: [])
        .environmentObject(AppState())
} 