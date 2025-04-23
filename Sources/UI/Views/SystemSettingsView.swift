import SwiftUI
import AppKit

struct SystemSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    // App preferences
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("showInDock") private var showInDock = true
    
    // Notification preferences
    @AppStorage("notifyHighGlucose") private var notifyHighGlucose = true
    @AppStorage("notifyLowGlucose") private var notifyLowGlucose = true
    @AppStorage("notifyRapidChange") private var notifyRapidChange = true
    
    // Advanced diagnostics state
    @State private var showAdvancedOptions = false
    @State private var keyMonitor: Any? = nil
    
    // Add state for diagnostic operations
    @State private var isDiagnosingDuplicates = false
    @State private var showDiagnosticResults = false
    
    // Add state for cleanup operations
    @State private var showCleanupConfirmation = false
    @State private var showCleanupResultAlert = false
    @State private var cleanupResultMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appPreferencesSection
                notificationsSection
                
                // Conditionally display advanced options
                if showAdvancedOptions {
                    advancedDiagnosticsSection
                }
                
                // Small visual indicator for advanced options
                HStack {
                    Spacer()
                    Circle()
                        .fill(showAdvancedOptions ? Color.green.opacity(0.5) : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .padding(.trailing, 8)
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 600, alignment: .center)
        }
        .onAppear {
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .alert("Confirm Database Cleanup", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Up Database", role: .destructive) {
                Task {
                    await appState.cleanupDuplicateReadings()
                    
                    // Show results alert when finished
                    await MainActor.run {
                        if let result = appState.lastCleanupResult {
                            switch result {
                            case .success(let uniqueCount, let duplicatesRemoved, let backupPath):
                                cleanupResultMessage = "Successfully removed \(duplicatesRemoved) duplicate readings.\n\nPreserved \(uniqueCount) unique readings.\n\nBackup created: \(backupPath ?? "No backup")"
                            case .failure(let error):
                                cleanupResultMessage = "Cleanup failed: \(error)"
                            }
                            showCleanupResultAlert = true
                        }
                    }
                }
            }
        } message: {
            Text("This will remove duplicate readings from your database while preserving exactly one reading per timestamp. A backup will be created first. Proceed?")
        }
        .alert("Database Cleanup Results", isPresented: $showCleanupResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanupResultMessage)
        }
    }
    
    private var appPreferencesSection: some View {
        SettingsSection(title: "App Preferences", icon: "gearshape") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        // Logic to set app to launch at login would go here
                        // This would typically use SMLoginItemSetEnabled or similar
                        print("Launch at login set to: \(newValue)")
                    }
                
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { oldValue, newValue in
                        // Logic to show/hide menu bar icon would go here
                        print("Show in menu bar set to: \(newValue)")
                    }
                
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { oldValue, newValue in
                        // Logic to show/hide dock icon would go here
                        print("Show in Dock set to: \(newValue)")
                    }
                
                Divider()
                
                Button("Check for Updates") {
                    // Logic to check for app updates would go here
                    print("Checking for updates...")
                }
                .buttonStyle(.borderedProminent)
                
                Text("Version 1.0.4")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var notificationsSection: some View {
        SettingsSection(title: "Notifications", icon: "bell") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Notify on high glucose", isOn: $notifyHighGlucose)
                
                Toggle("Notify on low glucose", isOn: $notifyLowGlucose)
                
                Toggle("Notify on rapid changes", isOn: $notifyRapidChange)
                
                Divider()
                
                Button("Request Notification Permissions") {
                    // Logic to request notification permissions would go here
                    requestNotificationPermissions()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Advanced Diagnostics Section
    
    private var advancedDiagnosticsSection: some View {
        VStack(spacing: 8) {
            Divider().padding(.vertical)
            
            Section(header: Text("Advanced").font(.headline)) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Diagnostics")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        // Diagnostic button
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: {
                                isDiagnosingDuplicates = true
                                appState.diagnoseDuplicateReadings()
                                
                                // Set a timer to show the "completed" message
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    isDiagnosingDuplicates = false
                                    showDiagnosticResults = true
                                    
                                    // Auto-hide results after 5 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                        showDiagnosticResults = false
                                    }
                                }
                            }) {
                                Text("Check Database for Duplicate Readings")
                                    .frame(minWidth: 220)
                            }
                            .disabled(isDiagnosingDuplicates || appState.isDatabaseCleanupRunning)
                            
                            if isDiagnosingDuplicates {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .padding(.trailing, 4)
                                    
                                    Text("Analyzing database...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if showDiagnosticResults {
                                Text("Diagnostics complete! Check console output for results.")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Text("This checks for duplicate readings in the database without modifying any data. Results are displayed in the console logs.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Database cleanup button
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: {
                                showCleanupConfirmation = true
                            }) {
                                Text("Clean Up Duplicate Readings")
                                    .frame(minWidth: 220)
                            }
                            .disabled(isDiagnosingDuplicates || appState.isDatabaseCleanupRunning)
                            
                            if appState.isDatabaseCleanupRunning {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .padding(.trailing, 4)
                                    
                                    Text("Cleaning up database...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let lastResult = appState.lastCleanupResult {
                                switch lastResult {
                                case .success(let uniqueCount, let duplicatesRemoved, _):
                                    Text("Cleanup successful! Kept \(uniqueCount) unique readings, removed \(duplicatesRemoved) duplicates.")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                case .failure(let error):
                                    Text("Cleanup failed: \(error)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Text("This removes duplicate readings from the database while preserving one reading per timestamp. A backup is created first.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Material.regularMaterial)
                .cornerRadius(8)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Key Monitoring
    
    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // First shortcut: Shift+H
            if event.modifierFlags.contains(.shift) && event.charactersIgnoringModifiers?.lowercased() == "h" {
                self.handleSecretKeyCombo()
                // Return nil to prevent further processing of this event
                return nil
            }
            
            // Alternative shortcut: Option+D (for "Diagnostics")
            if event.modifierFlags.contains(.option) && event.charactersIgnoringModifiers?.lowercased() == "d" {
                self.handleSecretKeyCombo()
                return nil
            }
            
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func handleSecretKeyCombo() {
        // Toggle advanced options with animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showAdvancedOptions.toggle()
        }
        
        // Log to console for debugging
        print("🔧 Advanced diagnostics options \(showAdvancedOptions ? "shown" : "hidden") - Use Shift+H or Option+D to toggle")
    }
    
    private func requestNotificationPermissions() {
        // In a real implementation, this would use UNUserNotificationCenter
        // to request permissions
        print("Requesting notification permissions")
        
        let alert = NSAlert()
        alert.messageText = "Notification Permissions"
        alert.informativeText = "This would normally request notification permissions from the system."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#Preview {
    SystemSettingsView()
        .environmentObject(AppState())
}