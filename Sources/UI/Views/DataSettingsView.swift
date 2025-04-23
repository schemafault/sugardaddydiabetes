import SwiftUI
import UniformTypeIdentifiers
import AppKit

// Add LogStore to manage logs efficiently
class LogStore: ObservableObject {
    @Published private(set) var logs: [LogEntry] = []
    private let maxEntries: Int
    private var logFileHandle: FileHandle?
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType
        
        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }
    
    enum LogType: String, CaseIterable {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var color: Color {
            switch self {
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
    
    init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }
    
    func addLog(_ message: String, type: LogType = .info) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.logs.append(LogEntry(timestamp: Date(), message: message, type: type))
            
            // Keep logs array within size limit to avoid memory issues
            if self.logs.count > self.maxEntries {
                self.logs.removeFirst(self.logs.count - self.maxEntries)
            }
        }
    }
    
    func clearLogs() {
        DispatchQueue.main.async { [weak self] in
            self?.logs.removeAll(keepingCapacity: true)
        }
    }
}

struct DataSettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    @AppStorage("dataGranularity") private var dataGranularity: Int = 0
    
    let availableGranularities = [0, 1, 5, 15, 30]
    
    @State private var showingDeletionConfirmation = false
    
    // Export options
    @State private var isShowingExportOptions = false
    @State private var selectedExportFormat = ExportFormat.json
    @State private var exportDateRange: ExportDateRange = .allData
    @State private var customStartDate = Date().addingTimeInterval(-30*24*60*60) // 30 days ago
    @State private var customEndDate = Date()
    @State private var exportDataGranularity = 0 // 0: All data, 1: 5-minute averages, etc.
    
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
    
    // Log viewer state
    @StateObject private var logStore = LogStore()
    @State private var showLogViewer = false
    @State private var logFilter: LogStore.LogType? = nil
    
    // Export format options
    enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv = "CSV"
        case pdf = "PDF"
        
        var id: Self { self }
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            case .pdf: return "pdf"
            }
        }
        
        var contentType: UTType {
            switch self {
            case .json: return UTType.json
            case .csv: return UTType.commaSeparatedText
            case .pdf: return UTType.pdf
            }
        }
        
        var description: String {
            switch self {
            case .json: return "Structured data format for software developers"
            case .csv: return "Compatible with Excel and most data analysis tools"
            case .pdf: return "Visual report with charts and statistics"
            }
        }
    }
    
    // Date range options for export
    enum ExportDateRange: String, CaseIterable, Identifiable {
        case last7Days = "Last 7 Days"
        case last14Days = "Last 14 Days"
        case last30Days = "Last 30 Days"
        case last90Days = "Last 90 Days"
        case customRange = "Custom Range"
        case allData = "All Data"
        
        var id: Self { self }
        
        func getDateRange() -> (Date, Date)? {
            let today = Date()
            switch self {
            case .last7Days:
                return (Calendar.current.date(byAdding: .day, value: -7, to: today)!, today)
            case .last14Days:
                return (Calendar.current.date(byAdding: .day, value: -14, to: today)!, today)
            case .last30Days:
                return (Calendar.current.date(byAdding: .day, value: -30, to: today)!, today)
            case .last90Days:
                return (Calendar.current.date(byAdding: .day, value: -90, to: today)!, today)
            case .customRange:
                return nil // Custom range requires separate start/end dates
            case .allData:
                return nil // All data doesn't need a specific range
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                dataGranularitySection
                dataManagementSection
                
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
            
            // Register our log store with the AppState
            appState.registerLogStore(logStore)
            
            // Add initial log entry
            logStore.addLog("Data Settings view opened", type: .info)
            
            // Add version info to logs for diagnostics
            if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                logStore.addLog("App version: \(appVersion) (\(buildNumber))", type: .info)
            }
        }
        .onDisappear {
            removeKeyMonitor()
            
            // Add log entry
            logStore.addLog("Data Settings view closed", type: .info)
            
            // Unregister our log store
            appState.unregisterLogStore()
        }
        .alert("Confirm Data Deletion", isPresented: $showingDeletionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await appState.clearAllData()
                }
            }
        } message: {
            Text("This will permanently delete all your stored glucose readings. This action cannot be undone.")
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
        .sheet(isPresented: $isShowingExportOptions) {
            exportOptionsView
        }
    }
    
    private var dataGranularitySection: some View {
        SettingsSection(title: "Data Granularity", icon: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose how readings are grouped:")
                    .font(.subheadline)
                
                Picker("Data Granularity", selection: $dataGranularity) {
                    Text("All readings").tag(0)
                    Text("Average per minute").tag(1)
                    Text("Average per 5 minutes").tag(5)
                    Text("Average per 15 minutes").tag(15)
                    Text("Average per 30 minutes").tag(30)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: dataGranularity) { oldValue, newValue in
                    // Reload data with new granularity
                    print("Granularity changed from \(oldValue) to \(newValue)")
                    Task {
                        await appState.reloadWithCurrentGranularity()
                    }
                }
                
                Text("Higher granularity reduces data points and improves performance.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var dataManagementSection: some View {
        SettingsSection(title: "Data Management", icon: "externaldrive") {
            VStack(alignment: .leading, spacing: 20) {
                // Export Medical Data button with format selection
                Button(action: { showExportOptions() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Medical Data")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Material.thin)
                    .foregroundColor(.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Export your glucose readings and insulin data")
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
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
                                
                                // Add log entry
                                logStore.addLog("Running database duplicate check", type: .info)
                                
                                // Set a timer to show the "completed" message
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    isDiagnosingDuplicates = false
                                    showDiagnosticResults = true
                                    
                                    // Add log entry for completion
                                    logStore.addLog("Database duplicate check completed", type: .info)
                                    
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
                                logStore.addLog("Database cleanup confirmation requested", type: .warning)
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
                        
                        Divider()
                        
                        // System Logs Section
                        VStack(alignment: .leading, spacing: 10) {
                            DisclosureGroup(
                                isExpanded: $showLogViewer,
                                content: {
                                    logViewerSection
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "terminal")
                                            .foregroundColor(.accentColor)
                                        Text("System Logs")
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        Text("\(logStore.logs.count) entries")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation {
                                            showLogViewer.toggle()
                                        }
                                    }
                                }
                            )
                            .padding(6)
                            .background(Color.accentColor.opacity(0.05))
                            .cornerRadius(8)
                        }
                        
                        Divider()
                        
                        // Clear all data (destructive)
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: { 
                                showingDeletionConfirmation = true
                                logStore.addLog("All data deletion confirmation requested", type: .error)
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                    Text("Clear All Data")
                                        .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                                .background(Material.thin)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            VStack(spacing: 4) {
                                Text("This will permanently delete all readings stored in the app.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Your LibreView account data will not be affected.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
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
    
    // Log viewer implementation
    private var logViewerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Controls
            HStack {
                Picker("Filter", selection: $logFilter) {
                    Text("All").tag(nil as LogStore.LogType?)
                    ForEach(LogStore.LogType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as LogStore.LogType?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    
                    let logString = filteredLogs.map { "[\($0.formattedTimestamp)] [\($0.type.rawValue)] \($0.message)" }.joined(separator: "\n")
                    pasteboard.setString(logString, forType: .string)
                    
                    logStore.addLog("Logs copied to clipboard", type: .info)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                Button(action: {
                    logStore.clearLogs()
                    logStore.addLog("Logs cleared", type: .info)
                }) {
                    Label("Clear", systemImage: "trash")
                }
            }
            
            // Log display area
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredLogs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.formattedTimestamp)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text(entry.type.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(entry.type.color)
                                .frame(width: 70, alignment: .leading)
                            
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(entry.type.color)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            .background(Color(.textBackgroundColor).opacity(0.3))
            .cornerRadius(6)
            
            Text("System logs are only stored in memory and will be cleared when the app is closed.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 10)
    }
    
    // Computed property for filtered logs
    private var filteredLogs: [LogStore.LogEntry] {
        guard let filter = logFilter else {
            return logStore.logs.reversed()
        }
        return logStore.logs.filter { $0.type == filter }.reversed()
    }
    
    // Export Options Sheet
    private var exportOptionsView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Export Medical Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select your preferred export format and data options")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Format selection section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Format")
                            .font(.headline)
                        
                        ForEach(ExportFormat.allCases) { format in
                            formatSelectionButton(format)
                        }
                    }
                    .padding(16)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Date range section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Date Range")
                            .font(.headline)
                        
                        // Custom picker instead of segmented control for better appearance
                        HStack(spacing: 0) {
                            ForEach(ExportDateRange.allCases.prefix(3)) { range in
                                dateRangeButton(range)
                            }
                        }
                        .frame(height: 30)
                        
                        HStack(spacing: 0) {
                            ForEach(ExportDateRange.allCases.suffix(3)) { range in
                                dateRangeButton(range)
                            }
                        }
                        .frame(height: 30)
                        
                        if exportDateRange == .customRange {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Start Date:")
                                        .frame(width: 80, alignment: .leading)
                                    
                                    DatePicker("", selection: $customStartDate, displayedComponents: [.date])
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity)
                                }
                                
                                HStack {
                                    Text("End Date:")
                                        .frame(width: 80, alignment: .leading)
                                    
                                    DatePicker("", selection: $customEndDate, displayedComponents: [.date])
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Data granularity section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Data Granularity")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            granularityButton(0, label: "All Data Points", iconName: "chart.xyaxis.line")
                            granularityButton(5, label: "5-Minute Averages", iconName: "chart.bar")
                            granularityButton(15, label: "15-Minute Averages", iconName: "chart.bar")
                            granularityButton(30, label: "30-Minute Averages", iconName: "chart.bar")
                            granularityButton(60, label: "Hourly Averages", iconName: "clock")
                        }
                        
                        Text("Higher granularity reduces file size but includes fewer data points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
            }
            
            Divider()
                .padding(.vertical, 16)
            
            // Footer buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    isShowingExportOptions = false
                }
                .keyboardShortcut(.escape)
                
                Button("Export") {
                    isShowingExportOptions = false
                    performExport()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 540, height: 580)
    }
    
    // Helper views for export options
    private func formatSelectionButton(_ format: ExportFormat) -> some View {
        Button(action: { selectedExportFormat = format }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color(.controlAccentColor), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if selectedExportFormat == format {
                        Circle()
                            .fill(Color(.controlAccentColor))
                            .frame(width: 12, height: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: formatIcon(for: format))
                            .foregroundColor(.accentColor)
                        
                        Text(format.rawValue)
                            .font(.headline)
                    }
                    
                    Text(format.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(8)
            .background(selectedExportFormat == format ? Color(.controlAccentColor).opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func dateRangeButton(_ range: ExportDateRange) -> some View {
        Button(action: { exportDateRange = range }) {
            Text(range.rawValue)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    exportDateRange == range ?
                    Color(.controlAccentColor) :
                    Color(.controlBackgroundColor)
                )
                .foregroundColor(
                    exportDateRange == range ?
                    Color(.controlBackgroundColor) :
                    Color(.labelColor)
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func granularityButton(_ value: Int, label: String, iconName: String) -> some View {
        Button(action: { exportDataGranularity = value }) {
            HStack {
                Image(systemName: iconName)
                    .frame(width: 22)
                    .foregroundColor(.accentColor)
                
                Text(label)
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color(.controlAccentColor), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if exportDataGranularity == value {
                        Circle()
                            .fill(Color(.controlAccentColor))
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(8)
            .background(exportDataGranularity == value ? Color(.controlAccentColor).opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // Helper function to get icon for format
    private func formatIcon(for format: ExportFormat) -> String {
        switch format {
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        }
    }
    
    // MARK: - Key Monitoring for advanced options
    
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
        
        // Log to console for debugging and to our log store
        let message = "🔧 Advanced data management options \(showAdvancedOptions ? "shown" : "hidden") - Use Shift+H or Option+D to toggle"
        print(message)
        logStore.addLog(message, type: .info)
    }
    
    // Function to show export options sheet
    private func showExportOptions() {
        isShowingExportOptions = true
    }
    
    // Function to perform export based on selected format
    private func performExport() {
        switch selectedExportFormat {
        case .json:
            exportAsJSON()
        case .csv:
            exportAsCSV()
        case .pdf:
            exportAsPDF()
        }
    }
    
    // Function to export medical data as JSON
    private func exportAsJSON() {
        // Generate export data
        let exportData = appState.generateMedicalExportData()
        
        // Apply date range filtering if needed
        let filteredData = filterDataByDateRange(exportData)
        
        do {
            // Configure date formatter for the JSON serializer to handle Date objects
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            
            // First convert dates to strings in our dictionary
            var processedData = filteredData
            
            // Handle the exportDate
            if let exportDate = processedData["exportDate"] as? Date {
                processedData["exportDate"] = dateFormatter.string(from: exportDate)
            }
            
            // Try to serialize with JSONSerialization
            let jsonData = try JSONSerialization.data(withJSONObject: processedData, options: [.prettyPrinted, .sortedKeys])
            
            // Create a save panel
            let savePanel = NSSavePanel()
            savePanel.title = "Export Medical Data as JSON"
            savePanel.message = "Choose a location to save the medical data"
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            
            // Generate filename with date range
            let dateRangeString = getDateRangeString()
            
            // Set suggested filename
            let patientName = appState.patientProfile?.name ?? "patient"
            let safePatientName = patientName.replacingOccurrences(of: " ", with: "_")
            savePanel.nameFieldStringValue = "diabetes_data_\(safePatientName)_\(dateRangeString).json"
            
            // Show the save panel as a window-independent sheet
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        // Write JSON data to file
                        try jsonData.write(to: url)
                        print("✅ Successfully exported medical data to: \(url.path)")
                    } catch {
                        print("❌ Failed to write export file: \(error)")
                        
                        // Show error alert
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Export Failed"
                            alert.informativeText = "Failed to write file: \(error.localizedDescription)"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                }
            }
        } catch {
            print("❌ Failed to generate JSON: \(error)")
            
            // Show error alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Failed to generate JSON: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    // Function to export medical data as CSV
    private func exportAsCSV() {
        // Generate export data
        let exportData = appState.generateMedicalExportData()
        
        // Apply date range filtering if needed
        let filteredData = filterDataByDateRange(exportData)
        
        // Convert the data to CSV format
        let csvData = generateCSVData(from: filteredData)
        
        // Create a save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Medical Data as CSV"
        savePanel.message = "Choose a location to save the medical data"
        savePanel.allowedContentTypes = [UTType.commaSeparatedText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        // Generate filename with date range
        let dateRangeString = getDateRangeString()
        
        // Set suggested filename
        let patientName = appState.patientProfile?.name ?? "patient"
        let safePatientName = patientName.replacingOccurrences(of: " ", with: "_")
        savePanel.nameFieldStringValue = "diabetes_data_\(safePatientName)_\(dateRangeString).csv"
        
        // Show the save panel as a window-independent sheet
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    // Write CSV data to file
                    try csvData.write(to: url, atomically: true, encoding: .utf8)
                    print("✅ Successfully exported CSV data to: \(url.path)")
                } catch {
                    print("❌ Failed to write CSV file: \(error)")
                    
                    // Show error alert
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Failed to write CSV file: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    // Function to export medical data as PDF (placeholder for now)
    private func exportAsPDF() {
        // Show a message that PDF export is coming soon
        let alert = NSAlert()
        alert.messageText = "PDF Export Coming Soon"
        alert.informativeText = "PDF export functionality is under development and will be available in a future update."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // Helper function to generate CSV data from the medical data
    private func generateCSVData(from data: [String: Any]) -> String {
        var csvString = ""
        
        // Add export date and glucose unit information as comments
        if let exportDate = data["exportDate"] as? String {
            csvString += "# Export Date: \(exportDate)\n"
        }
        if let glucoseUnit = data["glucoseUnit"] as? String {
            csvString += "# Glucose Unit: \(glucoseUnit)\n"
        }
        csvString += "\n"
        
        // Add patient profile information as comments
        if let patientProfile = data["patientProfile"] as? [String: Any] {
            csvString += "# Patient Information\n"
            for (key, value) in patientProfile {
                csvString += "# \(key): \(value)\n"
            }
            csvString += "\n"
        }
        
        // Create separate sections for glucose readings and insulin shots
        
        // Glucose Readings Section
        if let glucoseReadings = data["glucoseReadings"] as? [[String: Any]], !glucoseReadings.isEmpty {
            csvString += "# GLUCOSE READINGS\n"
            
            // Add headers
            csvString += "Timestamp,Value,Unit,IsHigh,IsLow\n"
            
            // Add data rows
            for reading in glucoseReadings {
                let timestamp = reading["timestamp"] as? String ?? ""
                let value = reading["value"] as? Double ?? 0.0
                let unit = reading["unit"] as? String ?? ""
                let isHigh = reading["isHigh"] as? Bool ?? false
                let isLow = reading["isLow"] as? Bool ?? false
                
                csvString += "\(timestamp),\(value),\(unit),\(isHigh),\(isLow)\n"
            }
            
            csvString += "\n"
        }
        
        // Insulin Shots Section
        if let insulinShots = data["insulinShots"] as? [[String: Any]], !insulinShots.isEmpty {
            csvString += "# INSULIN SHOTS\n"
            
            // Add headers
            csvString += "Timestamp,Dosage,Notes\n"
            
            // Add data rows
            for shot in insulinShots {
                let timestamp = shot["timestamp"] as? String ?? ""
                let dosage = shot["dosage"] as? Double ?? 0.0
                let notes = shot["notes"] as? String ?? ""
                
                // Escape commas in notes
                let escapedNotes = notes.replacingOccurrences(of: ",", with: ";")
                
                csvString += "\(timestamp),\(dosage),\"\(escapedNotes)\"\n"
            }
        }
        
        return csvString
    }
    
    // Helper function to filter data by selected date range
    private func filterDataByDateRange(_ data: [String: Any]) -> [String: Any] {
        // If All Data is selected, return the original data
        if exportDateRange == .allData {
            return data
        }
        
        var filteredData = data
        var startDate: Date
        var endDate: Date
        
        // Get date range
        if exportDateRange == .customRange {
            startDate = customStartDate
            endDate = customEndDate
        } else if let dateRange = exportDateRange.getDateRange() {
            startDate = dateRange.0
            endDate = dateRange.1
        } else {
            // Fallback to all data if no valid date range
            return data
        }
        
        // Adjust end date to end of day
        let calendar = Calendar.current
        endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        
        // Filter glucose readings
        if var glucoseReadings = filteredData["glucoseReadings"] as? [[String: Any]] {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            
            glucoseReadings = glucoseReadings.filter { reading in
                if let timestampString = reading["timestamp"] as? String,
                   let timestamp = dateFormatter.date(from: timestampString) {
                    return timestamp >= startDate && timestamp <= endDate
                }
                return false
            }
            
            filteredData["glucoseReadings"] = glucoseReadings
        }
        
        // Filter insulin shots
        if var insulinShots = filteredData["insulinShots"] as? [[String: Any]] {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            
            insulinShots = insulinShots.filter { shot in
                if let timestampString = shot["timestamp"] as? String,
                   let timestamp = dateFormatter.date(from: timestampString) {
                    return timestamp >= startDate && timestamp <= endDate
                }
                return false
            }
            
            filteredData["insulinShots"] = insulinShots
        }
        
        return filteredData
    }
    
    // Helper function to get a string representation of the date range for filenames
    private func getDateRangeString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        switch exportDateRange {
        case .last7Days, .last14Days, .last30Days, .last90Days:
            if let dateRange = exportDateRange.getDateRange() {
                let startString = dateFormatter.string(from: dateRange.0)
                let endString = dateFormatter.string(from: dateRange.1)
                return "\(startString)_to_\(endString)"
            }
        case .customRange:
            let startString = dateFormatter.string(from: customStartDate)
            let endString = dateFormatter.string(from: customEndDate)
            return "\(startString)_to_\(endString)"
        case .allData:
            return "all_data"
        }
        
        // Default fallback
        return dateFormatter.string(from: Date())
    }
}

#Preview {
    DataSettingsView()
        .environmentObject(AppState())
}