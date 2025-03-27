import SwiftUI
import Charts

struct ComparativeDailyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDates: Set<Date> = []
    @State private var isEnabled: Bool = true // Default to enabled for better initial UX
    
    private var allDays: [Date] {
        // Get all available unique days from history
        let calendar = Calendar.current
        let days = appState.glucoseHistory
            .map { calendar.startOfDay(for: $0.timestamp) }
            .reduce(into: Set<Date>()) { $0.insert($1) }
            .sorted(by: >)
        
        // Pre-select the two most recent days if no selection exists
        if selectedDates.isEmpty && days.count >= 2 {
            DispatchQueue.main.async {
                selectedDates.insert(days[0])
                if days.count > 1 {
                    selectedDates.insert(days[1])
                }
            }
        }
        
        return days
    }
    
    private var dailyReadings: [Date: [GlucoseReading]] {
        // Group readings by day
        let calendar = Calendar.current
        
        return allDays.reduce(into: [Date: [GlucoseReading]]()) { dict, day in
            dict[day] = appState.glucoseHistory.filter {
                calendar.isDate(calendar.startOfDay(for: $0.timestamp), inSameDayAs: day)
            }.sorted(by: { $0.timestamp < $1.timestamp })
        }
    }
    
    private func normalizeTimeOfDay(_ reading: GlucoseReading) -> Date {
        // Normalize timestamp to time of day for overlay comparison
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: reading.timestamp)
        
        // Create a reference date (today) with the same time
        return calendar.date(bySettingHour: components.hour ?? 0,
                             minute: components.minute ?? 0,
                             second: components.second ?? 0,
                             of: Date()) ?? Date()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Comparative Daily Analysis")
                    .font(.headline)
                
                Spacer()
                
                // Simplified toggle to hide/show selections
                Button {
                    isEnabled.toggle()
                } label: {
                    Label(isEnabled ? "Hide Controls" : "Show Controls", 
                          systemImage: isEnabled ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            
            if !dailyReadings.isEmpty {
                VStack(spacing: 12) {
                    // Day selection section if controls are enabled
                    if isEnabled {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(allDays.prefix(7), id: \.self) { day in
                                    DaySelectionButton(
                                        day: day,
                                        isSelected: selectedDates.contains(day),
                                        action: {
                                            toggleDaySelection(day)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // The chart showing multiple days
                    Chart {
                        // Day lines
                        ForEach(Array(selectedDates), id: \.self) { day in
                            if let readings = dailyReadings[day], !readings.isEmpty {
                                ForEach(readings) { reading in
                                    LineMark(
                                        x: .value("Time", normalizeTimeOfDay(reading)),
                                        y: .value("Glucose", reading.displayValue)
                                    )
                                    .foregroundStyle(by: .value("Day", formatDayLabel(day)))
                                }
                            }
                        }
                        
                        // Add threshold lines
                        let lowThreshold = getThreshold("lowThreshold")
                        let highThreshold = getThreshold("highThreshold")
                        
                        RuleMark(y: .value("Low", lowThreshold))
                            .foregroundStyle(.yellow.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .leading) {
                                Text("Low")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        
                        RuleMark(y: .value("High", highThreshold))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .leading) {
                                Text("High")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                            if let date = value.as(Date.self) {
                                let hour = Calendar.current.component(.hour, from: date)
                                AxisValueLabel {
                                    Text("\(hour):00")
                                }
                            }
                        }
                    }
                    .chartYScale(domain: getYAxisRange())
                    .frame(height: 250)
                    .padding()
                }
            } else {
                Text("Insufficient data to compare days")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
    
    private func toggleDaySelection(_ day: Date) {
        if selectedDates.contains(day) {
            selectedDates.remove(day)
        } else {
            selectedDates.insert(day)
            
            // Limit to maximum 5 days for better readability
            if selectedDates.count > 5 {
                selectedDates.remove(selectedDates.sorted().first!)
            }
        }
    }
    
    private func formatDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: date)
    }
    
    private func getThreshold(_ key: String) -> Double {
        let defaultValue = key == "lowThreshold" ? 
            (UserDefaults.standard.string(forKey: "unit") == "mmol" ? 4.0 : 70.0) :
            (UserDefaults.standard.string(forKey: "unit") == "mmol" ? 10.0 : 180.0)
        
        if let thresholdString = UserDefaults.standard.string(forKey: key) {
            return Double(thresholdString) ?? defaultValue
        }
        return defaultValue
    }
    
    private func getYAxisRange() -> ClosedRange<Double> {
        // Calculate appropriate y-axis range
        if selectedDates.isEmpty {
            return 3...27
        }
        
        let values = selectedDates.flatMap { day in
            dailyReadings[day]?.map { $0.displayValue } ?? []
        }
        
        if values.isEmpty {
            return 3...27
        }
        
        let min = values.min() ?? 3.0
        let max = values.max() ?? 27.0
        
        // Add padding
        let padding = (max - min) * 0.2
        return (min - padding)...(max + padding)
    }
}

struct DaySelectionButton: View {
    let day: Date
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Text(dayOfWeek)
                    .fontWeight(isSelected ? .bold : .regular)
                Text(dayOfMonth)
                    .font(.caption)
            }
            .frame(width: 60, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: day)
    }
    
    private var dayOfMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day)
    }
}

#Preview {
    ComparativeDailyView()
        .environmentObject(AppState())
}