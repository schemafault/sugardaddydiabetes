import SwiftUI
import AppKit
import CoreData
import Security // Required for keychain access

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var updateTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize CoreData with programmatic model
        _ = ProgrammaticCoreDataManager.shared
        
        // Configure update timer
        setupUpdateTimer()
        
        // Handle Termination
        NSApplication.shared.registerForRemoteNotifications()
        
        print("App did finish launching")
        
        // Set proper activation policy
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Activate the app properly
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Add additional window management configuration
        NSApp.windows.forEach { window in
            window.isMovableByWindowBackground = false
            
            // Ensure windows can become key window
            if window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
        
        // Register for URL handling
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        print("Handling URL: \(url)")
        
        if url.host == "dashboard" {
            // Show the main window
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("Dashboard") }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Create the window if it doesn't exist
                    for window in NSApp.windows where window.title.contains("Diabetes Monitor") {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            }
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        print("App became active")
        
        // We DON'T need to call activate again here - that's causing the loop!
        // DO NOT call NSApplication.shared.activate() from this method
        
        // Minimal window handling to avoid focus issues
        if let keyWindow = NSApp.keyWindow, !keyWindow.isKeyWindow {
            keyWindow.makeKeyAndOrderFront(nil)
            
            // Ensure field editor is properly configured
            if let fieldEditor = keyWindow.fieldEditor(true, for: nil) {
                fieldEditor.isSelectable = true
                fieldEditor.isEditable = true
            }
        }
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        print("App resigned active")
    }
    
    private func setupUpdateTimer() {
        // Check for glucose updates every 5 minutes (300 seconds)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let appState = self?.appState else { return }
            
            Task {
                await appState.fetchLatestReadings()
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Stop timer
        updateTimer?.invalidate()
        
        // Ensure CoreData is saved on exit
        ProgrammaticCoreDataManager.shared.saveContext()
    }
}

// Native login window controller
class LoginWindowController: NSWindowController, NSWindowDelegate {
    var onCredentialsEntered: ((String, String) -> Void)? = nil
    
    convenience init() {
        // Create a simple window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LibreView Login"
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        window.delegate = self
        
        // Create text fields and buttons
        setupUI()
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Welcome to Diabetes Monitor")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Please enter your LibreView credentials to get started")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        
        // Username field
        let usernameField = NSTextField(frame: .zero)
        usernameField.placeholderString = "Username/Email"
        usernameField.bezelStyle = .roundedBezel
        usernameField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(usernameField)
        
        // Password field
        let passwordField = NSSecureTextField(frame: .zero)
        passwordField.placeholderString = "Password"
        passwordField.bezelStyle = .roundedBezel
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(passwordField)
        
        // Error label (hidden initially)
        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = NSColor.systemRed
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(errorLabel)
        
        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)
        
        // Login button
        let loginButton = NSButton(title: "Save & Continue", target: self, action: #selector(loginClicked))
        loginButton.bezelStyle = .rounded
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(loginButton)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            
            usernameField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            usernameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            usernameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            usernameField.heightAnchor.constraint(equalToConstant: 24),
            
            passwordField.topAnchor.constraint(equalTo: usernameField.bottomAnchor, constant: 10),
            passwordField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            passwordField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            passwordField.heightAnchor.constraint(equalToConstant: 24),
            
            errorLabel.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            loginButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            loginButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
        
        // Store references to the fields
        self.usernameField = usernameField
        self.passwordField = passwordField
        self.errorLabel = errorLabel
        self.loginButton = loginButton
        
        // Set the content view
        window.contentView = contentView
        
        // Make username field first responder
        window.initialFirstResponder = usernameField
    }
    
    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var errorLabel: NSTextField!
    private var loginButton: NSButton!
    private var isLoading = false
    
    @objc private func cancelClicked() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func loginClicked() {
        guard !isLoading else { return }
        
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        
        guard !username.isEmpty && !password.isEmpty else {
            showError("Please enter both username and password")
            return
        }
        
        startLoading()
        onCredentialsEntered?(username, password)
    }
    
    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        stopLoading()
    }
    
    func startLoading() {
        isLoading = true
        loginButton.isEnabled = false
        loginButton.title = "Loading..."
    }
    
    func stopLoading() {
        isLoading = false
        loginButton.isEnabled = true
        loginButton.title = "Save & Continue"
    }
    
    func windowWillClose(_ notification: Notification) {
        // Do nothing when window closes - only terminate if this is initial setup
        if UserDefaults.standard.string(forKey: "username") == nil {
            NSApplication.shared.terminate(nil)
        }
    }
}

