import SwiftUI
import Charts
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// Add a new AccessibilityAnnouncer class at the top level
class AccessibilityAnnouncer {
    static let shared = AccessibilityAnnouncer()
    
    private init() {}
    
    func announce(_ message: String, delay: Double = 0.5, polite: Bool = true) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            #if os(iOS)
            if polite {
                UIAccessibility.post(notification: .announcement, argument: message)
            } else {
                UIAccessibility.post(notification: .screenChanged, argument: message)
            }
            #elseif os(macOS)
            // For macOS, use process-wide notification if we need accessibility announcements
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Just log for now, accessibility announcements on macOS need a different approach
                print("Accessibility announcement on macOS: \(message)")
            }
            #endif
        }
    }
}

// Add AccessibilityUtils to contain shared accessibility helpers
enum AccessibilityUtils {
    // Higher contrast colors that meet WCAG 2.1 AA standards
    static let highContrastBlue = Color(red: 0.0, green: 0.4, blue: 0.9) // More vibrant blue for buttons
    static let highContrastOrange = Color(red: 0.9, green: 0.5, blue: 0.0) // More vibrant orange for warnings
    static let highContrastRed = Color(red: 0.9, green: 0.2, blue: 0.2) // More vibrant red for errors
    static let highContrastGreen = Color(red: 0.0, green: 0.7, blue: 0.3) // More vibrant green for success
    
    // Get an appropriate foreground color based on background
    static func accessibleForeground(for background: Color) -> Color {
        // Simple approximation - dark backgrounds get white text, light backgrounds get black text
        return background.brightness > 0.6 ? .black : .white
    }
    
    // Get high contrast border for focus states
    static func focusBorder(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .stroke(highContrastBlue, lineWidth: isActive ? 2.5 : 0)
            .opacity(isActive ? 1 : 0)
    }
}

// Add a brightness extension to Color for contrast calculations
extension Color {
    var brightness: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        #if os(iOS)
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #elseif os(macOS)
        NSColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        
        // Using weighted RGB values to calculate brightness
        return (red * 0.299 + green * 0.587 + blue * 0.114)
    }
}

// Add a TransitionDirection enum for easier animation handling
enum TransitionDirection {
    case left
    case right
    case none
    
