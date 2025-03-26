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
            
            VStack(spacing: 0) {
                MenuRowButton(title: "Open Dashboard", icon: "square.grid.2x2") {
                    NSApp.activate(ignoringOtherApps: true)
                    
                    // Set the tab first, then open the window
                    appState.selectedTab = 0
                    
                    DispatchQueue.main.async {
                        // Open main window
                        openWindow(id: "main")
                    }
                }
                
                MenuRowButton(title: "Refresh Data", icon: "arrow.clockwise") {
                    Task {
                        await appState.fetchLatestReadings()
                    }
                }
                
                MenuRowButton(title: "Settings", icon: "gear") {
                    NSApp.activate(ignoringOtherApps: true)
                    
                    // Set the tab first, then open the window
                    appState.selectedTab = 2
                    
                    DispatchQueue.main.async {
                        // Open main window
                        openWindow(id: "main")
                    }
                }
                
                if appState.isAuthenticated {
                    MenuRowButton(title: "Logout", icon: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                        appState.isAuthenticated = false
                    }
                }
                
                MenuRowButton(title: "Quit App", icon: "xmark.circle", isDestructive: true) {
                    NSApplication.shared.terminate(nil)
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

struct MenuRowButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .fontWeight(.regular)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(isDestructive ? .red : .primary)
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    var isDestructive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isDestructive ? .red : .primary)
            .background(
                configuration.isPressed ? 
                    Color(.selectedControlColor) : 
                    Color.clear
            )
            .cornerRadius(4)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
} 