@main
struct DiabetesMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    // Store window controller reference
    @State private var loginWindowController: LoginWindowController? = nil
    
    var body: some Scene {
        WindowGroup("Diabetes Monitor", id: "main") {
            ContentView(selectedTab: $appState.selectedTab)
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Set appState in AppDelegate
                    appDelegate.appState = appState
                    
                    // Debug what's in the defaults
                    let username = UserDefaults.standard.string(forKey: "username")
                    let password = UserDefaults.standard.string(forKey: "password")
                    print("DEBUG UserDefaults - username: \(username != nil ? "found" : "missing"), password: \(password != nil ? "found" : "missing")")
                    
                    let hasCredentials = username != nil && password != nil
                    
                    print("🔐 Checking for existing credentials: \(hasCredentials ? "Found" : "Not found")")
                    
                    // Configure NSWindow for better text field behavior
                    configureWindows()
                    
                    // Show login window ONLY if there are no credentials
                    if !hasCredentials {
                        print("📱 No credentials found - showing login window")
                        showNativeLoginWindow()
                    } else {
                        print("🔑 Using existing credentials - skipping login screen")
                        
                        // If credentials exist, fetch data in background but don't show login on failure
                        // This provides a better experience - user won't be interrupted with login screens
                        Task {
                            // Try to fetch data using stored credentials
                            do {
                                await appState.fetchLatestReadings()
                            } catch {
                                print("⚠️ Fetch attempt with existing credentials failed: \(error)")
                                // We don't show the login window here - that would be disruptive
                                // Instead, the error will be shown in the app and user can manually fix credentials
                            }
                        }
                    }
                }
        }
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "diabetesmonitor"))
        .commands {
            // Hide the default "New Window" menu item
            CommandGroup(replacing: .newItem) {}
        }
        
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                if let reading = appState.currentGlucoseReading {
                    // Show glucose value in menu bar with color
                    Text(String(format: "%.1f", reading.displayValue))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(reading.isInRange ? .green : (reading.isHigh ? .red : .yellow))
                    
                    // Add an icon according to trend
                    Image(systemName: reading.trend.icon)
                        .imageScale(.small)
                        .foregroundColor(reading.rangeStatus.color)
                } else {
                    // Fallback when no reading is available
                    Image(systemName: "heart.fill")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
    
    private func showNativeLoginWindow() {
        print("🪟 Creating and showing login window")
        
        // First, ensure we don't already have a login window showing
        if loginWindowController != nil {
            print("🪟 Login window already exists, bringing to front")
            loginWindowController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Create and show the login window
        let windowController = LoginWindowController()
        
        // Set callback for when credentials are entered
        windowController.onCredentialsEntered = { username, password in
            // Test credentials
            Task {
                do {
                    // Directly save credentials to UserDefaults
                    print("Saving credentials to UserDefaults...")
                    UserDefaults.standard.set(username, forKey: "username")
                    UserDefaults.standard.set(password, forKey: "password")
                    
                    // Debug what was saved
                    let savedUsername = UserDefaults.standard.string(forKey: "username")
                    let savedPassword = UserDefaults.standard.string(forKey: "password")
                    print("Saved username: \(savedUsername != nil ? "YES" : "NO"), Saved password: \(savedPassword != nil ? "YES" : "NO")")
                    
                    // Force UserDefaults to synchronize to ensure values are saved immediately
                    UserDefaults.standard.synchronize()
                    
                    // Create a service to test the credentials
                    let service = LibreViewService()
                    let isValid = try await service.checkAuthentication()
                    
                    await MainActor.run {
                        if isValid {
                            // If valid, close login window
                            windowController.close()
                            loginWindowController = nil
                        } else {
                            // If not valid, show error and clear credentials
                            UserDefaults.standard.removeObject(forKey: "username")
                            UserDefaults.standard.removeObject(forKey: "password")
                            windowController.showError("Invalid username or password")
                        }
                    }
                } catch {
                    await MainActor.run {
                        // If error, show error and clear credentials
                        UserDefaults.standard.removeObject(forKey: "username")
                        UserDefaults.standard.removeObject(forKey: "password")
                        windowController.showError("Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Show the window
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        
        // Store reference to prevent it from being deallocated
        loginWindowController = windowController
    }
    
    private func configureWindows() {
        DispatchQueue.main.async {
            // Bring application to front first
            NSApp.activate(ignoringOtherApps: true)
            
            for window in NSApplication.shared.windows {
                // Skip status bar windows which can't become key or main
                if NSStringFromClass(type(of: window)).contains("StatusBarWindow") ||
                   NSStringFromClass(type(of: window)).contains("MenuBarExtra") {
                    print("Skipping menu bar or status bar window configuration")
                    continue
                }
                
                // Only apply style to regular windows
                if window.styleMask.contains(.titled) {
                    // Apply full standard window style mask with all controls and resizing
                    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                    
                    // Enable proper text field handling
                    window.isMovableByWindowBackground = false
                    window.preventsApplicationTerminationWhenModal = false
                    
                    // Set behavior for proper focus
                    window.collectionBehavior = [.fullScreenPrimary]
                    
                    // Ensure proper field editor configuration
                    if let fieldEditor = window.fieldEditor(true, for: nil) {
                        fieldEditor.isSelectable = true
                        fieldEditor.isEditable = true
                    }
                    
                    // Set min size constraints
                    window.minSize = NSSize(width: 800, height: 600)
                    window.setContentSize(NSSize(width: 900, height: 700))
                    
                    // Set activation policy to ensure input
                    NSApp.setActivationPolicy(.regular)
                    
                    // Don't replace existing window delegate which might handle other things
                    if window.delegate == nil {
                        let delegate = FocusDebuggingWindowDelegate()
                        window.delegate = delegate
                    }
                    
                    // Only try to make key/main if the window can be key/main
                    if window.canBecomeKey {
                        window.makeKey()
                    }
                    
                    if window.canBecomeMain {
                        window.makeMain()
                    }
                    
                    if window.canBecomeKey || window.canBecomeMain {
                        window.orderFront(nil)
                    }
                    
                    print("Configured window: \(window.title) with style mask: \(window.styleMask)")
                }
            }
        }
    }
}

// Window delegate for debugging focus issues
class FocusDebuggingWindowDelegate: NSObject, NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        print("Window became key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        print("Window resigned key")
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        print("Window became main")
    }
    
    func windowDidResignMain(_ notification: Notification) {
        print("Window resigned main")
    }
}

// Add NSTextField wrapper
struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var secure: Bool = false
    var onFocus: (() -> Void)? = nil
    var onTextChange: ((String) -> Void)? = nil
    
    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField
        if secure {
            textField = NSSecureTextField()
        } else {
            textField = NSTextField()
        }
        
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.bezelStyle = .roundedBezel
        textField.delegate = context.coordinator
        
        // Critical focus handling settings
        textField.focusRingType = .exterior
        textField.isEditable = true
        textField.isSelectable = true
        textField.drawsBackground = true
        textField.isBezeled = true
        
        // Ensure the text field can become first responder
        textField.refusesFirstResponder = false
        
        // Allow keyboard input
        textField.allowsEditingTextAttributes = true
        textField.isEnabled = true
        
        // Explicitly set the action handler
        textField.action = #selector(context.coordinator.textFieldAction(_:))
        textField.target = context.coordinator
        
        return textField
    }
    
    func updateNSView(_ textField: NSTextField, context: Context) {
        // Only update if text values don't match and not being edited
        if textField.stringValue != text {
            // Check if field is not currently being edited
            let isBeingEdited = textField.window?.firstResponder == textField || 
                               textField.window?.firstResponder == textField.currentEditor()
            
            if !isBeingEdited {
                textField.stringValue = text
            }
        }
        
        // Always ensure editable state
        textField.isEditable = true
        textField.isEnabled = true
    }
    
    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        // Clean up any field editor references
        if let window = nsView.window, 
           let fieldEditor = window.fieldEditor(false, for: nil) {
            fieldEditor.resignFirstResponder()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppKitTextField
        
        init(_ parent: AppKitTextField) {
            self.parent = parent
            super.init()
        }
        
        @objc func textFieldAction(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onTextChange?(sender.stringValue)
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                // Always update binding with current value
                parent.text = textField.stringValue
                parent.onTextChange?(textField.stringValue)
            }
        }
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                // Ensure app is active when editing begins
                if !NSApp.isActive {
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                // Ensure window is key and main
                if let window = textField.window {
                    if !window.isKeyWindow {
                        window.makeKey()
                        window.makeMain()
                        window.orderFront(nil)
                    }
                    
                    // Ensure field editor is active
                    if let fieldEditor = window.fieldEditor(true, for: textField) {
                        fieldEditor.isSelectable = true
                        fieldEditor.isEditable = true
                    }
                }
                
                parent.onFocus?()
            }
        }
        
        // Let system handle all key presses
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            return false
        }
    }
}