    var offset: CGFloat {
        switch self {
        case .left: return -300
        case .right: return 300
        case .none: return 0
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: Int
    @State private var showSidebar: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var toastManager = ToastManager.shared
    
    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedTab) {
                Section("Main") {
                    NavigationLink(value: 0) {
                        Label("Dashboard", systemImage: "gauge")
                            .font(.headline)
                    }
                    NavigationLink(value: 1) {
                        Label("History", systemImage: "clock.fill")
                            .font(.headline)
                    }
                }
                
                Section("Advanced Analytics") {
                    NavigationLink(value: 3) {
                        Label("AGP Analysis", systemImage: "chart.xyaxis.line")
                            .font(.headline)
                    }
                    
                    NavigationLink(value: 4) {
                        Label("Calendar View", systemImage: "calendar")
                            .font(.headline)
                    }
                    
                    NavigationLink(value: 5) {
                        Label("Daily Comparison", systemImage: "chart.bar.doc.horizontal")
                            .font(.headline)
                    }
                }
                
                Section {
                    NavigationLink(value: 2) {
                        Label("Settings", systemImage: "gear")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Glucose Monitor")
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            // Remove redundant sidebar toggle - macOS provides this automatically
        } detail: {
            ZStack {
                // Background gradient
                backgroundGradient
                
                Group {
                    switch appState.selectedTab {
                    case 0:
                        DashboardView()
                            .transition(.opacity)
                    case 1:
                        HistoryView()
                            .transition(.opacity)
                    case 2:
                        SettingsView()
                            .transition(.opacity)
                    case 3:
                        AGPView()
                            .transition(.opacity)
                    case 4:
                        TimeInRangeCalendarView()
                            .transition(.opacity)
                    case 5:
                        ComparativeDailyView()
                            .transition(.opacity)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Material.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: colorScheme == .dark ? .black.opacity(0.5) : .gray.opacity(0.15), radius: 10)
                .padding(10)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await appState.fetchLatestReadings()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if appState.isLoading {
                LoadingView()
            }
        }
        .alert("Error", isPresented: .constant(appState.error != nil)) {
            Button("OK") {
                appState.error = nil
            }
        } message: {
            if let error = appState.error {
                Text(error.localizedDescription)
            }
        }
        .toast()
        .onReceive(appState.$lastRefreshResult) { newValue in
            print("🔔 TOAST ContentView: Refresh result changed to \(newValue)")
            if case .success(let count) = newValue {
                print("🔔 TOAST ContentView: Showing success toast for \(count) readings")
                toastManager.showSuccess("Successfully added \(count) new reading\(count == 1 ? "" : "s")")
            } else if case .upToDate = newValue {
                print("🔔 TOAST ContentView: Showing up-to-date toast")
                toastManager.showInfo("Already up to date with latest readings")
            } else if case .error(let error) = newValue {
                print("🔔 TOAST ContentView: Showing error toast: \(error.localizedDescription)")
                toastManager.showError("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.2) : Color(red: 0.95, green: 0.97, blue: 1.0),
                colorScheme == .dark ? Color(red: 0.1, green: 0.2, blue: 0.3) : Color(red: 0.9, green: 0.95, blue: 1.0)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .edgesIgnoringSafeArea(.all)
    }
}

struct LoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing), lineWidth: 5)
                    .frame(width: 50, height: 50)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                    .onAppear {
                        isAnimating = true
                    }
                
                Text("Loading...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Material.ultraThickMaterial)
            .cornerRadius(20)
            .shadow(radius: 10)
        }
    }
}

// Replace the simplified DashboardView with a restored complex version
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dateFilter = 0 // 0 = Today, 1 = Last 3 Days, 2 = Last 7 Days, 3 = Last 30 Days, 4 = All
    @State private var selectedDate: Date? = nil // For day navigation
    @State private var isTransitioning = false
    @State private var showDatePicker = false // State to control date picker visibility
    @State private var contentOpacity = 1.0
    @State private var previousDate: Date? = nil
    @State private var transitionDirection = TransitionDirection.none
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Historical data indicator
                if dateFilter == 0 && selectedDate != nil && !isViewingToday() {
                    historicalDataIndicatorContent
                }
                
                // Daily navigation controls (when in day view)
                if dateFilter == 0 {
                    dayNavigationControls
                }
                
                // Time filter picker
                timeFilterPicker
                
                // Current reading display - use currentGlucoseReading instead of latestReading
                if let latestReading = appState.currentGlucoseReading {
                    CurrentReadingView(reading: latestReading)
                        .padding(.horizontal)
                }
                
                // Graph section with filtered readings
                if !filteredReadings.isEmpty {
                    graphSection
                    
                    // Statistics Cards
                    StatisticsView(readings: filteredReadings)
                        .padding(.horizontal)
                }
                else {
                    noDataView
                }
                
                Spacer(minLength: 20)
            }
            .padding(.vertical)
            .contentWithTransition(
                isTransitioning: $isTransitioning,
                contentOpacity: $contentOpacity,
                direction: $transitionDirection
            )
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task {
                        await appState.fetchLatestReadings()
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }
    
    // MARK: - Helper Views
    
    private var historicalDataIndicatorContent: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(differentiateWithoutColor ? AccessibilityUtils.highContrastOrange : .orange)
                .accessibilityHidden(true)
            Text("Viewing historical data")
                .font(.callout)
                .foregroundColor(differentiateWithoutColor ? AccessibilityUtils.highContrastOrange : .orange)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Historical data indicator")
    }
    
