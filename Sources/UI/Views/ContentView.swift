import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
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
                switch selectedTab {
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
                    GlucoseChartView(readings: appState.glucoseHistory)
                        .frame(minHeight: 300)
                        .padding()
                }
                
                StatisticsView(readings: appState.glucoseHistory)
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
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let reading = value.as(Double.self) {
                            Text(String(format: "%.1f", reading))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel(formatDate(date))
                    }
                }
            }
            .overlay {
                GeometryReader { geometry in
                    let lowThreshold = Double(UserDefaults.standard.string(forKey: "lowThreshold") ?? "70") ?? 70
                    let highThreshold = Double(UserDefaults.standard.string(forKey: "highThreshold") ?? "180") ?? 180
                    
                    // Convert to display units if needed
                    let displayLow = UserDefaults.standard.string(forKey: "unit") == "mmol" ? lowThreshold / 18.0182 : lowThreshold
                    let displayHigh = UserDefaults.standard.string(forKey: "unit") == "mmol" ? highThreshold / 18.0182 : highThreshold
                    
                    let maxValue = readings.map { $0.displayValue }.max() ?? 1
                    let yScale = geometry.size.height / maxValue
                    
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.size.height - (displayLow * yScale)))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - (displayLow * yScale)))
                    }
                    .stroke(Color.yellow.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.size.height - (displayHigh * yScale)))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - (displayHigh * yScale)))
                    }
                    .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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