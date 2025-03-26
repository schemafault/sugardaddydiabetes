import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 12) {
            if let reading = appState.currentGlucoseReading {
                VStack(spacing: 8) {
                    Text("Current Reading")
                        .font(.headline)
                    
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(format: "%.1f", reading.value))
                            .font(.system(size: 32, weight: .bold))
                        Text(UserDefaults.standard.string(forKey: "unit") == "mmol" ? "mmol/L" : "mg/dL")
                            .font(.subheadline)
                    }
                    
                    HStack {
                        Image(systemName: reading.trend.icon)
                        Text(reading.trend.description)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top)
            } else {
                Text("No Data")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Button("Open Dashboard") {
                openWindow(id: "main")
            }
            
            Button("Refresh Data") {
                Task {
                    await appState.fetchLatestReadings()
                }
            }
            
            Button("Settings") {
                openWindow(id: "main", value: 2)
            }
            
            if appState.isAuthenticated {
                Button("Logout", role: .destructive) {
                    appState.isAuthenticated = false
                }
            }
            
            Divider()
            
            Text("Last Updated: \(formatDate(Date()))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .frame(width: 250)
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
} 