    private var dayNavigationControls: some View {
        HStack(spacing: 20) {
            // Previous day button
            Button(action: {
                navigateDay(direction: .backward)
            }) {
                Image(systemName: "chevron.left")
                    .imageScale(.large)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Date display/picker button
            Button(action: {
                // Show date picker sheet
                showDatePicker = true
            }) {
                HStack {
                    Text(formattedSelectedDate)
                        .font(.headline)
                    Image(systemName: "calendar")
                        .imageScale(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Next day button (disabled if viewing today)
            Button(action: {
                navigateDay(direction: .forward)
            }) {
                Image(systemName: "chevron.right")
                    .imageScale(.large)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundColor(isViewingToday() ? .gray : .primary)
            }
            .buttonStyle(.plain)
            .disabled(isViewingToday())
            .onChange(of: isViewingToday()) { _, isToday in
                if isToday {
                    AccessibilityAnnouncer.shared.announce("Next day button disabled. You are viewing today's data.")
                }
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Day navigation controls")
    }
    
    private var timeFilterPicker: some View {
        Picker("Time Range", selection: $dateFilter) {
            Text("Day View").tag(0)
            Text("3 Days").tag(1)
            Text("7 Days").tag(2)
            Text("30 Days").tag(3)
            Text("All Data").tag(4)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: dateFilter) { _, _ in
            // Reset date selection when changing filter type
            if dateFilter != 0 {
                selectedDate = nil
            } else if selectedDate == nil {
                selectedDate = Calendar.current.startOfDay(for: Date())
            }
            
            // Announce the change for accessibility
            let rangeText: String
            switch dateFilter {
            case 0: rangeText = "day view"
            case 1: rangeText = "3 days"
            case 2: rangeText = "7 days"
            case 3: rangeText = "30 days"
            case 4: rangeText = "all data"
            default: rangeText = "unknown range"
            }
            
            AccessibilityAnnouncer.shared.announce("Changed to \(rangeText) time range")
        }
    }
    
    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glucose Trend")
                .font(.headline)
                .padding(.horizontal)
            
            GlucoseChartView(readings: filteredReadings)
                .frame(height: 220)
                .padding(.horizontal, 5)
        }
    }
    
    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No data available for this time period")
                .font(.headline)
            
            Text("Try selecting a different date range or refresh your data")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Refresh Data") {
                Task {
                    await appState.fetchLatestReadings()
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var datePickerSheet: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    showDatePicker = false
                }
                .padding()
                
                Spacer()
                
                Button("Today") {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                    showDatePicker = false
                    
                    AccessibilityAnnouncer.shared.announce("Selected today's date")
                }
                .padding()
            }
            
            DatePicker(
                "Select Date",
                selection: Binding(
                    get: { selectedDate ?? Date() },
                    set: { selectedDate = Calendar.current.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            
            Button("Select") {
                // Make sure a date is selected
                if selectedDate == nil {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                }
                showDatePicker = false
                
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                
                AccessibilityAnnouncer.shared.announce("Selected date: \(formatter.string(from: selectedDate ?? Date()))")
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
    
    // MARK: - Helper Methods
    
    private var filteredReadings: [GlucoseReading] {
        guard !appState.glucoseHistory.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let now = Date()
        
        // If in day view and a day is selected
        if dateFilter == 0 && selectedDate != nil {
            let startOfSelectedDay = calendar.startOfDay(for: selectedDate!)
            let endOfSelectedDay = calendar.date(byAdding: .day, value: 1, to: startOfSelectedDay)!
            
            return appState.glucoseHistory.filter { reading in
                reading.timestamp >= startOfSelectedDay && reading.timestamp < endOfSelectedDay
            }
        }
        
        // For other time ranges
        switch dateFilter {
        case 1: // Last 3 days
            let startDate = calendar.date(byAdding: .day, value: -3, to: now)!
            return appState.glucoseHistory.filter { $0.timestamp >= startDate }
        case 2: // Last 7 days
            let startDate = calendar.date(byAdding: .day, value: -7, to: now)!
            return appState.glucoseHistory.filter { $0.timestamp >= startDate }
        case 3: // Last 30 days
            let startDate = calendar.date(byAdding: .day, value: -30, to: now)!
            return appState.glucoseHistory.filter { $0.timestamp >= startDate }
        case 4: // All data
            return appState.glucoseHistory
        default:
            // Default to today
            let startOfToday = calendar.startOfDay(for: now)
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
            
            return appState.glucoseHistory.filter { reading in
                reading.timestamp >= startOfToday && reading.timestamp < endOfToday
            }
        }
    }
    
    private var formattedSelectedDate: String {
        let date = selectedDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func isViewingToday() -> Bool {
        guard dateFilter == 0, let selectedDate = selectedDate else { return true }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: selectedDate)
        
        return calendar.isDate(today, inSameDayAs: selected)
    }
    
    private enum DayNavigationDirection {
        case forward
        case backward
    }
    
    private func navigateDay(direction: DayNavigationDirection) {
        // Store the previous date for animation
        previousDate = selectedDate
        
        // Get the current selected date, or today if none
        let currentDate = selectedDate ?? Calendar.current.startOfDay(for: Date())
        
        // Calculate the new date
        if let newDate = Calendar.current.date(
            byAdding: .day,
            value: direction == .forward ? 1 : -1,
            to: currentDate
        ) {
            // Don't allow navigating to future dates
            let today = Calendar.current.startOfDay(for: Date())
            if newDate > today {
                AccessibilityAnnouncer.shared.announce("Cannot navigate to future dates")
                return
            }
            
            // Start animation
            isTransitioning = true
            transitionDirection = direction == .forward ? .left : .right
            
            // Update the selected date
            selectedDate = newDate
            
            // Format for accessibility announcement
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            AccessibilityAnnouncer.shared.announce("Navigated to \(formatter.string(from: newDate))")
        }
    }
}

// Add the content transition modifier
extension View {
    func contentWithTransition(
        isTransitioning: Binding<Bool>,
        contentOpacity: Binding<Double>,
        direction: Binding<TransitionDirection>
    ) -> some View {
        self.modifier(ContentTransitionModifier(
            isTransitioning: isTransitioning,
            contentOpacity: contentOpacity,
            direction: direction
        ))
    }
}

// Create the content transition modifier
struct ContentTransitionModifier: ViewModifier {
    @Binding var isTransitioning: Bool
    @Binding var contentOpacity: Double
    @Binding var direction: TransitionDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .opacity(contentOpacity)
            .offset(x: isTransitioning && !reduceMotion ? direction.offset : 0)
            .onChange(of: isTransitioning) { _, transitioning in
                if transitioning {
                    // Start transition
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentOpacity = 0
                    }
                    
                    // After a short delay, end transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            contentOpacity = 1
                            direction = .none
                        }
                        
                        // End transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isTransitioning = false
                        }
                    }
                }
            }
    }
}

// Create the GlucoseChartView
struct GlucoseChartView: View {
    let readings: [GlucoseReading]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    
    // Target range
    private let targetMin = 70.0
    private let targetMax = 180.0
    
    var body: some View {
        Chart {
            // Target range rectangle
            RectangleMark(
                xStart: .value("Start", readings.first?.timestamp ?? Date()),
                xEnd: .value("End", readings.last?.timestamp ?? Date()),
                yStart: .value("Min", targetMin),
                yEnd: .value("Max", targetMax)
            )
            .foregroundStyle(Color.green.opacity(differentiateWithoutColor ? 0.1 : 0.15))
            .accessibilityHidden(true)
            
            // Glucose line
            ForEach(readings) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.displayValue)
                )
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(differentiateWithoutColor ? 
                                  AccessibilityUtils.highContrastBlue : 
                                  Color.blue.opacity(0.8))
                .interpolationMethod(.catmullRom)
                .accessibilityLabel("Glucose reading at \(timeString(reading.timestamp))")
                .accessibilityValue("\(String(format: "%.1f", reading.displayValue)) \(reading.displayUnit)")
            }
            
            // Data points
            ForEach(readings) { reading in
                PointMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.displayValue)
                )
                .symbolSize(CGSize(width: 10, height: 10))
                .foregroundStyle(differentiateWithoutColor ? 
                                  getHighContrastPointColor(for: reading) : 
                                  getPointColor(for: reading))
            }
        }
        .chartXAxis {
            AxisMarks(preset: .automatic, values: .stride(by: .hour, count: 2)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(timeString(date))
                            .font(.caption)
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(preset: .automatic, position: .trailing) { value in
                AxisValueLabel()
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYScale(domain: chartYDomain)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? 
                      Color.black.opacity(0.3) : 
                      Color.white.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // Compute Y axis range dynamically
    private var chartYDomain: ClosedRange<Double> {
        if readings.isEmpty { return 40...300 }
        
        let minReading = readings.map { $0.displayValue }.min() ?? 70.0
        let maxReading = readings.map { $0.displayValue }.max() ?? 180.0
        
        // Add padding to the range
        let padding = (maxReading - minReading) * 0.2
        let min = max(0, minReading - padding)
        let max = maxReading + padding
        
        return min...max
    }
    
    // Helper to format time for X axis
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    
    // Get color for data points
    private func getPointColor(for reading: GlucoseReading) -> Color {
        if reading.displayValue < targetMin {
            return .orange
        } else if reading.displayValue > targetMax {
            return .red
        } else {
            return .green
        }
    }
    
    // Get high contrast color for data points
    private func getHighContrastPointColor(for reading: GlucoseReading) -> Color {
        if reading.displayValue < targetMin {
            return AccessibilityUtils.highContrastOrange
        } else if reading.displayValue > targetMax {
            return AccessibilityUtils.highContrastRed
        } else {
            return AccessibilityUtils.highContrastGreen
        }
    }
}

// Style CurrentReadingView with high contrast support
struct CurrentReadingView: View {
    let reading: GlucoseReading
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    
    var body: some View {
        VStack(spacing: dynamicTypeSize >= .large ? 20 : 16) {
            HStack {
                Text("Current Reading")
                    .font(.system(size: dynamicTypeSize >= .large ? 20 : 18, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .imageScale(.small)
                    Text(formatTime(reading.timestamp))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            HStack(alignment: .center, spacing: 30) {
                VStack {
                    Text(String(format: "%.1f", reading.displayValue))
                        .font(.system(size: dynamicTypeSize >= .large ? 50 : 60, weight: .bold, design: .rounded))
                        .foregroundColor(differentiateWithoutColor ? getHighContrastColor(for: reading) : reading.rangeStatus.color)
                        .contentTransition(.numericText())
                        .shadow(color: reading.rangeStatus.color.opacity(0.4), radius: 2, x: 0, y: 1)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    Text(reading.displayUnit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 10) {
                    Image(systemName: reading.trend.icon)
                        .font(.system(size: dynamicTypeSize >= .large ? 35 : 40))
                        .foregroundColor(differentiateWithoutColor ? getHighContrastColor(for: reading) : reading.rangeStatus.color)
                        .symbolEffect(.pulse, options: .repeating, value: reading.isInRange ? false : true)
                    
                    Text(reading.trend.description)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(dynamicTypeSize >= .xxLarge ? 25 : 20)
        .background(Material.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1), radius: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    differentiateWithoutColor ? 
                    getHighContrastColor(for: reading).opacity(0.5) : 
                    reading.rangeStatus.color.opacity(0.3), 
                    lineWidth: differentiateWithoutColor ? 2 : 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current glucose reading: \(String(format: "%.1f", reading.displayValue)) \(reading.displayUnit), \(reading.trend.description)")
        .accessibilityValue(reading.isInRange ? "In range" : "Out of range")
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Helper method to get high contrast colors
    private func getHighContrastColor(for reading: GlucoseReading) -> Color {
        let status = GlucoseRangeStatus.fromRangeStatus(reading.rangeStatus)
        return getHighContrastColor(for: status)
    }
    
    private func getHighContrastColor(for status: GlucoseRangeStatus) -> Color {
        switch status {
        case .low:
            return AccessibilityUtils.highContrastOrange
        case .normal:
            return AccessibilityUtils.highContrastGreen
        case .high:
            return AccessibilityUtils.highContrastRed
        }
    }
}

// Update StatisticsView for better accessibility
struct StatisticsView: View {
    let readings: [GlucoseReading]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize // Support for dynamic type
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: dynamicTypeSize >= .large ? 25 : 20) { // Adjust spacing for dynamic type
            StatCard(title: "Average", value: calculateAverage(), icon: "number")
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Average glucose level: \(calculateAverage())")
            
            StatCard(title: "Time in Range", value: calculateTimeInRange(), icon: "timer")
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Time in range: \(calculateTimeInRange())")
            
            StatCard(title: "Readings", value: "\(readings.count)", icon: "list.bullet.clipboard")
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Total readings: \(readings.count)")
        }
    }
    
    private func calculateAverage() -> String {
        guard !readings.isEmpty else { return "0.0" }
        let values = readings.map { $0.displayValue }
        let average = values.reduce(0, +) / Double(values.count)
        return String(format: "%.1f", average)
    }
    
    private func calculateTimeInRange() -> String {
        guard !readings.isEmpty else { return "0%" }
        let inRange = readings.filter { $0.isInRange }.count
        let percentage = Double(inRange) / Double(readings.count) * 100
        return String(format: "%.1f%%", percentage)
    }
}

// Simplified, minimal version of other struct defs
private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack {
            Image(systemName: icon)
            Text(title)
            Text(value)
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(10)
    }
}

// SwipeDirection enum for gesture handling
enum SwipeDirection {
    case left
    case right
}

// Custom ViewModifier for handling swipe gestures
struct SwipeGestureModifier: ViewModifier {
    let onSwipe: (SwipeDirection) -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var previousTranslation: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onChanged { gesture in
                        let translation = gesture.translation.width
                        let delta = translation - previousTranslation
                        previousTranslation = translation
                        
                        // Only allow horizontal dragging
                        let newOffset = dragOffset + delta
                        
                        // Limit the drag distance with diminishing returns
                        let maxDrag: CGFloat = 100
                        if abs(newOffset) < maxDrag {
                            dragOffset = newOffset
                        } else {
                            // Apply diminishing effect beyond maxDrag
                            let extraDrag = abs(newOffset) - maxDrag
                            let diminishedExtra = extraDrag * 0.2 // Diminishing factor
                            let direction: CGFloat = newOffset > 0 ? 1 : -1
                            dragOffset = maxDrag * direction + diminishedExtra * direction
                        }
                    }
                    .onEnded { gesture in
                        let translation = gesture.translation.width
                        let velocity = gesture.predictedEndTranslation.width - translation
                        
                        // Determine swipe direction based on final position and velocity
                        if dragOffset > 75 || (dragOffset > 20 && velocity > 100) {
                            // Swipe right detected
                            withAnimation(.spring()) {
                                dragOffset = 0
                                previousTranslation = 0
                            }
                            onSwipe(.right)
                        } else if dragOffset < -75 || (dragOffset < -20 && velocity < -100) {
                            // Swipe left detected
                            withAnimation(.spring()) {
                                dragOffset = 0
                                previousTranslation = 0
                            }
                            onSwipe(.left)
                        } else {
                            // Reset position if not a valid swipe
                            withAnimation(.spring()) {
                                dragOffset = 0
                                previousTranslation = 0
                            }
                        }
                    }
            )
            .offset(x: dragOffset)
            .animation(.interactiveSpring(), value: dragOffset)
    }
}

// Add this to the file scope to support keyboard shortcuts
extension View {
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.keyboardShortcut(key, modifiers: modifiers)
            .onAppear {
                #if os(macOS)
                // Use a global key handler through NSEvent
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // Check if the key combination matches
                    if event.modifierFlags.contains(modifiers.eventModifierFlags) {
                        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
                        if character == key.character.lowercased() {
                            action()
                            return nil // Consume the event
                        }
                    }
                    return event
                }
                #endif
            }
    }
}

// Add extension for KeyEquivalent
extension KeyEquivalent {
    var character: String {
        String(describing: self)
    }
}

// Add conversion for SwiftUI EventModifiers to AppKit modifiers
extension EventModifiers {
    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}

// Define the GlucoseRangeStatus enum as a top-level type
enum GlucoseRangeStatus: Equatable {
    case low
    case normal // Maps to .inRange in RangeStatus
    case high
    
    var color: Color {
        switch self {
        case .low:
            return Color.yellow 
        case .normal:
            return Color.green
        case .high:
            return Color.red
        }
    }
    
    // Helper to convert from the model's RangeStatus
    static func fromRangeStatus(_ status: GlucoseReading.RangeStatus) -> GlucoseRangeStatus {
        switch status {
        case .low: return .low
        case .inRange: return .normal
        case .high: return .high
        }
    }
    
    // Helper to create from a glucose value
    static func fromValue(_ value: Double, unit: String) -> GlucoseRangeStatus {
        let mgdl: Double
        
        // Convert to mg/dL if needed
        if unit == "mmol/L" {
            mgdl = value * 18.0
        } else {
            mgdl = value
        }
        
        // Use the same thresholds as the app
        let lowThreshold = Double(UserDefaults.standard.string(forKey: "lowThreshold") ?? "70") ?? 70
        let highThreshold = Double(UserDefaults.standard.string(forKey: "highThreshold") ?? "180") ?? 180
        
        if mgdl < lowThreshold {
            return .low
        } else if mgdl > highThreshold {
            return .high
        } else {
            return .normal
        }
    }
}

// Add trend properties to GlucoseRangeStatus or create a GlucoseTrend enum
enum GlucoseTrend {
    case rapidlyFalling
    case falling
    case stable
    case rising
    case rapidlyRising
    case unknown
    
    var icon: String {
        switch self {
        case .rapidlyFalling:
            return "arrow.down.to.line"
        case .falling:
            return "arrow.down"
        case .stable:
            return "arrow.right"
        case .rising:
            return "arrow.up"
        case .rapidlyRising:
            return "arrow.up.to.line"
        case .unknown:
            return "questionmark"
        }
    }
    
    var description: String {
        switch self {
        case .rapidlyFalling:
            return "rapidly falling"
        case .falling:
            return "falling"
        case .stable:
            return "stable"
        case .rising:
            return "rising"
        case .rapidlyRising:
            return "rapidly rising"
        case .unknown:
            return "unknown trend"
        }
    }
}

// Map GlucoseTrend to match the existing model
extension GlucoseTrend {
    static func fromModelTrend(_ trend: GlucoseReading.GlucoseTrend) -> GlucoseTrend {
        switch trend {
        case .notComputable: return .unknown
        case .falling: return .falling
        case .stable: return .stable
        case .rising: return .rising
        }
    }
}

#Preview {
    ContentView(selectedTab: .constant(0))
        .environmentObject(AppState())
}