import SwiftUI

struct MonitoringSettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    @AppStorage("unit") private var unit: String = "mg/dL"
    @AppStorage("lowThreshold") private var lowThreshold: String = "70"
    @AppStorage("highThreshold") private var highThreshold: String = "180"
    @AppStorage("updateInterval") private var updateInterval: Int = 15
    
    let availableIntervals = [5, 10, 15, 30, 60]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                unitsSection
                thresholdsSection
                updateIntervalSection
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 600, alignment: .center)
        }
    }
    
    private var unitsSection: some View {
        SettingsSection(title: "Glucose Units", icon: "gauge") {
            Picker("Glucose Units", selection: $unit) {
                Text("mg/dL").tag("mg/dL")
                Text("mmol/L").tag("mmol")
            }
            .pickerStyle(.segmented)
            .onChange(of: unit) { oldValue, newValue in
                updateThresholdValues()
            }
        }
    }
    
    private var thresholdsSection: some View {
        SettingsSection(title: "Glucose Thresholds", icon: "arrow.up.arrow.down") {
            VStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Low Threshold")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        TextField("", text: $lowThreshold)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        
                        Text(unit == "mmol" ? "mmol/L" : "mg/dL")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Slider(value: lowThresholdDouble, in: sliderRange.0...sliderRange.1, step: sliderStep)
                        .tint(.yellow)
                        .padding(.horizontal)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("High Threshold")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        TextField("", text: $highThreshold)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        
                        Text(unit == "mmol" ? "mmol/L" : "mg/dL")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Slider(value: highThresholdDouble, in: sliderRange.0...sliderRange.1, step: sliderStep)
                        .tint(.red)
                        .padding(.horizontal)
                }
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var updateIntervalSection: some View {
        SettingsSection(title: "Update Interval", icon: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Check for new readings every:")
                    .font(.subheadline)
                
                Picker("Update Interval", selection: $updateInterval) {
                    ForEach(availableIntervals, id: \.self) { interval in
                        Text("\(interval) minutes").tag(interval)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // Helper properties and methods
    private var sliderRange: (Double, Double) {
        if unit == "mmol" {
            return (3.0, 20.0)
        } else {
            return (54.0, 360.0)
        }
    }
    
    private var sliderStep: Double {
        return unit == "mmol" ? 0.1 : 1.0
    }
    
    private var lowThresholdDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(lowThreshold) ?? (unit == "mmol" ? 4.0 : 70.0) },
            set: { lowThreshold = String(format: unit == "mmol" ? "%.1f" : "%.0f", $0) }
        )
    }
    
    private var highThresholdDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(highThreshold) ?? (unit == "mmol" ? 10.0 : 180.0) },
            set: { highThreshold = String(format: unit == "mmol" ? "%.1f" : "%.0f", $0) }
        )
    }
    
    private func updateThresholdValues() {
        if unit == "mmol" {
            // Convert from mg/dL to mmol/L
            if let lowValue = Double(lowThreshold), lowValue > 30 {
                lowThreshold = String(format: "%.1f", lowValue / 18.0182)
            }
            if let highValue = Double(highThreshold), highValue > 30 {
                highThreshold = String(format: "%.1f", highValue / 18.0182)
            }
        } else {
            // Convert from mmol/L to mg/dL
            if let lowValue = Double(lowThreshold), lowValue < 30 {
                lowThreshold = String(format: "%.0f", lowValue * 18.0182)
            }
            if let highValue = Double(highThreshold), highValue < 30 {
                highThreshold = String(format: "%.0f", highValue * 18.0182)
            }
        }
    }
}

#Preview {
    MonitoringSettingsView()
        .environmentObject(AppState())
}