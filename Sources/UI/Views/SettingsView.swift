import SwiftUI
import Security // Required for working with the keychain
import AppKit // Required for NSEvent monitoring
import UniformTypeIdentifiers // Required for UTType

// Debug extension to print current value of a UserDefaults key
extension UserDefaults {
    // The correct bundle ID for the app
    static let appBundleID = "com.magiworks.diabetesmonitor"
    
    static func debugValue(forKey key: String) {
        let standardValue = UserDefaults.standard.string(forKey: key)
        print("DEBUG UserDefaults.standard[\(key)] = \(standardValue ?? "nil")")
        
        // Also check app-specific domain
        let appDefaults = UserDefaults(suiteName: appBundleID)
        let appValue = appDefaults?.string(forKey: key)
        print("DEBUG UserDefaults[\(appBundleID)][\(key)] = \(appValue ?? "nil")")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    // Store credentials in UserDefaults for now
    @AppStorage("username") private var username: String = ""
    @AppStorage("password") private var password: String = ""
    
    @AppStorage("unit") private var unit: String = "mg/dL"
    @AppStorage("lowThreshold") private var lowThreshold: String = "70"
    @AppStorage("highThreshold") private var highThreshold: String = "180"
    @AppStorage("updateInterval") private var updateInterval: Int = 15
    @AppStorage("dataGranularity") private var dataGranularity: Int = 0 // 0: All readings, 1: Per minute, 5: Per 5 minutes, etc.
    
    @State private var showingDeletionConfirmation = false
    @State private var isEditingAccount = false
    @State private var newUsername = ""
    @State private var newPassword = ""
    
    @State private var isSaving = false
    @State private var showingLoginError = false
    @State private var loginErrorMessage = ""
    
    // Add state for patient profile
    @State private var isEditingPatientProfile = false
    @State private var patientName = ""
    @State private var dateOfBirth: Date = Date()
    @State private var weight = ""
    @State private var weightUnit = "kg"
    @State private var insulinType = ""
    @State private var insulinDose = ""
    @State private var otherMedications = ""
    
    // Add state for diagnostic operations
    @State private var isDiagnosingDuplicates = false
    @State private var showDiagnosticResults = false
    
    // Add state for cleanup operations
    @State private var showCleanupConfirmation = false
    @State private var showCleanupResultAlert = false
    @State private var cleanupResultMessage = ""
    
    // Advanced options visibility control
    @State private var showAdvancedOptions = false
    @State private var keyMonitor: Any? = nil
    
    let availableIntervals = [5, 10, 15, 30, 60]
    let availableGranularities = [0, 1, 5, 15, 30]
    let weightUnits = ["kg", "lbs"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                accountSection
                patientProfileSection
                unitsSection
                thresholdsSection
                updateIntervalSection
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
        .navigationTitle("Settings")
        .onAppear {
            setupKeyMonitor()
            loadPatientProfile()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .alert("Error", isPresented: $showingLoginError) {
            Button("OK") {}
        } message: {
            Text(loginErrorMessage)
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
    }
    
    private var accountSection: some View {
        SettingsSection(title: "LibreView Account", icon: "person.fill") {
            if isEditingAccount {
                VStack(spacing: 15) {
                    TextField("Username/Email", text: $newUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    SecureField("Password", text: $newPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    HStack {
                        Button("Cancel") {
                            isEditingAccount = false
                            newUsername = username
                            newPassword = password
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveAccountInfo()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newUsername.isEmpty || newPassword.isEmpty || isSaving)
                        .overlay {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                    }
                }
                .padding()
                .background(Material.thin)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        if !username.isEmpty {
                            Text(username)
                                .font(.headline)
                            
                            Text("•••••••••")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No account configured")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        isEditingAccount = true
                        newUsername = username
                        newPassword = password
                    }) {
                        Text(username.isEmpty ? "Add Account" : "Edit")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Material.thin)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var patientProfileSection: some View {
        SettingsSection(title: "Patient Information", icon: "person.text.rectangle") {
            if isEditingPatientProfile {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Patient Information")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Name", text: $patientName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Date of Birth")
                                .font(.subheadline)
                            
                            // Use NSDatePicker wrapped in NSViewRepresentable for proper formatting
                            DatePickerWithFormat(date: $dateOfBirth)
                                .frame(height: 24)
                        }
                        
                        HStack {
                            TextField("Weight", text: $weight)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Picker("Unit", selection: $weightUnit) {
                                ForEach(weightUnits, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                            .frame(width: 80)
                        }
                    }
                    
                    Text("Medication Information")
                        .font(.headline)
                        .padding(.top, 10)
                        .padding(.bottom, 5)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Insulin Type", text: $insulinType)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .help("e.g., Humalog, Novolog, Lantus")
                        
                        TextField("Insulin Dose", text: $insulinDose)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .help("e.g., 10 units morning, 8 units evening")
                        
                        Text("Other Medications")
                            .font(.subheadline)
                        
                        TextEditor(text: $otherMedications)
                            .frame(height: 80)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .help("List other medications with dosage")
                    }
                    
                    HStack {
                        Button("Cancel") {
                            isEditingPatientProfile = false
                            loadPatientProfile()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Save") {
                            savePatientProfile()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 10)
                }
                .padding()
                .background(Material.thin)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let profile = appState.patientProfile, let name = profile.name, !name.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(name)
                                        .font(.headline)
                                    
                                    if let _ = profile.dateOfBirth, let age = profile.formattedAge {
                                        Text("Age: \(age)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let formattedWeight = profile.formattedWeight {
                                        Text("Weight: \(formattedWeight)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    isEditingPatientProfile = true
                                }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            if let insulinType = profile.insulinType, !insulinType.isEmpty {
                                Text("Insulin: \(insulinType)")
                                    .font(.subheadline)
                                
                                if let insulinDose = profile.insulinDose, !insulinDose.isEmpty {
                                    Text("Dose: \(insulinDose)")
                                        .font(.subheadline)
                                }
                            }
                            
                            if let medications = profile.otherMedications, !medications.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Other Medications:")
                                        .font(.subheadline)
                                    
                                    Text(medications)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            
                            // Add export button 
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    exportMedicalData()
                                }) {
                                    Label("Export Medical Data", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                                .help("Export patient data and glucose readings for medical professionals")
                            }
                            .padding(.top, 10)
                        }
                    } else {
                        HStack {
                            Text("No patient information configured")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                isEditingPatientProfile = true
                            }) {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Material.thin)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
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
            VStack(alignment: .leading, spacing: 10) {
                Button(action: { showingDeletionConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Data")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Material.thin)
                    .foregroundColor(.red)
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
    
    private func saveAccountInfo() {
        isSaving = true
        
        Task {
            // Debug current values
            print("Before save - Checking values in UserDefaults:")
            UserDefaults.debugValue(forKey: "username")
            UserDefaults.debugValue(forKey: "password")
            
            // IMPORTANT: First save the credentials without verification
            // This ensures we don't get into a state where verification fails but user can't update credentials
            await MainActor.run {
                print("Saving credentials without verification first")
                UserDefaults.standard.set(newUsername, forKey: "username")
                UserDefaults.standard.set(newPassword, forKey: "password")
                UserDefaults.standard.synchronize()
                
                // Update @AppStorage properties which should reflect the changes
                username = newUsername
                password = newPassword
            }
            
            // Now attempt to verify the credentials - this is secondary
            // Even if verification fails, we'll keep the credentials
            do {
                print("Attempting to verify credentials after saving")
                let isValid = try await appState.checkAuthentication()
                
                await MainActor.run {
                    isSaving = false
                    
                    if isValid {
                        print("Credentials verified successfully")
                        isEditingAccount = false
                        appState.isAuthenticated = true
                        
                        // Force refresh data with new credentials
                        Task {
                            await appState.fetchLatestReadings()
                        }
                    } else {
                        // Even if verification fails, keep the credentials
                        print("Warning: Credentials were saved but verification returned false")
                        loginErrorMessage = "Credentials saved, but verification failed. Your credentials may be incorrect."
                        showingLoginError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    print("Verification error: \(error)")
                    loginErrorMessage = "Credentials saved, but verification encountered an error: \(error.localizedDescription)"
                    showingLoginError = true
                }
            }
        }
    }
    
    // Load patient profile data into state variables
    private func loadPatientProfile() {
        if let profile = appState.patientProfile {
            patientName = profile.name ?? ""
            
            if let dob = profile.dateOfBirth {
                dateOfBirth = dob
            } else {
                // Default to a reasonable birth date if none is set
                let defaultDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
                dateOfBirth = defaultDate
            }
            
            // Handle optional Double value with nil coalescing
            weight = (profile.weight ?? 0) > 0 ? String(profile.weight ?? 0) : ""
            
            weightUnit = profile.weightUnit ?? "kg"
            insulinType = profile.insulinType ?? ""
            insulinDose = profile.insulinDose ?? ""
            otherMedications = profile.otherMedications ?? ""
        } else {
            // Initialize with reasonable defaults
            let defaultDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
            dateOfBirth = defaultDate
        }
    }
    
    // Save patient profile data
    private func savePatientProfile() {
        var weightValue: Double?
        if let doubleWeight = Double(weight) {
            weightValue = doubleWeight
        }
        
        appState.updatePatientProfile(
            name: patientName,
            dateOfBirth: dateOfBirth,
            weight: weightValue,
            weightUnit: weightUnit,
            insulinType: insulinType,
            insulinDose: insulinDose,
            otherMedications: otherMedications
        )
        
        isEditingPatientProfile = false
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
    
    // Function to export medical data
    private func exportMedicalData() {
        // Generate export data
        let exportData = appState.generateMedicalExportData()
        
        do {
            // Configure date formatter for the JSON serializer to handle Date objects
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            
            // Convert to JSON with ISO date formatting
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            // First convert dates to strings in our dictionary
            var processedData = exportData
            
            // Handle the exportDate
            if let exportDate = processedData["exportDate"] as? Date {
                processedData["exportDate"] = dateFormatter.string(from: exportDate)
            }
            
            // Try to serialize with JSONSerialization
            let jsonData = try JSONSerialization.data(withJSONObject: processedData, options: [.prettyPrinted, .sortedKeys])
            
            // Create a save panel
            let savePanel = NSSavePanel()
            savePanel.title = "Export Medical Data"
            savePanel.message = "Choose a location to save the medical data"
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            
            // Generate filename with current date
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            
            // Set suggested filename
            let patientName = appState.patientProfile?.name ?? "patient"
            let safePatientName = patientName.replacingOccurrences(of: " ", with: "_")
            savePanel.nameFieldStringValue = "diabetes_data_\(safePatientName)_\(dateString).json"
            
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
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 36, height: 36)
                    )
                
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 4)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Add this at the end of the file, outside the SettingsView struct
struct DatePickerWithFormat: NSViewRepresentable {
    @Binding var date: Date
    
    func makeNSView(context: Context) -> NSDatePicker {
        let datePicker = NSDatePicker()
        
        // Configure the date picker for text field style with 4-digit years
        datePicker.datePickerStyle = .textField
        datePicker.datePickerElements = .yearMonthDay
        datePicker.calendar = Calendar(identifier: .gregorian)
        
        // Create formatter with 4-digit year and set it on the picker
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy" // Explicitly use 4-digit year
        datePicker.formatter = formatter
        
        // Set value
        datePicker.dateValue = date
        
        // Set up delegate to handle changes
        datePicker.target = context.coordinator
        datePicker.action = #selector(Coordinator.dateChanged(_:))
        
        // Set constraints
        datePicker.minDate = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))
        datePicker.maxDate = Date()
        
        return datePicker
    }
    
    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        nsView.dateValue = date
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: DatePickerWithFormat
        
        init(_ parent: DatePickerWithFormat) {
            self.parent = parent
        }
        
        @objc func dateChanged(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}