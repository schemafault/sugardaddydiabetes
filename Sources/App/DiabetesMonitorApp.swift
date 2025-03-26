import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // Quit if onboarding is closed
        NSApplication.shared.terminate(nil)
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
                    
                    let hasCredentials = UserDefaults.standard.string(forKey: "username") != nil &&
                                         UserDefaults.standard.string(forKey: "password") != nil
                    
                    // Configure NSWindow for better text field behavior
                    configureWindows()
                    
                    // Show native login window if needed
                    if !hasCredentials {
                        showNativeLoginWindow()
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
        
        MenuBarExtra("Diabetes Monitor", systemImage: "heart.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
    
    private func showNativeLoginWindow() {
        // Create and show the login window
        let windowController = LoginWindowController()
        
        // Set callback for when credentials are entered
        windowController.onCredentialsEntered = { username, password in
            // Test credentials
            Task {
                do {
                    // Temporarily set the credentials
                    UserDefaults.standard.set(username, forKey: "username")
                    UserDefaults.standard.set(password, forKey: "password")
                    
                    // Create a service to test the credentials
                    let service = LibreViewService()
                    let isValid = try await service.checkAuthentication()
                    
                    await MainActor.run {
                        if isValid {
                            // If valid, close login window
                            windowController.close()
                            loginWindowController = nil
                        } else {
                            // If not valid, show error
                            UserDefaults.standard.removeObject(forKey: "username")
                            UserDefaults.standard.removeObject(forKey: "password")
                            windowController.showError("Invalid username or password")
                        }
                    }
                } catch {
                    await MainActor.run {
                        // If error, show error
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
    @Published var isAuthenticated = false
    @Published var currentGlucoseReading: GlucoseReading?
    @Published var glucoseHistory: [GlucoseReading] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedTab = 0 // Add selectedTab property
    
    private let libreViewService = LibreViewService()
    
    // Set to false to always use real API data
    private let useTestData = false
    
    init() {
        Task {
            do {
                _ = try await checkAuthentication()
            } catch {
                // Don't set the error here, as we'll handle credentials via onboarding
                isAuthenticated = false
            }
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
            if useTestData {
                // Create test data with realistic timestamps if authentication fails
                isAuthenticated = true
                generateTestData()
                return true
            }
            isAuthenticated = false
            throw error
        }
    }
    
    func fetchLatestReadings() async {
        do {
            if useTestData {
                // Use test data instead of calling the API
                generateTestData()
                return
            }
            
            print("🔄 Fetching glucose data from LibreView API...")
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
            
            glucoseHistory = sortedReadings
            currentGlucoseReading = sortedReadings.first
            
            if let reading = currentGlucoseReading {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("📱 Current glucose: \(reading.value) \(reading.unit) at \(dateFormatter.string(from: reading.timestamp))")
            }
        } catch {
            print("❌ Error fetching glucose data: \(error.localizedDescription)")
            self.error = error
            
            if useTestData {
                // Create test data if API fetch fails
                generateTestData()
            }
        }
    }
    
    // Create test data with varied timestamps for proper time range filtering
    private func generateTestData() {
        // Create mock readings spanning multiple days
        var mockReadings = [GlucoseReading]()
        
        // Today
        let today = Date()
        let todayValues = [5.6, 6.2, 7.1, 8.3, 7.5, 5.9, 6.4]
        
        // Yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let yesterdayValues = [4.5, 5.7, 6.8, 7.9, 6.2, 5.1, 5.8]
        
        // Two days ago
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        let twoDaysAgoValues = [4.9, 6.1, 7.2, 8.5, 7.7, 6.3, 5.5]
        
        // Last week
        let lastWeek = Calendar.current.date(byAdding: .day, value: -6, to: today)!
        let lastWeekValues = [5.2, 5.8, 6.7, 7.4, 6.8, 5.7, 6.1]
        
        // Create readings for today (every 2 hours)
        for (index, value) in todayValues.enumerated() {
            let timestamp = Calendar.current.date(byAdding: .hour, value: index * 2, to: today)!
            let id = UUID().uuidString
            let reading = GlucoseReading(id: id, timestamp: timestamp, value: value, unit: "mmol/L", isHigh: false, isLow: false)
            mockReadings.append(reading)
        }
        
        // Create readings for yesterday (every 2 hours)
        for (index, value) in yesterdayValues.enumerated() {
            let timestamp = Calendar.current.date(byAdding: .hour, value: index * 2, to: yesterday)!
            let id = UUID().uuidString
            let reading = GlucoseReading(id: id, timestamp: timestamp, value: value, unit: "mmol/L", isHigh: false, isLow: false)
            mockReadings.append(reading)
        }
        
        // Create readings for two days ago (every 3 hours)
        for (index, value) in twoDaysAgoValues.enumerated() {
            let timestamp = Calendar.current.date(byAdding: .hour, value: index * 3, to: twoDaysAgo)!
            let id = UUID().uuidString
            let reading = GlucoseReading(id: id, timestamp: timestamp, value: value, unit: "mmol/L", isHigh: false, isLow: false)
            mockReadings.append(reading)
        }
        
        // Create readings for last week (every 3 hours)
        for (index, value) in lastWeekValues.enumerated() {
            let timestamp = Calendar.current.date(byAdding: .hour, value: index * 3, to: lastWeek)!
            let id = UUID().uuidString
            let reading = GlucoseReading(id: id, timestamp: timestamp, value: value, unit: "mmol/L", isHigh: false, isLow: false)
            mockReadings.append(reading)
        }
        
        // Sort readings by timestamp, most recent first
        mockReadings.sort { $0.timestamp > $1.timestamp }
        
        // Print debug info about the test data
        print("Generated \(mockReadings.count) test readings spanning multiple days")
        
        if let earliest = mockReadings.map({ $0.timestamp }).min(),
           let latest = mockReadings.map({ $0.timestamp }).max() {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: earliest, to: latest).day ?? 0
            print("Test data spans \(days) days from \(earliest) to \(latest)")
            
            // Check unique days
            let uniqueDays = Set(mockReadings.map { calendar.startOfDay(for: $0.timestamp) })
            print("Test data covers \(uniqueDays.count) unique days")
        }
        
        // Update the app state
        glucoseHistory = mockReadings
        currentGlucoseReading = mockReadings.first
        
        print("Test data loaded. Run filtering tests with different time ranges.")
    }
} 