import SwiftUI

struct DevicesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    // Store credentials in UserDefaults for now
    @AppStorage("username") private var username: String = ""
    @AppStorage("password") private var password: String = ""
    
    @State private var isEditingAccount = false
    @State private var newUsername = ""
    @State private var newPassword = ""
    
    @State private var isSaving = false
    @State private var showingLoginError = false
    @State private var loginErrorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                accountSection
                futureDevicesSection
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 600, alignment: .center)
        }
        .alert("Error", isPresented: $showingLoginError) {
            Button("OK") {}
        } message: {
            Text(loginErrorMessage)
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
    
    private var futureDevicesSection: some View {
        SettingsSection(title: "Future Device Support", icon: "display.2") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coming Soon")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Text("Support for additional CGM devices and direct connections will be available in future updates.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                    .padding(.vertical, 8)
                
                Text("Supported Devices")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                supportedDeviceRow(name: "Abbott FreeStyle Libre", status: "Connected via LibreView")
                
                Divider()
                    .padding(.vertical, 4)
                
                supportedDeviceRow(name: "Dexcom G6/G7", status: "Coming soon", isEnabled: false)
                
                Divider()
                    .padding(.vertical, 4)
                
                supportedDeviceRow(name: "Medtronic Guardian", status: "Coming soon", isEnabled: false)
            }
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func supportedDeviceRow(name: String, status: String, isEnabled: Bool = true) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "clock.fill")
                    .foregroundColor(.gray)
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

#Preview {
    DevicesSettingsView()
        .environmentObject(AppState())
}