@MainActor
class AppState: ObservableObject {
    // Method to clear all data
    func clearAllData() async {
        glucoseHistory = []
        currentGlucoseReading = nil
        print("Cleared data from memory - all API data is still in CoreData database")
    }
    
    // Method to reload data with current granularity setting
    func reloadWithCurrentGranularity() async {
        print("🔄 Reloading data with current granularity setting...")
        
        // Fetch all readings from CoreData
        let allReadings = coreDataManager.fetchAllGlucoseReadings()
        
        // Apply current granularity
        let granularityReadings = applyGranularity(to: allReadings)
        
        // Update the UI
        await MainActor.run {
            self.glucoseHistory = granularityReadings
            if !granularityReadings.isEmpty {
                self.currentGlucoseReading = granularityReadings.first
            }
        }
        
        print("✅ Reloaded \(granularityReadings.count) readings with granularity")
    }
    
    // Apply data granularity to readings
    private func applyGranularity(to readings: [GlucoseReading]) -> [GlucoseReading] {
        let granularity = UserDefaults.standard.integer(forKey: "dataGranularity")
        
        // If granularity is 0 (all readings) or only a single reading, return as is
        if granularity == 0 || readings.count <= 1 {
            return readings
        }
        
        print("🧪 Applying granularity of \(granularity) minute(s) to \(readings.count) readings")
        
        let calendar = Calendar.current
        var buckets: [String: [GlucoseReading]] = [:]
        
        // Group readings into time buckets based on granularity
        for reading in readings {
            // Create a time bucket key based on the granularity
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reading.timestamp)
            let minuteBucket = (components.minute ?? 0) / granularity * granularity
            
            // Create a unique key for this time bucket
            let bucketKey = String(format: "%04d-%02d-%02d %02d:%02d", 
                                   components.year ?? 0, 
                                   components.month ?? 0, 
                                   components.day ?? 0,
                                   components.hour ?? 0,
                                   minuteBucket)
            
            // Add reading to the appropriate bucket
            if buckets[bucketKey] == nil {
                buckets[bucketKey] = []
            }
            buckets[bucketKey]?.append(reading)
        }
        
