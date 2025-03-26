import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTimeRange: TimeRange = .day
    
    enum TimeRange: String, CaseIterable {
        case day = "24 Hours"
        case week = "7 Days"
        case month = "30 Days"
        
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }
    
    var filteredReadings: [GlucoseReading] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -selectedTimeRange.days, to: Date()) ?? Date()
        return appState.glucoseHistory.filter { $0.timestamp >= cutoffDate }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            if !filteredReadings.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        GlucoseChartView(readings: filteredReadings)
                            .frame(minHeight: 300)
                            .padding()
                        
                        StatisticsView(readings: filteredReadings)
                            .padding(.horizontal)
                        
                        ReadingsListView(readings: filteredReadings)
                            .frame(minHeight: 200)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Data")
                        .font(.headline)
                    Text("No glucose readings available for the selected time range")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationTitle("History")
    }
}

struct ReadingsListView: View {
    let readings: [GlucoseReading]
    
    var body: some View {
        List(readings) { reading in
            ReadingRow(reading: reading)
        }
        .frame(minHeight: 200)
        .listStyle(.plain)
    }
}

struct ReadingRow: View {
    let reading: GlucoseReading
    
    private var backgroundColor: Color {
        let value = reading.value
        if value < 70 || value > 180 {
            return Color.red.opacity(0.2)
        } else if value < 100 || value > 140 {
            return Color.orange.opacity(0.2)
        } else {
            return Color.green.opacity(0.2)
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(formatDate(reading.timestamp))
                    .font(.headline)
                Text(reading.trend.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(String(format: "%.1f", reading.value))
                    .font(.headline)
                Text(UserDefaults.standard.string(forKey: "unit") == "mmol" ? "mmol/L" : "mg/dL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
} 