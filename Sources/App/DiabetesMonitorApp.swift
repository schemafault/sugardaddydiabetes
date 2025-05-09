import SwiftUI
import AppKit
import CoreData
import Security // Required for keychain access

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var updateTimer: Timer?
    var menuBarCleanupTimer: Timer? // Timer for menu bar cleanup
    
    // Add property to track recently closed windows
    private var recentlyClosedWindows = Set<String>()
    private var lastCleanupTime: Date = Date()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // CRITICAL FIX: Check for and terminate other instances of the app to prevent multiple menu bar icons
        let runningApps = NSWorkspace.shared.runningApplications
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let currentPID = ProcessInfo.processInfo.processIdentifier
        print("🔍 Current app process identifier: \(currentPID)")
        print("🔍 Current app bundle ID: \(bundleID)")
        
        // Log existing menu bar windows before any changes
        print("🔍 DEBUG: Menu bar windows at app launch:")
        let menuBarWindows = NSApp.windows.filter { window in
            let windowClass = NSStringFromClass(type(of: window))
            return windowClass.contains("MenuBarExtra") || windowClass.contains("StatusBar")
        }
        print("🔢 Found \(menuBarWindows.count) menu bar windows at launch")
        menuBarWindows.forEach { window in
            let windowClass = NSStringFromClass(type(of: window))
            print("  - Title: \(window.title), Class: \(windowClass)")
        }
        
        let matchingApps = runningApps.filter { 
            $0.bundleIdentifier == bundleID && $0.processIdentifier != currentPID 
        }
        
        print("🔍 Found \(matchingApps.count) other instances of the app")
        matchingApps.forEach { app in
            print("  - PID: \(app.processIdentifier), isActive: \(app.isActive)")
        }
        
        // CRITICAL FIX: Determine if this is the primary instance
        let lowestOtherPID: UInt32 = matchingApps.map({ UInt32($0.processIdentifier) }).min() ?? UInt32.max
        let isPrimary = matchingApps.isEmpty || UInt32(currentPID) < lowestOtherPID
        
        if !isPrimary {
            print("⚠️ This is NOT the primary instance. Terminating self to prevent multiple menu bar icons.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        
        print("✅ This is the primary instance. Continuing startup.")
        
        // If there are other instances running, terminate them
        for app in matchingApps {
            print("🔍 Terminating other instance with PID: \(app.processIdentifier)")
            app.terminate()
        }
        
        // IMPORTANT: Set up distributed notification to detect and handle multiple launches
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAppLaunch),
            name: NSNotification.Name("com.macsugardaddy.diabetesmonitor.launched"),
            object: nil
        )
        
        // Notify that this instance has launched
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔍 Broadcasting app launch notification")
            DistributedNotificationCenter.default().post(
                name: NSNotification.Name("com.macsugardaddy.diabetesmonitor.launched"),
                object: String(ProcessInfo.processInfo.processIdentifier)
            )
        }
        
        // Initialize CoreData with programmatic model
        _ = ProgrammaticCoreDataManager.shared
        
        // Configure update timer
        setupUpdateTimer()
        
        // Handle Termination
        NSApplication.shared.registerForRemoteNotifications()
        
        print("App did finish launching")
        
        // CRITICAL FIX: Set proper activation policy and activate immediately
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Process events to ensure windows are created
        NSApp.finishLaunching()
        
        // CRITICAL FIX: Make main window visible immediately
        for window in NSApp.windows where window.title.contains("Diabetes") {
            window.makeKeyAndOrderFront(nil)
            print("Making window visible immediately: \(window.title)")
        }
        
        // Register for URL handling
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // CRITICAL FIX: Clean up CoreData database
        Task {
            await cleanupCoreDataDatabase()
        }
        
        // CRITICAL FIX: Ensure menu bar extra is properly initialized immediately
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Log available windows for debugging
        print("Available windows after launch:")
        NSApp.windows.forEach { window in
            print("  - \(window.title)")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Show login window if no credentials are stored
            let username = UserDefaults.standard.string(forKey: "username")
            let password = UserDefaults.standard.string(forKey: "password")
            
            if username == nil || password == nil {
                self.showNativeLoginWindow()
            } else {
                // ... existing code ...
            }
        }
        
        // Set up a timer to periodically check for and clean up duplicate menu bar items
        setupMenuBarCleanupTimer()
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
        
        // CRITICAL FIX: Use weak self to prevent retain cycles
        DispatchQueue.main.async {
            // Count SwiftUI windows to avoid creating duplicates
            let hasSwiftUIWindows = NSApp.windows.contains { window in
                let windowClass = NSStringFromClass(type(of: window))
                return windowClass.contains("SwiftUI") || windowClass.contains("AppKit")
            }
            
            // Just make existing windows visible rather than creating new ones
            if hasSwiftUIWindows {
                print("SwiftUI windows found, making them visible")
                
                // Make existing windows visible
                for window in NSApp.windows {
                    // Skip menu bar windows
                    if NSStringFromClass(type(of: window)).contains("StatusBarWindow") ||
                       NSStringFromClass(type(of: window)).contains("MenuBarExtra") {
                        continue
                    }
                    
                    window.makeKeyAndOrderFront(nil)
                    print("Made window visible: \(window.title)")
                }
                
                // Ensure activation policy is correct
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                }
                
                return
            }
            
            // If no SwiftUI windows but other main windows exist, just make them visible
            let hasMainWindows = NSApp.windows.contains { window in
                !NSStringFromClass(type(of: window)).contains("StatusBarWindow") &&
                !NSStringFromClass(type(of: window)).contains("MenuBarExtra")
            }
            
            if hasMainWindows {
                // Just find the main window and make it visible
                for window in NSApp.windows where !NSStringFromClass(type(of: window)).contains("StatusBarWindow") {
                    window.makeKeyAndOrderFront(nil)
                    print("Making main window visible in didBecomeActive: \(window.title)")
                    return
                }
            }
            
            // If no main window found, try to make any key window visible
            if let keyWindow = NSApp.keyWindow, !keyWindow.isVisible {
                print("Making key window visible as fallback")
                keyWindow.makeKeyAndOrderFront(nil)
                return
            }
            
            // Ensure activation policy is correct
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            
            // CRITICAL FIX: Only create a new window as last resort if no windows exist
            if NSApp.windows.isEmpty {
                print("⚠️ No windows found at all in didBecomeActive, creating a new one as last resort")
                
                // Create a new window
                let newWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                newWindow.title = "Diabetes Monitor"
                newWindow.center()
                newWindow.makeKeyAndOrderFront(nil)
                
                // Add a simple view to the window
                let contentView = NSView(frame: newWindow.contentView!.bounds)
                contentView.autoresizingMask = [.width, .height]
                newWindow.contentView = contentView
                
                print("Created new window in didBecomeActive: \(newWindow.title)")
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
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🔚 Application will terminate - PID: \(ProcessInfo.processInfo.processIdentifier)")
        // Clean up any resources
        updateTimer?.invalidate()
        menuBarCleanupTimer?.invalidate() // Invalidate the menu bar cleanup timer
        
        // Log menu bar windows before termination
        let menuBarWindows = NSApp.windows.filter { window in
            let windowClass = NSStringFromClass(type(of: window))
            return windowClass.contains("MenuBarExtra") || windowClass.contains("StatusBar")
        }
        print("🔢 Found \(menuBarWindows.count) menu bar windows on termination")
        
        // Ensure CoreData is saved on exit
        ProgrammaticCoreDataManager.shared.saveContext()
    }
    
    // CRITICAL FIX: Add method to clean up CoreData database
    private func cleanupCoreDataDatabase() async {
        print("🧹 Starting CoreData database cleanup...")
        
        let coreDataManager = ProgrammaticCoreDataManager.shared
        
        // Fetch all readings
        let allReadings = coreDataManager.fetchAllGlucoseReadings()
        print("📊 Found \(allReadings.count) total readings in database")
        
        // Check for duplicates
        let uniqueIds = Set(allReadings.map { $0.id })
        if uniqueIds.count < allReadings.count {
            print("⚠️ WARNING: Found \(allReadings.count - uniqueIds.count) duplicate readings!")
            
            // Remove duplicates by ID
            let uniqueReadings = Array(Set(allReadings))
            print("🧹 Removed \(allReadings.count - uniqueIds.count) duplicate readings")
            
            // Save the deduplicated readings back to CoreData
            coreDataManager.saveGlucoseReadings(uniqueReadings)
            print("💾 Saved deduplicated readings to database")
            
            // Verify the cleanup
            let afterCleanup = coreDataManager.fetchAllGlucoseReadings()
            print("✅ Database cleanup complete. Now contains \(afterCleanup.count) unique readings")
        } else {
            print("✅ No duplicate readings found in database")
        }
    }
    
    // Add showNativeLoginWindow method
    private func showNativeLoginWindow() {
        print("🪟 Creating and showing login window")
        
        // Create and show the login window
        let windowController = LoginWindowController()
        
        // Set callback for when credentials are entered
        windowController.onCredentialsEntered = { [weak windowController] username, password in
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
                    
                    // Capture weak reference to avoid Swift 6 warnings
                    let weakWindowController = windowController
                    await MainActor.run {
                        if isValid {
                            // If valid, close login window
                            print("✅ Credentials verified - closing login window")
                            weakWindowController?.stopLoading()
                            weakWindowController?.close()
                        } else {
                            // If not valid, show error and clear credentials
                            UserDefaults.standard.removeObject(forKey: "username")
                            UserDefaults.standard.removeObject(forKey: "password")
                            weakWindowController?.showError("Invalid username or password")
                        }
                    }
                } catch {
                    // Capture weak reference to avoid Swift 6 warnings
                    let weakWindowController = windowController
                    await MainActor.run {
                        // If error, show error and clear credentials
                        print("❌ Authentication error: \(error.localizedDescription)")
                        UserDefaults.standard.removeObject(forKey: "username")
                        UserDefaults.standard.removeObject(forKey: "password")
                        weakWindowController?.showError("Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Show the window
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func handleAppLaunch(_ notification: Notification) {
        // Check if this is a notification from our own process
        if let senderPID = notification.object as? String,
           senderPID != String(ProcessInfo.processInfo.processIdentifier) {
            print("🔍 Received launch notification from another instance (PID: \(senderPID))")
            
            // This is a newer instance, so terminate this one
            if let otherPID = Int(senderPID), otherPID > ProcessInfo.processInfo.processIdentifier {
                print("🔍 Other instance has higher PID, terminating self")
                NSApplication.shared.terminate(nil)
            } else {
                print("🔍 This instance has higher PID, continuing")
            }
        }
    }
    
    @MainActor
    func cleanupDuplicateMenuBarItems() {
        print("🧹 AppDelegate checking for duplicate menu bar items...")
        
        // Reset recently closed windows if it's been a while since last cleanup
        let now = Date()
        if now.timeIntervalSince(lastCleanupTime) > 5.0 {
            recentlyClosedWindows.removeAll()
        }
        lastCleanupTime = now
        
        // First get status items (the actual menu bar icons)
        let statusItems = NSApp.windows.filter { window in
            NSStringFromClass(type(of: window)).contains("StatusBarWindow") ||
            NSStringFromClass(type(of: window)).contains("StatusItem")
        }
        
        // Then get menu windows (the dropdown menus)
        let menuWindows = NSApp.windows.filter { window in
            NSStringFromClass(type(of: window)).contains("MenuBarExtra") ||
            NSStringFromClass(type(of: window)).contains("MenuBar")
        }
        
        print("🧹 Found \(statusItems.count) status items and \(menuWindows.count) menu windows")
        
        // Access showMenuBar directly from the DiabetesMonitorApp instance if possible
        guard let appState = appState else {
            print("⚠️ AppState not available - cannot determine if menu bar should be shown")
            return
        }
        
        // Skip cleanup if a menu window is currently visible to prevent closing active menus
        let visibleMenuWindows = menuWindows.filter { $0.isVisible }
        if visibleMenuWindows.count > 0 {
            print("🧹 Skipping cleanup - menu is currently visible")
            return
        }
        
        // If we're closing a menu bar that was just opened, it will cause the immediate closing issue
        // Add a check to prevent closing windows that were just created
        if statusItems.count == 2 {
            // Get window identifiers
            let windowIds = statusItems.map { NSStringFromClass(type(of: $0)) + String(describing: $0.hashValue) }
            
            // Check if we've closed these windows recently
            let alreadyClosed = windowIds.allSatisfy { recentlyClosedWindows.contains($0) }
            if alreadyClosed {
                print("🧹 Skipping cleanup - these windows were recently processed")
                return
            }
        }
        
        // Check if showMenuBar is true (using the property from the App instance)
        if !appState.showMenuBar {
            // If we shouldn't show the menu bar at all, close all status items except one to avoid app crash
            print("🧹 We should not show any menu bar - hiding all status items")
            
            // Must keep at least one status item to avoid app crash, but make it invisible
            if let firstItem = statusItems.first, statusItems.count > 0 {
                firstItem.alphaValue = 0.0
                print("🧹 Made first status item invisible instead of closing it")
                
                // Close any additional status items
                for window in statusItems.dropFirst() {
                    let windowId = NSStringFromClass(type(of: window)) + String(describing: window.hashValue)
                    if !recentlyClosedWindows.contains(windowId) {
                        print("🧹 Closing extra status item: \(window)")
                        recentlyClosedWindows.insert(windowId)
                        window.close()
                    }
                }
            }
            
            // Close all menu windows
            for window in menuWindows {
                let windowId = NSStringFromClass(type(of: window)) + String(describing: window.hashValue)
                if !recentlyClosedWindows.contains(windowId) {
                    print("🧹 Closing menu window: \(window)")
                    recentlyClosedWindows.insert(windowId)
                    window.close()
                }
            }
        } else if statusItems.count > 1 {
            // If there are duplicate status items, keep only one visible
            print("🧹 Found \(statusItems.count) status items - keeping only one")
            
            // Make the first item visible
            if let firstItem = statusItems.first {
                firstItem.alphaValue = 1.0
            }
            
            // Close extras 
            for window in statusItems.dropFirst() {
                let windowId = NSStringFromClass(type(of: window)) + String(describing: window.hashValue)
                if !recentlyClosedWindows.contains(windowId) {
                    print("🧹 Closing duplicate status item: \(window)")
                    recentlyClosedWindows.insert(windowId)
                    window.close()
                }
            }
            
            // Don't close any menu windows - they'll be managed by the system
        } else {
            // Ensure the status item is visible
            if let firstItem = statusItems.first {
                firstItem.alphaValue = 1.0
            }
            
            print("✅ Menu bar state is good: \(statusItems.count) status item(s) and shouldShowMenuBar=\(appState.showMenuBar)")
        }
    }
    
    @MainActor
    func setupMenuBarCleanupTimer() {
        // Check for duplicate menu bar items every 20 seconds
        menuBarCleanupTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupDuplicateMenuBarItems()
            }
        }
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
    
    // We will use the AppState object directly for coreDataManager access
    
    var body: some Scene {
        WindowGroup("Diabetes Monitor", id: "main") {
            ContentView(selectedTab: $appState.selectedTab)
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Set appState in AppDelegate
                    appDelegate.appState = appState
                    
                    // CRITICAL FIX: Show UI immediately
                    NSApp.activate(ignoringOtherApps: true)
                    
                    // Debug what's in the defaults
                    let username = UserDefaults.standard.string(forKey: "username")
                    let password = UserDefaults.standard.string(forKey: "password")
                    print("DEBUG UserDefaults - username: \(username != nil ? "found" : "missing"), password: \(password != nil ? "found" : "missing")")
                    
                    let hasCredentials = username != nil && password != nil
                    
                    print("🔐 Checking for existing credentials: \(hasCredentials ? "Found" : "Not found")")
                    
                    // Configure windows without excessive activation
                    configureWindows()
                    
                    // Set show menu bar based on primary instance check
                    if self.isPrimaryInstance() {
                        appState.showMenuBar = true
                        print("🔍 This is the primary instance - showing menu bar")
                        
                        // Clean up any duplicate menu bar items
                        appDelegate.cleanupDuplicateMenuBarItems()
                    } else {
                        appState.showMenuBar = false
                        print("🔍 This is a secondary instance - hiding menu bar")
                    }
                    
                    // Show login window ONLY if there are no credentials
                    if !hasCredentials {
                        print("📱 No credentials found - showing login window")
                        showNativeLoginWindow()
                    } else {
                        print("🔑 Using existing credentials - skipping login screen")
                        
                        // If credentials exist, fetch data in background
                        Task {
                            await appState.fetchLatestReadings()
                        }
                    }
                    
                    // CRITICAL FIX: Force window activation immediately
                    for window in NSApp.windows where window.title.contains("Diabetes") {
                        window.makeKeyAndOrderFront(nil)
                        print("Forcing window activation immediately: \(window.title)")
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
        
        // CRITICAL FIX: Create MenuBarExtra with isInserted binding to better handle multiple instances
        MenuBarExtra(isInserted: .constant(true)) {
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 280)
                .onAppear {
                    print("📊 Menu bar view appeared")
                    
                    // Log all available windows for debugging
                    print("🔍 DEBUG: All windows after menu bar appear:")
                    NSApp.windows.enumerated().forEach { index, window in
                        let windowClass = NSStringFromClass(type(of: window))
                        print("  \(index): \(window.title) - Class: \(windowClass)")
                    }
                    
                    // Count menu bar extras
                    let menuBarCount = NSApp.windows.filter { window in
                        let windowClass = NSStringFromClass(type(of: window))
                        return windowClass.contains("MenuBarExtra") || windowClass.contains("StatusBar")
                    }.count
                    
                    print("🔢 DEBUG: Found \(menuBarCount) menu bar windows")
                    
                    // Introduce a longer delay for Xcode runs to ensure proper cleanup
                    // Only perform cleanup after a delay to allow for scene setup
                    let delay: TimeInterval = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]?.contains("com.apple.dt.Xcode") ?? false ? 2.0 : 0.5
                    print("⏱️ Using cleanup delay of \(delay) seconds")
                    
                    // If more than one or shouldn't show menu bar, close this one
                    if menuBarCount > 1 || !appState.showMenuBar {
                        // Defer cleanup to ensure window is fully created
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            print("⏱️ Performing cleanup after delay")
                            appDelegate.cleanupDuplicateMenuBarItems()
                        }
                    }
                }
        } label: {
            if let reading = appState.currentGlucoseReading {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .imageScale(.medium)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(reading.rangeStatus.color)
                    
                    Text(String(format: "%.1f", reading.displayValue))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(reading.rangeStatus.color)
                }
                .onAppear {
                    print("❤️ Menu bar icon appeared with glucose value")
                }
            } else {
                Image(systemName: "heart.fill")
                    .imageScale(.medium)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.gray)
                    .onAppear {
                        print("❤️ Menu bar icon appeared (no glucose data)")
                    }
            }
        }
    }
    
    private func showNativeLoginWindow() {
        print("🪟 Creating and showing login window")
        
        // Create and show the login window
        let windowController = LoginWindowController()
        
        // Set callback for when credentials are entered
        windowController.onCredentialsEntered = { [weak windowController] username, password in
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
                    
                    // Capture weak reference to avoid Swift 6 warnings
                    let weakWindowController = windowController
                    await MainActor.run {
                        if isValid {
                            // If valid, close login window
                            print("✅ Credentials verified - closing login window")
                            weakWindowController?.stopLoading()
                            weakWindowController?.close()
                        } else {
                            // If not valid, show error and clear credentials
                            UserDefaults.standard.removeObject(forKey: "username")
                            UserDefaults.standard.removeObject(forKey: "password")
                            weakWindowController?.showError("Invalid username or password")
                        }
                    }
                } catch {
                    // Capture weak reference to avoid Swift 6 warnings
                    let weakWindowController = windowController
                    await MainActor.run {
                        // If error, show error and clear credentials
                        print("❌ Authentication error: \(error.localizedDescription)")
                        UserDefaults.standard.removeObject(forKey: "username")
                        UserDefaults.standard.removeObject(forKey: "password")
                        weakWindowController?.showError("Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Show the window
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }
    
    private func configureWindows() {
        print("🪟 Configuring windows...")
        
        // Set proper activation policy and activate the app
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Add a small delay to ensure SwiftUI has time to create windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Log available windows for debugging
            print("Available windows after configuration delay:")
            NSApp.windows.forEach { window in
                print("  - \(window.title)")
            }
            
            // Check if we have SwiftUI-managed windows
            let hasSwiftUIWindows = NSApp.windows.contains { window in
                let windowClass = NSStringFromClass(type(of: window))
                return windowClass.contains("SwiftUI") || windowClass.contains("AppKit")
            }
            
            // Only configure windows if we have any to work with
            if !hasSwiftUIWindows {
                // Configure any existing windows
                for window in NSApplication.shared.windows {
                    // Skip menu bar windows
                    if NSStringFromClass(type(of: window)).contains("StatusBarWindow") ||
                       NSStringFromClass(type(of: window)).contains("MenuBarExtra") {
                        continue
                    }
                    
                    print("Configuring window: \(window.title)")
                    
                    // Apply full standard window style mask with all controls and resizing
                    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                    
                    // Set min size constraints
                    window.minSize = NSSize(width: 800, height: 600)
                    window.setContentSize(NSSize(width: 900, height: 700))
                    
                    // Make the window visible
                    window.makeKeyAndOrderFront(nil)
                    print("Made window visible: \(window.title)")
                }
                
                // CRITICAL FIX: Only create a new window if absolutely necessary
                let hasMainWindows = NSApplication.shared.windows.contains { window in
                    !NSStringFromClass(type(of: window)).contains("StatusBarWindow") &&
                    !NSStringFromClass(type(of: window)).contains("MenuBarExtra")
                }
                
                // Create a window only if we have NO windows at all
                if !hasMainWindows {
                    print("⚠️ No windows found at all, creating a new one")
                    
                    // Create a new window
                    let newWindow = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                        backing: .buffered,
                        defer: false
                    )
                    newWindow.title = "Diabetes Monitor"
                    newWindow.center()
                    newWindow.makeKeyAndOrderFront(nil)
                    
                    // Add a simple view to the window
                    let contentView = NSView(frame: newWindow.contentView!.bounds)
                    contentView.autoresizingMask = [.width, .height]
                    newWindow.contentView = contentView
                    
                    print("Created new window: \(newWindow.title)")
                }
            } else {
                print("✅ SwiftUI-managed windows found, skipping manual window creation")
            }
        }
    }
    
    // Helper method to determine if this is the primary app instance
    private func isPrimaryInstance() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        
        print("🔍 DEBUG isPrimaryInstance: Checking PID \(myPID) with bundle \(bundleID)")
        
        // Find all instances of our app
        let matchingApps = runningApps.filter { $0.bundleIdentifier == bundleID }
        
        print("🔍 DEBUG isPrimaryInstance: Found \(matchingApps.count) matching apps")
        matchingApps.forEach { app in
            print("  - PID: \(app.processIdentifier), isActive: \(app.isActive)")
        }
        
        // This is primary if it's the only instance or has the lowest PID
        if matchingApps.count <= 1 {
            print("✅ DEBUG isPrimaryInstance: Only one instance found - this is primary")
            return true
        } else {
            // Find the app with the lowest PID
            let lowestPID: UInt32 = matchingApps.map { UInt32($0.processIdentifier) }.min() ?? UInt32.max
            let isPrimary = UInt32(myPID) == lowestPID
            print("\(isPrimary ? "✅" : "❌") DEBUG isPrimaryInstance: Multiple instances found - this \(isPrimary ? "IS" : "is NOT") primary (PID \(myPID) vs lowest \(lowestPID))")
            return isPrimary
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
    // Menu bar visibility control
    @Published var showMenuBar: Bool = true
    
    // CoreData manager
    let coreDataManager: ProgrammaticCoreDataManager
    
    // LibreView service for API access
    let libreViewService = LibreViewService()
    
    // Method to clear all data
    func clearAllData() async {
        glucoseHistory = []
        currentGlucoseReading = nil
        logWarning("Cleared data from memory - all API data is still in CoreData database")
    }
    
    // Add properties to track refresh results
    enum RefreshResult: Equatable {
        case none
        case success(newReadingsCount: Int)
        case upToDate
        case error(Error)
        
        var message: String {
            switch self {
            case .none:
                return ""
            case .success(let count):
                return "Successfully added \(count) new reading\(count == 1 ? "" : "s")"
            case .upToDate:
                return "Already up to date with latest readings"
            case .error(let error):
                return "Error: \(error.localizedDescription)"
            }
        }
        
        var isSuccess: Bool {
            if case .success = self {
                return true
            }
            return false
        }
        
        var isError: Bool {
            if case .error = self {
                return true
            }
            return false
        }
        
        // Implement Equatable
        static func == (lhs: RefreshResult, rhs: RefreshResult) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.upToDate, .upToDate):
                return true
            case (.success(let count1), .success(let count2)):
                return count1 == count2
            case (.error(let err1), .error(let err2)):
                return err1.localizedDescription == err2.localizedDescription
            default:
                return false
            }
        }
    }
    
    @Published var lastRefreshResult: RefreshResult = .none
    
    // Method to reload data with current granularity setting
    func reloadWithCurrentGranularity() async {
        logInfo("🔄 Reloading data with current granularity setting...")
        
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
        
        logInfo("✅ Reloaded \(granularityReadings.count) readings with granularity")
    }
    
    // Apply data granularity to readings
    private func applyGranularity(to readings: [GlucoseReading]) -> [GlucoseReading] {
        let granularity = UserDefaults.standard.integer(forKey: "dataGranularity")
        
        // If granularity is 0 (all readings) or only a single reading, return as is
        if granularity == 0 || readings.count <= 1 {
            return readings
        }
        
        logInfo("🧪 Applying granularity of \(granularity) minute(s) to \(readings.count) readings")
        
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
        
        logInfo("🧪 Reduced to \(sortedReadings.count) averaged readings with granularity of \(granularity) minute(s)")
        
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
    @Published var insulinHistory: [InsulinShot] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedTab = 0
    
    // Add patient profile property
    @Published var patientProfile: PatientProfile?
    
    // Current unit of measurement (mmol/L or mg/dL)
    var currentUnit: String {
        return UserDefaults.standard.string(forKey: "unit") ?? "mmol/L"
    }
    
    // MARK: - Logging Support
    
    // Central log store that can be registered from different views
    private weak var logStore: LogStore? = nil
    
    // Register a log store from a view
    func registerLogStore(_ store: LogStore) {
        self.logStore = store
        log("AppState registered a log store")
    }
    
    // Unregister the log store when view disappears
    func unregisterLogStore() {
        log("AppState unregistering log store")
        self.logStore = nil
    }
    
    // Log a message with an optional type
    func log(_ message: String, type: LogStore.LogType = .info) {
        // Print to console first (this always happens)
        print(message)
        
        // Then to the log store if available (no performance hit if not registered)
        logStore?.addLog(message, type: type)
    }
    
    // Short aliases for convenience
    func logInfo(_ message: String) {
        log(message, type: .info)
    }
    
    func logWarning(_ message: String) {
        log(message, type: .warning)
    }
    
    func logError(_ message: String) {
        log(message, type: .error)
    }
    
    // Add state variables for database cleanup
    @Published var isDatabaseCleanupRunning = false
    @Published var lastCleanupResult: DatabaseCleanupResult? = nil
    
    enum DatabaseCleanupResult {
        case success(uniqueCount: Int, duplicatesRemoved: Int, backupPath: String?)
        case failure(error: String)
    }
    
    init() {
        // Initialize coreDataManager first
        self.coreDataManager = ProgrammaticCoreDataManager.shared
        
        // Load saved readings from CoreData
        loadSavedReadings()
        
        // Load patient profile
        loadPatientProfile()
        
        // Load insulin shots
        loadSavedInsulinShots()
        
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
        
        // Use weak self to prevent retain cycles (AppState is a class)
        Task { [weak self] in
            guard let self = self else { return }
            
            // Since CoreDataManager methods don't throw, we don't need try/catch
            // Fetch all readings from CoreData
            var savedReadings = self.coreDataManager.fetchAllGlucoseReadings()
            
            print("📊 CRITICAL: Loaded \(savedReadings.count) readings from CoreData at startup")
            
            // CRITICAL FIX: Check if the data count is suspiciously high
            if savedReadings.count > 10000 {
                print("⚠️ WARNING: Suspiciously high number of readings (\(savedReadings.count)). This may indicate duplicate data.")
                
                // CRITICAL FIX: Check for duplicate readings
                let uniqueIds = Set(savedReadings.map { $0.id })
                if uniqueIds.count < savedReadings.count {
                    print("⚠️ WARNING: Found \(savedReadings.count - uniqueIds.count) duplicate readings!")
                    
                    // CRITICAL FIX: Remove duplicates by ID
                    let uniqueReadings = Array(Set(savedReadings))
                    print("🧹 Removed \(savedReadings.count - uniqueIds.count) duplicate readings")
                    savedReadings = uniqueReadings
                    
                    // Save the deduplicated readings back to CoreData
                    self.coreDataManager.saveGlucoseReadings(uniqueReadings)
                }
            }
            
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
            
            if !savedReadings.isEmpty {
                // Sort by timestamp, most recent first
                savedReadings.sort { $0.timestamp > $1.timestamp }
                
                // CRITICAL FIX: Only process the most recent 1000 readings for initial display
                // This will significantly speed up startup
                let recentReadings = Array(savedReadings.prefix(1000))
                print("📊 CRITICAL: Processing only the most recent 1000 readings for initial display")
                
                // Calculate trends for each reading using previous readings
                var enhancedReadings = [GlucoseReading]()
                
                for (index, reading) in recentReadings.enumerated() {
                    // Deep copy the reading
                    var updatedReading = reading
                    
                    // For each reading, consider all readings that came before it
                    let previousReadings = Array(recentReadings.suffix(from: index + 1))
                    
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
                
                // Update UI on main thread
                await MainActor.run {
                    self.glucoseHistory = granularityReadings
                    self.currentGlucoseReading = granularityReadings.first
                    print("📂 Loaded \(granularityReadings.count) glucose readings with calculated trends and applied granularity")
                }
                
                // CRITICAL FIX: Process the rest of the data in the background
                Task {
                    print("🔄 Processing remaining \(savedReadings.count - 1000) readings in background")
                    // Process the rest of the data here if needed
                }
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
            // Never use test data - always rely on real API authentication
            isAuthenticated = false
            throw error
        }
    }
    
    func fetchLatestReadings() async {
        // Reset the refresh result to ensure onChange is triggered even with the same result
        await MainActor.run {
            // Set to none first to ensure onChange triggers even if the result is the same
            print("🔔 TOAST: Resetting refresh result before fetch")
            self.lastRefreshResult = .none
        }
        
        do {
            // Always fetch real glucose data from the API
            print("🔄 Fetching real glucose data from LibreView API...")
            let readings = try await libreViewService.fetchGlucoseData()
            
            // Debug API response
            print("✅ API returned \(readings.count) readings")
            
            // IMPROVED DUPLICATE DETECTION: Check for readings with matching timestamps
            let existingReadings = coreDataManager.fetchAllGlucoseReadings()
            print("📊 Found \(existingReadings.count) existing readings in database")
            
            // Create a set of existing timestamps (as timeIntervalSince1970) for exact comparison
            let existingTimestamps = Set(existingReadings.map { $0.timestamp.timeIntervalSince1970 })
            
            // Filter out readings that already exist in the database by comparing exact timestamps
            let newReadings = readings.filter { reading in
                !existingTimestamps.contains(reading.timestamp.timeIntervalSince1970)
            }
            
            print("📊 Found \(newReadings.count) new readings to add")
            
            // Special explicit handling for no new readings case
            if newReadings.isEmpty {
                print("🔔 TOAST FINAL DEBUG: No new readings detected - need to show 'Already up to date' toast")
                
                // Make absolutely sure the message gets shown
                await MainActor.run {
                    // Force a message directly in the UI for testing
                    print("🔔 TOAST FINAL DEBUG: Directly calling toast manager")
                    ToastManager.shared.showInfo("Already up to date with latest readings")
                    
                    // Also update the state as before
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("🔔 TOAST FINAL DEBUG: Setting state to .upToDate")
                        self.lastRefreshResult = .upToDate
                    }
                }
                
                return
            }
            
            // We have new readings, save them and update
            if !newReadings.isEmpty {
                // Save the new readings
                coreDataManager.saveGlucoseReadings(newReadings)
                
                // Update app state with new readings
                await MainActor.run {
                    print("🔔 TOAST: Setting refresh result to .success(\(newReadings.count))")
                    self.lastRefreshResult = .success(newReadingsCount: newReadings.count)
                }
            }
            
            // Update state regardless of new readings
            loadSavedReadings()
            
        } catch {
            print("❌ Error fetching glucose data: \(error)")
            
            await MainActor.run {
                print("🔔 TOAST: Setting refresh result to .error")
                self.lastRefreshResult = .error(error)
            }
        }
    }
    
    // No test data generation function - always using real API data only
    
    // Cleanup database by removing duplicate readings
    func cleanupDuplicateReadings() async {
        // Prepare for cleanup
        await MainActor.run {
            isDatabaseCleanupRunning = true
            lastCleanupResult = nil
        }
        
        // Create an observer for cleanup messages
        let notificationCenter = NotificationCenter.default
        let observer = notificationCenter.addObserver(
            forName: NSNotification.Name("CleanupLog"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.userInfo?["message"] as? String,
               let type = notification.userInfo?["type"] as? String {
                switch type {
                case "warning":
                    self?.logWarning("🧹 CLEANUP: \(message)")
                case "error":
                    self?.logError("❌ CLEANUP: \(message)")
                default:
                    self?.logInfo("🧹 CLEANUP: \(message)")
                }
            }
        }
        
        // Start with a warning log
        logWarning("Starting database cleanup - removing duplicate readings")
        
        // Run cleanup in a background task
        let cleanupTask = Task.detached { [self] in
            // Run backup first
            let backupPath = DiabetesDataDiagnostic.shared.backupDatabase()
            
            // Log backup status
            if backupPath == nil {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CleanupLog"),
                    object: nil,
                    userInfo: [
                        "message": "Proceeding with cleanup without successful backup",
                        "type": "warning"
                    ]
                )
            } else {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CleanupLog"),
                    object: nil,
                    userInfo: [
                        "message": "Database backup created at: \(backupPath!)",
                        "type": "info"
                    ]
                )
            }
            
            // Perform cleanup with extensive logging
            let result = await cleanupDatabaseWithLogs(backupPath: backupPath)
            
            // Update state with results on main thread
            await MainActor.run { [self] in
                isDatabaseCleanupRunning = false
                
                if result.success {
                    let message = "✅ Database cleanup completed: removed \(result.duplicatesRemoved) duplicates, kept \(result.uniqueCount) unique readings"
                    logInfo(message)
                    
                    lastCleanupResult = .success(
                        uniqueCount: result.uniqueCount,
                        duplicatesRemoved: result.duplicatesRemoved,
                        backupPath: backupPath
                    )
                    
                    // Reload data to reflect changes
                    Task {
                        logInfo("Reloading data after cleanup")
                        loadSavedReadings()
                    }
                } else {
                    logError("❌ Database cleanup failed")
                    lastCleanupResult = .failure(error: "Database cleanup failed")
                }
                
                // Remove observer once complete
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    
    // Helper function to run cleanup with detailed logging
    private func cleanupDatabaseWithLogs(backupPath: String?) async -> (success: Bool, uniqueCount: Int, duplicatesRemoved: Int) {
        NotificationCenter.default.post(
            name: NSNotification.Name("CleanupLog"),
            object: nil,
            userInfo: [
                "message": "Starting detailed database cleanup process",
                "type": "info"
            ]
        )
        
        // Get all readings
        let allReadings = coreDataManager.fetchAllGlucoseReadings()
        
        NotificationCenter.default.post(
            name: NSNotification.Name("CleanupLog"),
            object: nil,
            userInfo: [
                "message": "Fetched \(allReadings.count) total readings",
                "type": "info"
            ]
        )
        
        // Group readings by timestamp string (accurate to the second)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var readingsByTimestamp: [String: [GlucoseReading]] = [:]
        
        for reading in allReadings {
            let timestampKey = dateFormatter.string(from: reading.timestamp)
            if readingsByTimestamp[timestampKey] == nil {
                readingsByTimestamp[timestampKey] = []
            }
            readingsByTimestamp[timestampKey]?.append(reading)
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("CleanupLog"),
            object: nil,
            userInfo: [
                "message": "Found \(readingsByTimestamp.count) unique timestamps out of \(allReadings.count) total readings",
                "type": "info"
            ]
        )
        
        // Count how many will be deleted
        var duplicatesToDelete = 0
        for (_, readings) in readingsByTimestamp {
            if readings.count > 1 {
                duplicatesToDelete += readings.count - 1
            }
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("CleanupLog"),
            object: nil,
            userInfo: [
                "message": "Will preserve \(readingsByTimestamp.count) readings and delete \(duplicatesToDelete) duplicates",
                "type": "info"
            ]
        )
        
        // Create a list of readings to keep (one per timestamp)
        var readingsToKeep: [GlucoseReading] = []
        for (_, readings) in readingsByTimestamp {
            if let firstReading = readings.first {
                readingsToKeep.append(firstReading)
            }
        }
        
        // Log what we're keeping for debug
        NotificationCenter.default.post(
            name: NSNotification.Name("CleanupLog"),
            object: nil,
            userInfo: [
                "message": "Preparing to save \(readingsToKeep.count) unique readings",
                "type": "info"
            ]
        )
        
        // Now save only the readings we want to keep
        do {
            // First delete all readings (we have them in memory)
            let deleteResult = coreDataManager.deleteAllGlucoseReadings()
            
            if !deleteResult {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CleanupLog"),
                    object: nil,
                    userInfo: [
                        "message": "Failed to clear existing readings",
                        "type": "error"
                    ]
                )
                return (false, 0, 0)
            }
            
            NotificationCenter.default.post(
                name: NSNotification.Name("CleanupLog"),
                object: nil,
                userInfo: [
                    "message": "Successfully cleared existing readings",
                    "type": "info"
                ]
            )
            
            // Then save only the unique readings
            coreDataManager.saveGlucoseReadings(readingsToKeep)
            
            NotificationCenter.default.post(
                name: NSNotification.Name("CleanupLog"),
                object: nil,
                userInfo: [
                    "message": "Successfully saved \(readingsToKeep.count) unique readings",
                    "type": "info"
                ]
            )
            
            return (true, readingsToKeep.count, duplicatesToDelete)
        } catch {
            NotificationCenter.default.post(
                name: NSNotification.Name("CleanupLog"),
                object: nil,
                userInfo: [
                    "message": "Error cleaning up database: \(error.localizedDescription)",
                    "type": "error"
                ]
            )
            return (false, 0, 0)
        }
    }
    
    // Diagnostic method to check for duplicate readings without modifying data
    func diagnoseDuplicateReadings() {
        Task {
            // Create log capture for diagnostics
            logInfo("📊 Running database diagnostics...")
            
            // Create an observer for diagnostic messages
            let notificationCenter = NotificationCenter.default
            let observer = notificationCenter.addObserver(
                forName: NSNotification.Name("DiagnosticLog"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let message = notification.userInfo?["message"] as? String {
                    self?.logInfo("📊 DIAGNOSTIC: \(message)")
                }
            }
            
            // Modify diagnostics to post notifications instead of just printing
            let diagnostic = DiabetesDataDiagnostic.shared
            
            // Run a customized diagnostic that captures output
            Task.detached {
                // Get all readings
                let allReadings = self.coreDataManager.fetchAllGlucoseReadings()
                
                // Post a notification with the count
                NotificationCenter.default.post(
                    name: NSNotification.Name("DiagnosticLog"),
                    object: nil,
                    userInfo: ["message": "Found \(allReadings.count) total readings in database"]
                )
                
                // Group readings by timestamp strings (accurate to the second)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                var readingsByTimestamp: [String: [GlucoseReading]] = [:]
                
                for reading in allReadings {
                    let timestampKey = dateFormatter.string(from: reading.timestamp)
                    if readingsByTimestamp[timestampKey] == nil {
                        readingsByTimestamp[timestampKey] = []
                    }
                    readingsByTimestamp[timestampKey]?.append(reading)
                }
                
                // Find duplicates
                var totalDuplicates = 0
                var duplicateGroups: [String: [GlucoseReading]] = [:]
                
                for (timestamp, readings) in readingsByTimestamp where readings.count > 1 {
                    duplicateGroups[timestamp] = readings
                    totalDuplicates += readings.count - 1 // Count duplicates (original doesn't count)
                }
                
                // Post results
                NotificationCenter.default.post(
                    name: NSNotification.Name("DiagnosticLog"),
                    object: nil,
                    userInfo: ["message": "Found \(duplicateGroups.count) timestamp groups with duplicates"]
                )
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("DiagnosticLog"),
                    object: nil,
                    userInfo: ["message": "Total duplicate readings: \(totalDuplicates)"]
                )
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("DiagnosticLog"),
                    object: nil,
                    userInfo: ["message": "Unique timestamps: \(readingsByTimestamp.count)"]
                )
                
                // Show examples of duplicates
                if !duplicateGroups.isEmpty {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DiagnosticLog"),
                        object: nil,
                        userInfo: ["message": "Examples of duplicate readings:"]
                    )
                    
                    let exampleCount = min(5, duplicateGroups.count)
                    let exampleTimestamps = Array(duplicateGroups.keys.sorted().prefix(exampleCount))
                    
                    for timestamp in exampleTimestamps {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("DiagnosticLog"),
                            object: nil,
                            userInfo: ["message": "Timestamp: \(timestamp)"]
                        )
                        
                        for (index, reading) in duplicateGroups[timestamp]!.enumerated() {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("DiagnosticLog"),
                                object: nil,
                                userInfo: ["message": "  Reading \(index+1): ID \(reading.id), Value \(reading.value)"]
                            )
                        }
                    }
                }
                
                // Final notification that we're done
                await MainActor.run {
                    self.logInfo("Diagnostics complete - check log viewer for results")
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
    
    // Load patient profile from CoreData
    private func loadPatientProfile() {
        if let profile = coreDataManager.fetchPatientProfile() {
            self.patientProfile = profile
            print("📋 Loaded patient profile: \(profile.name ?? "Unnamed")")
        } else {
            // Create a default profile with Core Data
            let newId = UUID().uuidString
            coreDataManager.savePatientProfile(
                id: newId,
                name: nil as String?,
                dateOfBirth: nil as Date?, 
                weight: nil as Double?,
                weightUnit: nil as String?,
                insulinType: nil as String?,
                insulinDose: nil as String?,
                otherMedications: nil as String?
            )
            // Fetch the newly created profile
            self.patientProfile = coreDataManager.fetchPatientProfile()
            print("📋 Created default patient profile")
        }
    }
    
    // Save patient profile to CoreData
    func savePatientProfile(_ profile: PatientProfile) {
        coreDataManager.savePatientProfile(
            id: profile.id,
            name: profile.name,
            dateOfBirth: profile.dateOfBirth,
            weight: profile.weight,
            weightUnit: profile.weightUnit,
            insulinType: profile.insulinType,
            insulinDose: profile.insulinDose,
            otherMedications: profile.otherMedications
        )
        self.patientProfile = profile
    }
    
    // Update specific patient profile fields
    func updatePatientProfile(
        name: String? = nil,
        dateOfBirth: Date? = nil,
        weight: Double? = nil,
        weightUnit: String? = nil,
        insulinType: String? = nil,
        insulinDose: String? = nil,
        otherMedications: String? = nil
    ) {
        if var currentProfile = self.patientProfile {
            // Update fields if provided
            if let name = name {
                currentProfile.name = name
            }
            
            if let dateOfBirth = dateOfBirth {
                currentProfile.dateOfBirth = dateOfBirth
            }
            
            if let weight = weight {
                currentProfile.weight = weight
            }
            
            if let weightUnit = weightUnit {
                currentProfile.weightUnit = weightUnit
            }
            
            if let insulinType = insulinType {
                currentProfile.insulinType = insulinType
            }
            
            if let insulinDose = insulinDose {
                currentProfile.insulinDose = insulinDose
            }
            
            if let otherMedications = otherMedications {
                currentProfile.otherMedications = otherMedications
            }
            
            // Save updated profile
            savePatientProfile(currentProfile)
        } else {
            // Create a new profile if none exists
            let id = UUID().uuidString
            coreDataManager.savePatientProfile(
                id: id,
                name: name,
                dateOfBirth: dateOfBirth,
                weight: weight,
                weightUnit: weightUnit,
                insulinType: insulinType,
                insulinDose: insulinDose,
                otherMedications: otherMedications
            )
            // Fetch the newly created profile
            self.patientProfile = coreDataManager.fetchPatientProfile()
        }
    }
    
    // Generate export data including patient profile, glucose readings, and insulin shots
    func generateMedicalExportData() -> [String: Any] {
        var exportData: [String: Any] = [
            "exportDate": Date(),
            "glucoseUnit": currentUnit
        ]
        
        // Add patient profile if available
        if let profile = patientProfile {
            // Create a dictionary from PatientProfile properties directly
            var profileDict: [String: Any] = [
                "id": profile.id
            ]
            
            if let name = profile.name {
                profileDict["name"] = name
            }
            
            if let dateOfBirth = profile.dateOfBirth {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                profileDict["dateOfBirth"] = dateFormatter.string(from: dateOfBirth)
            }
            
            if let profileWeight = profile.weight, profileWeight > 0 {
                profileDict["weight"] = profileWeight
            }
            
            if let weightUnit = profile.weightUnit {
                profileDict["weightUnit"] = weightUnit
            }
            
            if let insulinType = profile.insulinType {
                profileDict["insulinType"] = insulinType
            }
            
            if let insulinDose = profile.insulinDose {
                profileDict["insulinDose"] = insulinDose
            }
            
            if let otherMedications = profile.otherMedications {
                profileDict["otherMedications"] = otherMedications
            }
            
            exportData["patientProfile"] = profileDict
        }
        
        // Add glucose readings
        let readingsData = glucoseHistory.map { reading -> [String: Any] in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            
            return [
                "timestamp": dateFormatter.string(from: reading.timestamp),
                "value": reading.value,
                "unit": reading.unit,
                "isHigh": reading.isHigh,
                "isLow": reading.isLow
            ]
        }
        
        exportData["glucoseReadings"] = readingsData
        
        // Add insulin shots
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let insulinShotsData = insulinHistory.map { shot -> [String: Any] in
            var shotDict: [String: Any] = [
                "id": shot.id.uuidString,
                "timestamp": dateFormatter.string(from: shot.timestamp)
            ]
            
            if let dosage = shot.dosage {
                shotDict["dosage"] = dosage
            }
            
            if let notes = shot.notes {
                shotDict["notes"] = notes
            }
            
            return shotDict
        }
        
        exportData["insulinShots"] = insulinShotsData
        
        return exportData
    }
    
    // MARK: - Insulin Shot Methods
    
    // Load saved insulin shots from CoreData
    private func loadSavedInsulinShots() {
        print("🔃 Loading saved insulin shots from CoreData...")
        Task { [weak self] in
            guard let self = self else { return }
            
            let savedShots = self.coreDataManager.fetchAllInsulinShots()
            await MainActor.run {
                self.insulinHistory = savedShots
                print("💉 Loaded \(savedShots.count) insulin shots from CoreData")
            }
        }
    }
    
    // Add a new insulin shot
    func logInsulinShot(timestamp: Date, dosage: Double?, notes: String?) async -> Bool {
        // Create a new InsulinShot
        let newShot = InsulinShot(timestamp: timestamp, dosage: dosage, notes: notes)
        
        // Save to CoreData
        let success = coreDataManager.saveInsulinShot(
            id: newShot.id,
            timestamp: newShot.timestamp,
            dosage: newShot.dosage,
            notes: newShot.notes
        )
        
        if success {
            // If saved successfully, reload all shots
            // (This is simpler than trying to insert at the correct sorted position)
            await MainActor.run {
                // Add to the beginning of the array if sorted by most recent first
                // or simply reload all shots from CoreData
                loadSavedInsulinShots()
            }
        }
        
        return success
    }
    
    // Delete an insulin shot
    func deleteInsulinShot(id: UUID) async -> Bool {
        let success = coreDataManager.deleteInsulinShot(id: id)
        
        if success {
            await MainActor.run {
                // Remove from the in-memory array
                insulinHistory.removeAll { $0.id == id }
            }
        }
        
        return success
    }
    
    // Get insulin shots for a specific day
    func getInsulinShots(forDate date: Date) -> [InsulinShot] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return insulinHistory.filter {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    // Get insulin shots for a date range
    func getInsulinShots(fromDate: Date, toDate: Date) -> [InsulinShot] {
        return insulinHistory.filter {
            $0.timestamp >= fromDate && $0.timestamp <= toDate
        }.sorted { $0.timestamp < $1.timestamp }
    }
} 