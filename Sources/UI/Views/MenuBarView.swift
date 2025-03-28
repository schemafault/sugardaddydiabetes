import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with current reading
            if let reading = appState.currentGlucoseReading {
                currentReadingHeader(reading)
            } else {
                noDataHeader()
            }
            
            Divider()
                .padding(.vertical, 1)
            
            // Menu items
            menuItems
            
            Divider()
                .padding(.vertical, 1)
            
            // Footer
            footerView
        }
        .frame(width: 280)
        .background(menuBackground)
    }
    
    private var menuBackground: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.15, blue: 0.18),
                        Color(red: 0.12, green: 0.12, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.99),
                        Color(red: 0.95, green: 0.96, blue: 0.98)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
    
    private func currentReadingHeader(_ reading: GlucoseReading) -> some View {
        VStack(spacing: 8) {
            Text("Current Glucose")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.top, 12)
            
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f", reading.displayValue))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(reading.rangeStatus.color)
                        .contentTransition(.numericText())
                        .shadow(color: reading.rangeStatus.color.opacity(0.4), radius: 1)
                    
                    Text(reading.displayUnit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Image(systemName: reading.trend.icon)
                            .symbolEffect(.pulse, options: .repeating, value: reading.isInRange ? false : true)
                            .foregroundColor(reading.rangeStatus.color)
                        Text(reading.trend.description)
                    }
                    .foregroundColor(reading.rangeStatus.color)
                    .font(.system(size: 15, weight: .medium))
                    
                    Text(formatTime(reading.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            reading.rangeStatus.color.opacity(0.07)
        )
    }
    
    private func noDataHeader() -> some View {
        VStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .symbolEffect(.pulse)
            
            Text("No Data Available")
                .font(.headline)
            
            Text("Tap Refresh to update")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
    }
    
    private var menuItems: some View {
        VStack(spacing: 0) {
            MenuRowButton(title: "Open Dashboard", icon: "gauge") {
                NSApp.activate(ignoringOtherApps: true)
                appState.selectedTab = 0
                
                DispatchQueue.main.async {
                    // First try to find existing window
                    if let existingWindow = findMainAppWindow() {
                        existingWindow.makeKeyAndOrderFront(nil)
                    } else {
                        // Only open a new window if none exists
                        openWindow(id: "main")
                    }
                }
            }
            
            MenuRowButton(title: "View History", icon: "chart.xyaxis.line") {
                NSApp.activate(ignoringOtherApps: true)
                appState.selectedTab = 1
                
                DispatchQueue.main.async {
                    // First try to find existing window
                    if let existingWindow = findMainAppWindow() {
                        existingWindow.makeKeyAndOrderFront(nil)
                    } else {
                        // Only open a new window if none exists
                        openWindow(id: "main")
                    }
                }
            }
            
            MenuRowButton(title: "Refresh Data", icon: "arrow.clockwise") {
                Task {
                    await appState.fetchLatestReadings()
                }
            }
            
            MenuRowButton(title: "Settings", icon: "gear") {
                NSApp.activate(ignoringOtherApps: true)
                appState.selectedTab = 2
                
                DispatchQueue.main.async {
                    // First try to find existing window
                    if let existingWindow = findMainAppWindow() {
                        existingWindow.makeKeyAndOrderFront(nil)
                    } else {
                        // Only open a new window if none exists
                        openWindow(id: "main")
                    }
                }
            }
            
            if appState.isAuthenticated {
                MenuRowButton(title: "Logout", icon: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                    appState.isAuthenticated = false
                }
            }
            
            MenuRowButton(title: "Quit Glucose Monitor", icon: "power", isDestructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private var footerView: some View {
        VStack(spacing: 2) {
            Text("Last Updated: \(formatDateTime(Date()))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text("Glucose Monitor")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Helper function to find the main application window
    private func findMainAppWindow() -> NSWindow? {
        // First, look for a window with "Diabetes Monitor" in the title
        for window in NSApp.windows where window.title.contains("Diabetes Monitor") {
            return window
        }
        
        // If not found, check for windows with "Dashboard" title
        for window in NSApp.windows where window.title.contains("Dashboard") {
            return window
        }
        
        // Last resort: find any window that could be a main app window
        // Filtering out menu extra windows and others that can't be main/key
        for window in NSApp.windows {
            let windowClass = NSStringFromClass(type(of: window))
            
            // Skip status and menu bar windows
            if windowClass.contains("StatusBarWindow") || 
               windowClass.contains("MenuBarExtra") {
                continue
            }
            
            // Check if window can be key or main, has proper style mask
            if window.canBecomeKey || window.canBecomeMain,
               window.styleMask.contains(.titled) {
                return window
            }
        }
        
        return nil
    }
}

struct MenuRowButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(isDestructive ? .red : (isHovering ? .primary : .secondary))
                
                Text(title)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(isDestructive ? .red : .primary)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}