import SwiftUI
import Charts

struct EnhancedGlucoseChartView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let readings: [GlucoseReading]
    
    @State private var chartType: ChartType = .line
    @State private var showComparison: Bool = false
    @State private var selectedDate: Date? = nil
    @State private var showAverage: Bool = false
    @State private var isHovering: Bool = false
    @State private var selectedReading: GlucoseReading? = nil
    
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
    
    // Break up the body into smaller components
    var body: some View {
        VStack(spacing: 12) {
            controlsRow
            chartContent
            selectedReadingView
            legendView
        }
    }
    
    // Break out controls into a separate view
    private var controlsRow: some View {
        HStack {
            // Comparison controls
            if showComparison {
                dateSelectionMenu
                
                Toggle("Average", isOn: $showAverage)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .disabled(readings.count < 10) // Need enough data for meaningful average
            }
            
            Spacer()
            
            controlsGroup
        }
        .padding(.horizontal, 6)
    }
    
    private var dateSelectionMenu: some View {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Material.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(availableDays.isEmpty)
    }
    
    private var controlsGroup: some View {
        HStack(spacing: 12) {
            // Comparison toggle
            Toggle("Compare", isOn: $showComparison)
                .toggleStyle(.button)
                .controlSize(.small)
            
            Divider()
                .frame(height: 20)
            
            // Chart type
            Picker("", selection: $chartType) {
                Image(systemName: "waveform.path.ecg")
                    .tag(ChartType.line)
                Image(systemName: "chart.bar.fill")
                    .tag(ChartType.bar)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(6)
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // The chart content as a separate view
    private var chartContent: some View {
        ZStack(alignment: .topLeading) {
            // Background with threshold zones
            ChartBackgroundView(lowThreshold: displayThresholds.low, highThreshold: displayThresholds.high)
            
            glucoseChart
        }
    }
    
    // Break the chart into its own view property
    private var glucoseChart: some View {
        Chart {
            // Target range rectangle
            RectangleMark(
                xStart: .value("Start", readings.first?.timestamp ?? Date()),
                xEnd: .value("End", readings.last?.timestamp ?? Date()),
                yStart: .value("Low", displayThresholds.low),
                yEnd: .value("High", displayThresholds.high)
            )
            .foregroundStyle(Color.green.opacity(0.1))
            
            // Main data
            ForEach(readings) { reading in
                if chartType == .line {
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
                    .symbolSize(30)
                } else {
                    BarMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", reading.displayValue)
                    )
                    .foregroundStyle(reading.rangeStatus.color.gradient)
                    .cornerRadius(4)
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
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 2]))
                    .symbol {
                        Circle()
                            .fill(.blue.opacity(0.7))
                            .frame(width: 6, height: 6)
                    }
                    .symbolSize(30)
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
                    .symbol {
                        Circle()
                            .fill(.purple.opacity(0.7))
                            .frame(width: 6, height: 6)
                    }
                    .symbolSize(30)
                }
                .accessibilityLabel("Average glucose curve")
            }
            
            // Threshold lines
            RuleMark(y: .value("Low Threshold", displayThresholds.low))
                .foregroundStyle(.yellow.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            
            RuleMark(y: .value("High Threshold", displayThresholds.high))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            
            if let selectedReading = selectedReading {
                RuleMark(x: .value("Selected Time", selectedReading.timestamp))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(range: .plotDimension(padding: 40))
        .chartYScale(domain: 3...27)
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
        .chartForegroundStyleScale([
            "Glucose": Color.primary,
            "Comparison": Color.blue,
            "Average": Color.purple
        ])
        .chartOverlay { proxy in
            chartOverlayContent(proxy: proxy)
        }
    }
    
    // Chart overlay for interaction
    private func chartOverlayContent(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragGesture(value: value, geometry: geometry, proxy: proxy)
                        }
                )
        }
    }
    
    // Extract drag gesture handling to separate method
    private func handleDragGesture(value: DragGesture.Value, geometry: GeometryProxy, proxy: ChartProxy) {
        let x = value.location.x
        guard x >= 0, x <= geometry.size.width else { return }
        
        // Calculate relativeXPosition in the plot
        let relativeXPosition = x / geometry.size.width
        
        // Find closest reading based on timestamp
        // First convert screen position to chart scale
        let dateStart = readings.first?.timestamp ?? Date()
        let dateEnd = readings.last?.timestamp ?? Date()
        let range = dateEnd.timeIntervalSince(dateStart)
        
        // Estimate the date at the x position
        let approximateDate = Date(timeInterval: range * Double(relativeXPosition), since: dateStart)
        
        // Find the closest reading by date
        selectedReading = readings.min { reading1, reading2 in
            abs(reading1.timestamp.timeIntervalSince(approximateDate)) < 
            abs(reading2.timestamp.timeIntervalSince(approximateDate))
        }
    }
    
    // Selected reading tooltip view
    @ViewBuilder
    private var selectedReadingView: some View {
        if let reading = selectedReading, isHovering {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDateTime(reading.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        Text(String(format: "%.1f %@", reading.displayValue, reading.displayUnit))
                            .font(.headline)
                        
                        HStack(spacing: 4) {
                            Image(systemName: reading.trend.icon)
                            Text(reading.trend.description)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Material.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .transition(.opacity)
        }
    }
    
    // Legend view
    @ViewBuilder
    private var legendView: some View {
        if showComparison && (selectedDate != nil || showAverage) {
            HStack(spacing: 16) {
                Spacer()
                
                LegendItem(color: .primary, label: "Today")
                
                if let selectedDate = selectedDate {
                    LegendItem(color: .blue, label: formatDay(selectedDate))
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
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

// Background view showing threshold zones
struct ChartBackgroundView: View {
    let lowThreshold: Double
    let highThreshold: Double
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Low zone (below lowThreshold)
                Rectangle()
                    .fill(Color.yellow.opacity(0.08))
                    .frame(height: calculateZoneHeight(for: lowThreshold, in: geo))
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: lowThreshold / 2, in: geo))
                
                // Normal zone (between lowThreshold and highThreshold)
                Rectangle()
                    .fill(Color.green.opacity(0.08))
                    .frame(height: calculateZoneHeight(for: highThreshold - lowThreshold, in: geo))
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: (lowThreshold + highThreshold) / 2, in: geo))
                
                // High zone (above highThreshold)
                Rectangle()
                    .fill(Color.red.opacity(0.08))
                    .frame(height: calculateZoneHeight(for: 27 - highThreshold, in: geo))
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: (highThreshold + 27) / 2, in: geo))
            }
        }
    }
    
    private func calculateZoneHeight(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        // Scale from the chart's 3-27 range (24 units of range)
        return CGFloat(value) * geometry.size.height / 24.0
    }
    
    private func calculateZonePosition(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        // Calculate position based on value in the 3-27 range
        // Invert Y axis since SwiftUI's Y increases downward
        return geometry.size.height - (CGFloat(value - 3) * geometry.size.height / 24.0)
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
                .frame(width: 8, height: 8)
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