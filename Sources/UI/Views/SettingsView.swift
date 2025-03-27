import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("username") private var username: String = ""
    @AppStorage("password") private var password: String = ""
    @AppStorage("unit") private var unit: String = "mg/dL"
    @AppStorage("lowThreshold") private var lowThreshold: String = "70"
    @AppStorage("highThreshold") private var highThreshold: String = "180"
    @AppStorage("updateInterval") private var updateInterval: Int = 15
    
    @State private var showingDeletionConfirmation = false
    @State private var isEditingAccount = false
    @State private var newUsername = ""
    @State private var newPassword = ""
    
    @State private var isSaving = false
    @State private var showingLoginError = false
    @State private var loginErrorMessage = ""
    
    let availableIntervals = [5, 10, 15, 30, 60]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                accountSection
                unitsSection
                thresholdsSection
                updateIntervalSection
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
            // Attempt to verify credentials before saving
            let result = await appState.verifyCredentials(username: newUsername, password: newPassword)
            
            await MainActor.run {
                isSaving = false
                
                if result.success {
                    username = newUsername
                    password = newPassword
                    isEditingAccount = false
                    appState.isAuthenticated = true
                } else {
                    loginErrorMessage = result.message ?? "Failed to verify account credentials. Please check your username and password."
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