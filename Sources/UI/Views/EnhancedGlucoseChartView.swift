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
    @State private var showInsulinShots: Bool = true
    @State private var hoveredInsulinShot: InsulinShot? = nil
    
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
        // Get unique days, sort by most recent first
        let days = Array(Set(readings.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
        
        // For better performance, limit to most recent 30 days
        return days.count > 30 ? Array(days.prefix(30)) : days
    }
    
    // Helper method to determine timespan of readings in seconds
    private func getReadingsTimespan() -> TimeInterval {
        guard let oldestReading = readings.min(by: { $0.timestamp < $1.timestamp }),
              let newestReading = readings.max(by: { $0.timestamp < $1.timestamp }) else {
            return 0
        }
        
        return newestReading.timestamp.timeIntervalSince(oldestReading.timestamp)
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
    
    // Get insulin shots for the time range covered by the readings
    private var insulinShotsInRange: [InsulinShot] {
        guard !readings.isEmpty else { return [] }
        
        let oldestReading = readings.min { $0.timestamp < $1.timestamp }
        let newestReading = readings.max { $0.timestamp < $1.timestamp }
        
        guard let start = oldestReading?.timestamp,
              let end = newestReading?.timestamp else {
            return []
        }
        
        // Add a small buffer on both sides for better visualization
        let startWithBuffer = start.addingTimeInterval(-60 * 60) // 1 hour before
        let endWithBuffer = end.addingTimeInterval(60 * 60) // 1 hour after
        
        return appState.getInsulinShots(fromDate: startWithBuffer, toDate: endWithBuffer)
    }
    
    // Break up the body into smaller components
    var body: some View {
        VStack(spacing: 12) {
            controlsRow
            
            // Quick stats of displayed data
            if !readings.isEmpty {
                HStack(spacing: 16) {
                    StatChip(
                        label: "Average",
                        value: String(format: "%.1f", calculateAverage()),
                        color: .blue,
                        icon: "number.circle.fill"
                    )
                    
                    StatChip(
                        label: "Time in Range",
                        value: String(format: "%.0f%%", calculateTimeInRange()),
                        color: .green,
                        icon: "checkmark.circle.fill"
                    )
                    
                    StatChip(
                        label: "Readings",
                        value: "\(readings.count)",
                        color: .purple,
                        icon: "waveform.path.ecg.rectangle.fill"
                    )
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
            }
            
            chartContent
                .animation(.easeInOut(duration: 0.3), value: chartType)
            selectedReadingView
            legendView
        }
    }
    
    // Helper methods to calculate statistics
    private func calculateAverage() -> Double {
        guard !readings.isEmpty else { return 0 }
        return readings.map { $0.displayValue }.reduce(0, +) / Double(readings.count)
    }
    
    private func calculateTimeInRange() -> Double {
        guard !readings.isEmpty else { return 0 }
        let inRangeCount = readings.filter { $0.isInRange }.count
        return Double(inRangeCount) / Double(readings.count) * 100
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
            
            if readings.count > 0 {
                Toggle(isOn: $showInsulinShots) {
                    Image(systemName: "syringe")
                }
                .toggleStyle(.button)
                .help("Show/hide insulin shots")
            }
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
            
            // Main chart
            mainChart
        }
    }
    
    // Break the chart into its own view property
    private var mainChart: some View {
        Chart {
            // Target range rectangle
            if !readings.isEmpty {
                RectangleMark(
                    xStart: .value("Start", readings.first?.timestamp ?? Date()),
                    xEnd: .value("End", readings.last?.timestamp ?? Date()),
                    yStart: .value("Low", displayThresholds.low),
                    yEnd: .value("High", displayThresholds.high)
                )
                .foregroundStyle(Color.green.opacity(0.1))
            }
            
            // Main data using line or bar charts
            if chartType == .line {
                // Line chart with enhanced styling
                ForEach(readings) { reading in
                    // Line connecting points
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", reading.displayValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                reading.rangeStatus.color.opacity(0.7),
                                reading.rangeStatus.color
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                    
                    // Points on the line
                    PointMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", reading.displayValue)
                    )
                    .foregroundStyle(Color.white)
                    .symbolSize(28)
                    .annotation(position: .overlay) {
                        Circle()
                            .fill(reading.rangeStatus.color)
                            .frame(width: 8, height: 8)
                            .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                    }
                }
                
                // Add insulin shot indicators
                if showInsulinShots {
                    ForEach(insulinShotsInRange) { shot in
                        RuleMark(
                            x: .value("Insulin Shot", shot.timestamp)
                        )
                        .foregroundStyle(insulinShotColor(opacity: shot.id == hoveredInsulinShot?.id ? 0.7 : 0.4))
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                        .annotation(position: .top) {
                            if shot.id == hoveredInsulinShot?.id {
                                VStack(alignment: .center, spacing: 4) {
                                    Text("Insulin Shot")
                                        .font(.caption2)
                                        .bold()
                                    
                                    Text(formatTime(shot.timestamp))
                                        .font(.caption2)
                                    
                                    if let dosage = shot.dosage {
                                        Text("\(String(format: "%.1f", dosage)) units")
                                            .font(.caption2)
                                    }
                                }
                                .padding(6)
                                .background(Material.regularMaterial)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            } else {
                // Bar chart with proper baseline and value labels
                let shouldShowAllLabels = readings.count < 15 // Only show all labels if we have fewer than 15 readings
                
                ForEach(readings.enumerated().map { ($0, $1) }, id: \.1.id) { index, reading in
                    BarMark(
                        x: .value("Time", reading.timestamp),
                        yStart: .value("Baseline", 3), // Start from minimum of y-axis
                        yEnd: .value("Glucose", reading.displayValue),
                        width: .fixed(4) // Fixed width to prevent overlapping bars
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                reading.rangeStatus.color.opacity(0.8),
                                reading.rangeStatus.color
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center, spacing: 0) {
                        // Show label if we have few readings OR it's an important reading
                        // (every 3rd reading, or high/low values)
                        if shouldShowAllLabels || 
                           index % 3 == 0 || 
                           reading.isHigh || 
                           reading.isLow {
                            // Show a value label above each bar
                            Text(String(format: "%.1f", reading.displayValue))
                                .font(.system(size: 8.5)) // Slightly bigger font
                                .foregroundColor(.white) // White text for better contrast
                                .fontWeight(.bold)
                                // Use colored background matching the reading status
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(reading.rangeStatus.color.opacity(0.8))
                                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                                )
                        }
                    }
                }
                
                // Add insulin shot indicators
                if showInsulinShots {
                    ForEach(insulinShotsInRange) { shot in
                        RuleMark(
                            x: .value("Insulin Shot", shot.timestamp)
                        )
                        .foregroundStyle(insulinShotColor(opacity: shot.id == hoveredInsulinShot?.id ? 0.7 : 0.4))
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                        .annotation(position: .top) {
                            if shot.id == hoveredInsulinShot?.id {
                                VStack(alignment: .center, spacing: 4) {
                                    Text("Insulin Shot")
                                        .font(.caption2)
                                        .bold()
                                    
                                    Text(formatTime(shot.timestamp))
                                        .font(.caption2)
                                    
                                    if let dosage = shot.dosage {
                                        Text("\(String(format: "%.1f", dosage)) units")
                                            .font(.caption2)
                                    }
                                }
                                .padding(6)
                                .background(Material.regularMaterial)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            
            // Comparison data (if enabled)
            if showComparison && selectedDate != nil && !comparisonReadings.isEmpty {
                ForEach(comparisonReadings, id: \.id) { reading in
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
            }
            
            // Average data (if enabled)
            if showComparison && showAverage {
                ForEach(averageReadings, id: \.id) { point in
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
            }
            
            // Threshold lines
            RuleMark(y: .value("Low Threshold", displayThresholds.low))
                .foregroundStyle(.yellow.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            
            RuleMark(y: .value("High Threshold", displayThresholds.high))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                
            // Highlight significant readings (highest and lowest points)
            if let highestReading = readings.max(by: { $0.displayValue < $1.displayValue }),
               highestReading.isHigh {
                PointMark(
                    x: .value("Time", highestReading.timestamp),
                    y: .value("Glucose", highestReading.displayValue)
                )
                .foregroundStyle(.red)
                .symbolSize(60)
                .annotation(position: .top) {
                    Text(String(format: "Peak: %.1f", highestReading.displayValue))
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            if let lowestReading = readings.min(by: { $0.displayValue < $1.displayValue }),
               lowestReading.isLow {
                PointMark(
                    x: .value("Time", lowestReading.timestamp),
                    y: .value("Glucose", lowestReading.displayValue)
                )
                .foregroundStyle(.yellow)
                .symbolSize(60)
                .annotation(position: .bottom) {
                    Text(String(format: "Low: %.1f", lowestReading.displayValue))
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            if let selectedReading = selectedReading {
                RuleMark(x: .value("Selected Time", selectedReading.timestamp))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(range: .plotDimension(padding: 40))
        .chartYScale(domain: 3...27)
        .chartXAxis {
            // Dynamically adjust x-axis labels based on data timespan
            let readingsTimespan = getReadingsTimespan()
            
            if readingsTimespan <= 24 * 60 * 60 { // Less than 1 day (show hourly marks)
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary)
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatTime(date))
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                }
            } else if readingsTimespan <= 3 * 24 * 60 * 60 { // 1-3 days (show every 6 hours)
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary)
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatDayAndTime(date))
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                }
            } else { // More than 3 days (show daily marks)
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary)
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatDay(date))
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
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
                            .foregroundStyle(Color.primary.opacity(0.8))
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
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Find the x-coordinate in the chart coordinate space
                            let x = value.location.x - geometry.frame(in: .local).origin.x
                            
                            // Find the reading closest to the hover position
                            var closestReading: (reading: GlucoseReading, distance: CGFloat)? = nil
                            
                            for reading in readings {
                                guard let xPosition = proxy.position(forX: reading.timestamp) else { continue }
                                let distance = abs(xPosition - x)
                                
                                if let current = closestReading {
                                    if distance < current.distance {
                                        closestReading = (reading, distance)
                                    }
                                } else {
                                    closestReading = (reading, distance)
                                }
                            }
                            
                            // Only select readings within 20-30 points of the cursor
                            if let closest = closestReading, closest.distance < 30 {
                                selectedReading = closest.reading
                                isHovering = true
                            } else {
                                selectedReading = nil
                                isHovering = false
                            }
                            
                            // Find the insulin shot closest to the hover position
                            if showInsulinShots && !insulinShotsInRange.isEmpty {
                                var closestShot: (shot: InsulinShot, distance: CGFloat)? = nil
                                
                                for shot in insulinShotsInRange {
                                    guard let xPosition = proxy.position(forX: shot.timestamp) else { continue }
                                    let distance = abs(xPosition - x)
                                    
                                    // Consider shots within 20 points of the cursor
                                    if distance < 20 {
                                        if let current = closestShot {
                                            if distance < current.distance {
                                                closestShot = (shot, distance)
                                            }
                                        } else {
                                            closestShot = (shot, distance)
                                        }
                                    }
                                }
                                
                                hoveredInsulinShot = closestShot?.shot
                            }
                        }
                        .onEnded { _ in
                            isHovering = false
                            // Clear the selected reading after a delay to avoid UI flicker
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                selectedReading = nil
                                hoveredInsulinShot = nil
                            }
                        }
                )
        }
    }
    
    // Selected reading tooltip view
    @ViewBuilder
    private var selectedReadingView: some View {
        if let reading = selectedReading, isHovering {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatDateTime(reading.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        Text(String(format: "%.1f %@", reading.displayValue, reading.displayUnit))
                            .font(.headline)
                            .foregroundColor(reading.rangeStatus.color)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 4) {
                            Image(systemName: reading.trend.icon)
                                .foregroundColor(reading.rangeStatus.color)
                            Text(reading.trend.description)
                                .foregroundColor(.primary)
                        }
                        .font(.caption)
                    }
                    
                    // Show range status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(reading.rangeStatus.color)
                            .frame(width: 8, height: 8)
                        
                        Text(reading.isInRange ? "In Range" : (reading.isHigh ? "High" : "Low"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Material.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(reading.rangeStatus.color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.spring(response: 0.2), value: selectedReading?.id)
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
    
    private func formatDayAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
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
    
    // Color for insulin shot indicators
    private func insulinShotColor(opacity: Double = 0.5) -> Color {
        return colorScheme == .dark ? Color.purple.opacity(opacity) : Color.purple.opacity(opacity)
    }
}

// Enhanced background view showing threshold zones
struct ChartBackgroundView: View {
    let lowThreshold: Double
    let highThreshold: Double
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Low zone (below lowThreshold)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.yellow.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                Color.yellow.opacity(colorScheme == .dark ? 0.08 : 0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: calculateZoneHeight(for: lowThreshold - 3, in: geo))
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: (lowThreshold + 3) / 2, in: geo))
                
                // Normal zone (between lowThreshold and highThreshold)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(colorScheme == .dark ? 0.15 : 0.08),
                                Color.green.opacity(colorScheme == .dark ? 0.08 : 0.04)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: calculateZoneHeight(for: highThreshold - lowThreshold, in: geo))
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: (lowThreshold + highThreshold) / 2, in: geo))
                
                // High zone (above highThreshold)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(colorScheme == .dark ? 0.18 : 0.1),
                                Color.red.opacity(colorScheme == .dark ? 0.12 : 0.05)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: calculateZoneHeight(for: 27 - highThreshold, in: geo))
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: (highThreshold + 27) / 2, in: geo))
                
                // Add subtle borders at the thresholds
                Rectangle()
                    .fill(Color.yellow.opacity(0.3))
                    .frame(height: 1)
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: lowThreshold, in: geo))
                
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(height: 1)
                    .position(x: geo.size.width / 2, y: calculateZonePosition(for: highThreshold, in: geo))
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

// Stat chip for showing statistics
struct StatChip: View {
    let label: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 11))
            
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Material.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    EnhancedGlucoseChartView(readings: [])
        .environmentObject(AppState())
}