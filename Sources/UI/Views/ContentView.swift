import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedTab) {
                NavigationLink(value: 0) {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                NavigationLink(value: 1) {
                    Label("History", systemImage: "clock.fill")
                }
                NavigationLink(value: 2) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("Diabetes Monitor")
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch appState.selectedTab {
                case 0:
                    DashboardView()
                case 1:
                    HistoryView()
                case 2:
                    SettingsView()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .alert("Error", isPresented: .constant(appState.error != nil)) {
            Button("OK") {
                appState.error = nil
            }
        } message: {
            if let error = appState.error {
                Text(error.localizedDescription)
            }
        }
        // Since the openWindowParameters isn't working, we'll just use the existing binding
        // The appState.selectedTab will be set directly by the MenuBarView when opening the window
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let reading = appState.currentGlucoseReading {
                    CurrentReadingView(reading: reading)
                }
                
                if !appState.glucoseHistory.isEmpty {
                    EnhancedGlucoseChartView(readings: appState.glucoseHistory)
                        .frame(minHeight: 300)
                        .padding()
                }
                
                StatisticsView(readings: appState.glucoseHistory)
                    .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
    }
}

struct CurrentReadingView: View {
    let reading: GlucoseReading
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Current Reading")
                .font(.headline)
            
            HStack(alignment: .center, spacing: 20) {
                VStack {
                    Text(String(format: "%.1f", reading.displayValue))
                        .font(.system(size: 48, weight: .bold))
                    Text(reading.displayUnit)
                        .font(.subheadline)
                }
                
                Image(systemName: reading.trend.icon)
                    .font(.system(size: 32))
                    .foregroundColor(reading.rangeStatus.color)
            }
            
            Text(reading.trend.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(radius: 2)
    }
}

struct GlucoseChartView: View {
    let readings: [GlucoseReading]
    @State private var chartType: ChartType = .line
    
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
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
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
                .padding(.horizontal)
            }
            
            Chart(readings) { reading in
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
                    
                    RuleMark(
                        x: .value("Time", reading.timestamp),
                        yStart: .value("Start", reading.displayValue),
                        yEnd: .value("End", reading.displayValue)
                    )
                    .annotation(position: .top) {
                        Text(String(format: "%.1f", reading.displayValue))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .background(.background.opacity(0.8))
                    }
                }
            }
            .chartXScale(range: .plotDimension(padding: 40))
            .chartYScale(domain: 3...27)
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
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatDate(date))
                    }
                }
            }
            .overlay {
                ChartOverlayView(displayLow: displayThresholds.low, displayHigh: displayThresholds.high)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// Break out overlay into its own structure to simplify the main view
struct ChartOverlayView: View {
    let displayLow: Double
    let displayHigh: Double
    
    var body: some View {
        GeometryReader { geometry in
            // Print for debugging
            let _ = print("Chart thresholds - low: \(displayLow), high: \(displayHigh) mmol/L")
            
            // Calculate scale (accounting for the 3-27 range = 24 units of range)
            let yScale = geometry.size.height / 24
            
            // Target range rectangle
            targetRangeRectangle(geometry: geometry, yScale: yScale)
            
            // Low threshold line
            thresholdLine(geometry: geometry, threshold: displayLow, yScale: yScale, color: .yellow)
            
            // High threshold line
            thresholdLine(geometry: geometry, threshold: displayHigh, yScale: yScale, color: .red)
        }
    }
    
    // Helper views to break down the complex calculations
    private func targetRangeRectangle(geometry: GeometryProxy, yScale: CGFloat) -> some View {
        let height = (displayHigh - displayLow) * yScale
        let yPosition = geometry.size.height - ((displayHigh + displayLow) / 2 - 3) * yScale
        
        return Rectangle()
            .fill(Color.green.opacity(0.1))
            .frame(width: geometry.size.width, height: height)
            .position(x: geometry.size.width / 2, y: yPosition)
    }
    
    private func thresholdLine(geometry: GeometryProxy, threshold: Double, yScale: CGFloat, color: Color) -> some View {
        let yPosition = geometry.size.height - ((threshold - 3) * yScale)
        
        return Path { path in
            path.move(to: CGPoint(x: 0, y: yPosition))
            path.addLine(to: CGPoint(x: geometry.size.width, y: yPosition))
        }
        .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
    }
}

struct StatisticsView: View {
    let readings: [GlucoseReading]
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            StatCard(title: "Average", value: calculateAverage())
            StatCard(title: "Time in Range", value: calculateTimeInRange())
            StatCard(title: "Readings", value: "\(readings.count)")
        }
    }
    
    private func calculateAverage() -> String {
        let values = readings.map { $0.displayValue }
        let average = values.reduce(0, +) / Double(values.count)
        return String(format: "%.1f", average)
    }
    
    private func calculateTimeInRange() -> String {
        let inRange = readings.filter { $0.isInRange }.count
        let percentage = Double(inRange) / Double(readings.count) * 100
        return String(format: "%.1f%%", percentage)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(radius: 2)
    }
}

#Preview {
    ContentView(selectedTab: .constant(0))
        .environmentObject(AppState())
} 