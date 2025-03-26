import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            if !appState.glucoseHistory.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        GlucoseChartView(readings: appState.glucoseHistory)
                            .frame(minHeight: 300)
                            .padding()
                        
                        StatisticsView(readings: appState.glucoseHistory)
                            .padding(.horizontal)
                        
                        ReadingsListView(readings: appState.glucoseHistory)
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
                    
                    Text("No glucose readings available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
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
    
    var displayReadings: [GlucoseReading] {
        // Simply return the readings in chronological order (most recent first)
        return readings.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    var body: some View {
        List(displayReadings) { reading in
            ReadingRow(reading: reading)
        }
        .frame(minHeight: 200)
        .listStyle(.plain)
    }
}

struct ReadingRow: View {
    let reading: GlucoseReading
    
    var body: some View {
        HStack {
            Text("\(reading.value, specifier: "%.1f") \(reading.unit)")
                .foregroundColor(colorForReading(reading))
                .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            // Show full date and time for all readings
            Text(formatDateTime(reading.timestamp))
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d, h:mm a"
        return dateFormatter.string(from: date)
    }
    
    private func colorForReading(_ reading: GlucoseReading) -> Color {
        let value = reading.value
        if value < 70 || value > 180 {
            return .red
        } else if value < 100 || value > 140 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
} 