import SwiftUI
import Security // Required for working with the keychain

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
    
    let availableIntervals = [5, 10, 15, 30, 60]
    let availableGranularities = [0, 1, 5, 15, 30]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                accountSection
                unitsSection
                thresholdsSection
                updateIntervalSection
                dataGranularitySection
                dataManagementSection
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 600, alignment: .center)
        }
        .navigationTitle("Settings")
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
                
                Group {
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}