        // For each bucket, compute the average reading
        var averagedReadings: [GlucoseReading] = []
        
        for (bucketKey, bucketReadings) in buckets {
            // If only one reading in bucket, use it directly
            if bucketReadings.count == 1 {
                averagedReadings.append(bucketReadings[0])
                continue
            }
            
            // Calculate average glucose value
            let totalValue = bucketReadings.reduce(0.0) { $0 + $1.value }
            let avgValue = totalValue / Double(bucketReadings.count)
            
            // Use middle timestamp of the bucket as representative timestamp
            let sortedTimestamps = bucketReadings.map { $0.timestamp }.sorted()
            let midTimestamp = sortedTimestamps[sortedTimestamps.count / 2]
            
            // Determine if readings are high or low based on majority
            let isHigh = bucketReadings.filter { $0.isHigh }.count > bucketReadings.count / 2
            let isLow = bucketReadings.filter { $0.isLow }.count > bucketReadings.count / 2
            
            // Use consistent unit from original readings
            let unit = bucketReadings[0].unit
            
            // Create a unique ID for this averaged reading
            let id = "avg-\(bucketKey)-\(UUID().uuidString)"
            
            // Create new averaged reading
            let avgReading = GlucoseReading(
                id: id,
                timestamp: midTimestamp,
                value: avgValue,
                unit: unit,
                isHigh: isHigh,
                isLow: isLow
            )
            
            averagedReadings.append(avgReading)
        }
        
