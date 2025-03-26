import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var username: String = UserDefaults.standard.string(forKey: "username") ?? ""
    @State private var password: String = UserDefaults.standard.string(forKey: "password") ?? ""
    @State private var selectedUnit: String = UserDefaults.standard.string(forKey: "unit") ?? "mg/dL"
    @State private var lowThreshold: String
    @State private var highThreshold: String
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    @FocusState private var focusedField: Field?
    
    init() {
        // Set initial values based on unit
        let unit = UserDefaults.standard.string(forKey: "unit") ?? "mg/dL"
        if unit == "mmol" {
            _lowThreshold = State(initialValue: UserDefaults.standard.string(forKey: "lowThreshold") ?? "3.0")
            _highThreshold = State(initialValue: UserDefaults.standard.string(forKey: "highThreshold") ?? "10.0")
        } else {
            _lowThreshold = State(initialValue: UserDefaults.standard.string(forKey: "lowThreshold") ?? "70")
            _highThreshold = State(initialValue: UserDefaults.standard.string(forKey: "highThreshold") ?? "180")
        }
    }
    
    enum Field: Hashable {
        case username
        case password
        case lowThreshold
        case highThreshold
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // LibreView Credentials Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("LibreView Credentials")
                        .font(.headline)
                    
                    AppKitTextField(text: $username, placeholder: "Username/Email", onFocus: {
                        print("Settings: Native username field focused")
                        // Ensure app is active when this happens
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }, onTextChange: { newValue in
                        print("Settings: Native username changed to: \(newValue)")
                    })
                    .frame(height: 24)
                    
                    AppKitTextField(text: $password, placeholder: "Password", secure: true, onFocus: {
                        print("Settings: Native password field focused")
                        // Ensure app is active when this happens
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }, onTextChange: { newValue in
                        print("Settings: Native password changed to: \(newValue.count) characters")
                    })
                    .frame(height: 24)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Unit Selection Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Units")
                        .font(.headline)
                    
                    Picker("Unit", selection: $selectedUnit) {
                        Text("mg/dL").tag("mg/dL")
                        Text("mmol/L").tag("mmol")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedUnit) { newUnit in
                        UserDefaults.standard.set(newUnit, forKey: "unit")
                        
                        // Convert threshold values
                        if let lowValue = Double(lowThreshold),
                           let highValue = Double(highThreshold) {
                            if newUnit == "mmol" {
                                // Convert from mg/dL to mmol/L
                                lowThreshold = String(format: "%.1f", lowValue / 18.0182)
                                highThreshold = String(format: "%.1f", highValue / 18.0182)
                            } else {
                                // Convert from mmol/L to mg/dL
                                lowThreshold = String(format: "%.0f", lowValue * 18.0182)
                                highThreshold = String(format: "%.0f", highValue * 18.0182)
                            }
                            
                            // Save the converted values
                            UserDefaults.standard.set(lowThreshold, forKey: "lowThreshold")
                            UserDefaults.standard.set(highThreshold, forKey: "highThreshold")
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Alert Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Alert Settings")
                        .font(.headline)
                    
                    HStack {
                        Text("Low Threshold")
                        Spacer()
                        AppKitTextField(text: $lowThreshold, placeholder: "Low", onFocus: {
                            print("Settings: Low threshold field focused")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }, onTextChange: { newValue in
                            print("Settings: Low threshold changed to: \(newValue)")
                        })
                        .frame(width: 80, height: 24)
                        Text(selectedUnit == "mmol" ? "mmol/L" : "mg/dL")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("High Threshold")
                        Spacer()
                        AppKitTextField(text: $highThreshold, placeholder: "High", onFocus: {
                            print("Settings: High threshold field focused")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }, onTextChange: { newValue in
                            print("Settings: High threshold changed to: \(newValue)")
                        })
                        .frame(width: 80, height: 24)
                        Text(selectedUnit == "mmol" ? "mmol/L" : "mg/dL")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Buttons Section
                VStack(spacing: 12) {
                    Button(action: saveChanges) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save Changes")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    .keyboardShortcut(.return, modifiers: .command)
                    
                    Button(action: logout) {
                        Text("Logout")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || !appState.isAuthenticated)
                }
            }
            .padding()
        }
        .navigationTitle("Settings")
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            print("Settings view appeared - native fields will handle focus")
            
            // Give UI time to fully initialize before activating window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Force app to front
                NSApplication.shared.activate(ignoringOtherApps: true)
                
                // Find and properly activate the settings window
                if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.title.contains("Settings") }) {
                    // Make sure window is properly configured for text input
                    window.makeKey()
                    window.makeMain()
                    window.orderFront(nil)
                    
                    // Reset responder chain
                    window.makeFirstResponder(nil)
                    
                    print("Settings window properly activated and configured")
                }
            }
        }
        .onDisappear {
            print("Settings view disappeared")
        }
    }
    
    private func saveChanges() {
        // Validate thresholds
        guard let lowValue = Double(lowThreshold),
              let highValue = Double(highThreshold) else {
            alertMessage = "Please enter valid numbers for thresholds"
            showingAlert = true
            return
        }
        
        // Additional validation based on unit
        if selectedUnit == "mmol" {
            guard lowValue >= 2.0 && lowValue <= 20.0 &&
                  highValue >= 2.0 && highValue <= 20.0 else {
                alertMessage = "Thresholds must be between 2.0 and 20.0 mmol/L"
                showingAlert = true
                return
            }
        } else {
            guard lowValue >= 40 && lowValue <= 400 &&
                  highValue >= 40 && highValue <= 400 else {
                alertMessage = "Thresholds must be between 40 and 400 mg/dL"
                showingAlert = true
                return
            }
        }
        
        guard highValue > lowValue else {
            alertMessage = "High threshold must be greater than low threshold"
            showingAlert = true
            return
        }
        
        // Save all settings
        UserDefaults.standard.set(username, forKey: "username")
        UserDefaults.standard.set(password, forKey: "password")
        UserDefaults.standard.set(selectedUnit, forKey: "unit")
        UserDefaults.standard.set(lowThreshold, forKey: "lowThreshold")
        UserDefaults.standard.set(highThreshold, forKey: "highThreshold")
        
        // Notify user
        alertMessage = "Settings saved successfully"
        showingAlert = true
    }
    
    private func logout() {
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "password")
        username = ""
        password = ""
        appState.isAuthenticated = false
        alertMessage = "Logged out successfully"
        showingAlert = true
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
} 