        // Sort by timestamp (newest first - consistent with the rest of app)
        let sortedReadings = averagedReadings.sorted { $0.timestamp > $1.timestamp }
        
        print("🧪 Reduced to \(sortedReadings.count) averaged readings with granularity of \(granularity) minute(s)")
        
        return sortedReadings
    }
    
    // Refactor verifyCredentials to return a result with success/message
    struct CredentialResult {
        let success: Bool
        let message: String?
    }
    
    func verifyCredentials(username: String, password: String) async -> CredentialResult {
        do {
            let isAuthenticated = try await libreViewService.checkAuthentication()
            return CredentialResult(success: isAuthenticated, message: isAuthenticated ? nil : "Invalid credentials")
        } catch {
            return CredentialResult(success: false, message: error.localizedDescription)
        }
    }
    @Published var isAuthenticated = false
    @Published var currentGlucoseReading: GlucoseReading?
    @Published var glucoseHistory: [GlucoseReading] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedTab = 0 // Add selectedTab property
    
    // Current unit of measurement (mmol/L or mg/dL)
    var currentUnit: String {
        return UserDefaults.standard.string(forKey: "unit") ?? "mmol/L"
    }
    
    private let libreViewService = LibreViewService()
    private let coreDataManager = ProgrammaticCoreDataManager.shared
    
    // Always use real API data, never test data
    private let useTestData = false
    
    init() {
        // Load saved readings from CoreData
        loadSavedReadings()
        
        Task {
            do {
                _ = try await checkAuthentication()
            } catch {
                // Don't set the error here, as we'll handle credentials via onboarding
                isAuthenticated = false
            }
        }
    }
    
    // Load saved readings from database and calculate trends
    private func loadSavedReadings() {
        print("🔃 Loading saved readings from CoreData...")
        var savedReadings = coreDataManager.fetchAllGlucoseReadings()
        
        print("📊 CRITICAL: Loaded \(savedReadings.count) readings from CoreData at startup")
        
        // Check date range to debug
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if !savedReadings.isEmpty {
            // Find earliest and latest date
            if let earliest = savedReadings.map({ $0.timestamp }).min(),
               let latest = savedReadings.map({ $0.timestamp }).max() {
                print("📅 CRITICAL DATA RANGE: \(dateFormatter.string(from: earliest)) to \(dateFormatter.string(from: latest))")
                
                // Count unique days
                let calendar = Calendar.current
                let uniqueDays = Set(savedReadings.map { calendar.startOfDay(for: $0.timestamp) })
                print("📊 CRITICAL: Data spans \(uniqueDays.count) unique days")
                
                // Print days
                print("📆 Available days:")
                let sortedDays = uniqueDays.sorted()
                for (index, day) in sortedDays.enumerated() {
                    let dayStr = dateFormatter.string(from: day).prefix(10)
                    let countForDay = savedReadings.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.count
                    print("  • \(dayStr): \(countForDay) readings")
                    
                    // Limit output to first 5 days
                    if index >= 4 && sortedDays.count > 5 {
                        print("  • ... and \(sortedDays.count - 5) more days")
                        break
                    }
                }
            }
        }
        
        // Print date range of the data
        if !savedReadings.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            if let earliest = savedReadings.map({ $0.timestamp }).min(),
               let latest = savedReadings.map({ $0.timestamp }).max() {
                print("📅 DEBUG: Date range of data: \(dateFormatter.string(from: earliest)) to \(dateFormatter.string(from: latest))")
            }
            
            // Check unique days
            let calendar = Calendar.current
            let uniqueDays = Set(savedReadings.map { calendar.startOfDay(for: $0.timestamp) })
            print("📆 DEBUG: Data covers \(uniqueDays.count) unique days")
        }
        
        if !savedReadings.isEmpty {
            // Sort by timestamp, most recent first
            savedReadings.sort { $0.timestamp > $1.timestamp }
            
            // Calculate trends for each reading using previous readings
            var enhancedReadings = [GlucoseReading]()
            
            for (index, reading) in savedReadings.enumerated() {
                // Deep copy the reading
                var updatedReading = reading
                
                // For each reading, consider all readings that came before it
                let previousReadings = Array(savedReadings.suffix(from: index + 1))
                
                // Use our enhanced trend calculation algorithm
                let calculatedTrend = GlucoseReading.calculateTrend(
                    currentReading: reading,
                    previousReadings: previousReadings
                )
                
                // Need to hack in the trend since it's calculated on-the-fly in the getter
                if calculatedTrend == .rising {
                    updatedReading = GlucoseReading(
                        id: reading.id,
                        timestamp: reading.timestamp,
                        value: reading.value,
                        unit: reading.unit,
                        isHigh: true,   // Hack to set trend to rising
                        isLow: false
                    )
                } else if calculatedTrend == .falling {
                    updatedReading = GlucoseReading(
                        id: reading.id,
                        timestamp: reading.timestamp,
                        value: reading.value,
                        unit: reading.unit,
                        isHigh: false,
                        isLow: true     // Hack to set trend to falling
                    )
                } else {
                    // Keep stable or not computable as is
                    updatedReading = reading
                }
                
                enhancedReadings.append(updatedReading)
            }
            
            // Apply granularity to reduce number of data points if configured
            let granularityReadings = applyGranularity(to: enhancedReadings)
            
            self.glucoseHistory = granularityReadings
            self.currentGlucoseReading = granularityReadings.first
            print("📂 Loaded \(granularityReadings.count) glucose readings with calculated trends and applied granularity")
        }
    }
    
    func checkAuthentication() async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            isAuthenticated = try await libreViewService.checkAuthentication()
            if isAuthenticated {
                await fetchLatestReadings()
            }
            return isAuthenticated
        } catch {
            // Never use test data - always rely on real API authentication
            isAuthenticated = false
            throw error
        }
    }
    
    func fetchLatestReadings() async {
        do {
            // Always fetch real glucose data from the API
            print("🔄 Fetching real glucose data from LibreView API...")
            let readings = try await libreViewService.fetchGlucoseData()
            
            // Debug API response
            print("✅ API returned \(readings.count) readings")
            
            // Sort to ensure most recent first
            let sortedReadings = readings.sorted { $0.timestamp > $1.timestamp }
            
            // Check timestamp distribution
            let calendar = Calendar.current
            let uniqueDates = Set(sortedReadings.map { calendar.startOfDay(for: $0.timestamp) })
            print("📊 Readings span \(uniqueDates.count) unique days")
            
            // Get date range of data
            if let earliest = sortedReadings.last?.timestamp, let latest = sortedReadings.first?.timestamp {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                let earliestStr = dateFormatter.string(from: earliest)
                let latestStr = dateFormatter.string(from: latest)
                
                let daysBetween = calendar.dateComponents([.day], from: earliest, to: latest).day ?? 0
                print("📅 Date range: \(earliestStr) to \(latestStr) (\(daysBetween) days)")
                
                // List all unique days in the data
                let allDays = uniqueDates.sorted()
                print("📆 Data available for these days:")
                
                var dayCount = 0
                for day in allDays {
                    let dayStr = dateFormatter.string(from: day)
                    let countForDay = sortedReadings.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.count
                    print("  • \(dayStr): \(countForDay) readings")
                    dayCount += 1
                    
                    // Limit output to avoid flooding the console
                    if dayCount >= 10 && allDays.count > 12 {
                        print("  • ... and \(allDays.count - 10) more days")
                        break
                    }
                }
            }
            
            // Log some sample readings
            print("📋 Sample of readings:")
            for (index, reading) in sortedReadings.prefix(5).enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timestampStr = dateFormatter.string(from: reading.timestamp)
                print("  [\(index)] \(reading.value) \(reading.unit) at \(timestampStr)")
            }
            
            // Calculate trends for readings
            var enhancedReadings = [GlucoseReading]()
            
            for (index, reading) in sortedReadings.enumerated() {
                // Deep copy the reading
                var updatedReading = reading
                
                // For each reading, consider all readings that came before it
                let previousReadings = Array(sortedReadings.suffix(from: index + 1))
                
                // Use our enhanced trend calculation algorithm
                let calculatedTrend = GlucoseReading.calculateTrend(
                    currentReading: reading,
                    previousReadings: previousReadings
                )
                
                // Need to hack in the trend since it's calculated on-the-fly in the getter
                if calculatedTrend == .rising {
                    updatedReading = GlucoseReading(
                        id: reading.id,
                        timestamp: reading.timestamp,
                        value: reading.value,
                        unit: reading.unit,
                        isHigh: true,   // Hack to set trend to rising
                        isLow: false
                    )
                } else if calculatedTrend == .falling {
                    updatedReading = GlucoseReading(
                        id: reading.id,
                        timestamp: reading.timestamp,
                        value: reading.value,
                        unit: reading.unit,
                        isHigh: false,
                        isLow: true     // Hack to set trend to falling
                    )
                } else {
                    // Keep stable or not computable as is
                    updatedReading = reading
                }
                
                enhancedReadings.append(updatedReading)
            }
            
            // Save enhanced readings to CoreData database
            coreDataManager.saveGlucoseReadings(enhancedReadings)
            print("💾 Saved \(enhancedReadings.count) readings with calculated trends to database")
            
            // CRITICAL FIX: Load ALL readings from CoreData instead of just using the ones from API
            // This ensures we see ALL historical data, not just what the API returned this time
            let allReadings = coreDataManager.fetchAllGlucoseReadings()
            print("⚠️ CRITICAL: Loaded \(allReadings.count) total readings from CoreData after saving new data")
            
            // Apply granularity setting to reduce data points if configured
            let granularityReadings = applyGranularity(to: allReadings)
            
            self.glucoseHistory = granularityReadings
            self.currentGlucoseReading = granularityReadings.first
            
            print("📊 Applied granularity: Reduced from \(allReadings.count) to \(granularityReadings.count) readings")
            
            print("📱 Updated readings with calculated trends")
            
            if let reading = currentGlucoseReading {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("📱 Current glucose: \(reading.value) \(reading.unit) at \(dateFormatter.string(from: reading.timestamp))")
            }
        } catch {
            print("❌ Error fetching glucose data: \(error.localizedDescription)")
            self.error = error
            
            // Never use test data - always rely on real API data
            // Still keep existing CoreData readings in memory
        }
    }
    
    // No test data generation function - always using real API data only
} 