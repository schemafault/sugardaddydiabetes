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
                    case 1:
                        HistoryView()
                    case 2:
                        SettingsView()
                    case 3:
                        AGPView()
                    case 4:
                        TimeInRangeCalendarView()
                    case 5:
                        ComparativeDailyView()
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
    
    // Add a computed property to determine if we're viewing historical data
    private var isViewingHistoricalData: Bool {
        // If using day filter and not viewing today, or using any other filter
        return (dateFilter == 0 && selectedDate != nil && !isViewingToday()) || dateFilter != 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time filter picker
                timeFilterPicker
                
                // Current reading display with selectedDate
                if let latestReading = appState.currentGlucoseReading {
                    CurrentReadingView(
                        reading: latestReading,
                        isHistorical: isViewingHistoricalData,
                        allReadings: filteredReadings.isEmpty ? [latestReading] : filteredReadings,
                        selectedDate: selectedDate
                    )
                    .padding(.horizontal)
                }
                
                // Graph section with filtered readings
                if !filteredReadings.isEmpty {
                    graphSection
                    
                    // Daily navigation controls MOVED HERE - after the graph
                    // Only show for day view (dateFilter == 0)
                    if dateFilter == 0 {
                        dayNavigationControls
                            .padding(.top, -10) // Reduce some spacing
                    }
                    
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
        }
        .navigationTitle("Dashboard")
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }
    
    // MARK: - Helper Views
    
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Glucose Trend")
                .font(.headline)
                .padding(.horizontal, 4)
            
            GlucoseChartView(readings: processedReadings, selectedDate: dateFilter == 0 ? selectedDate : nil)
                .padding(.horizontal, 4)
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
            
            // Retain refresh functionality with a standalone button
            Button("Refresh Data") {
                Task {
                    await appState.fetchLatestReadings()
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            .accessibilityHint("Refreshes glucose data from the server")
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
    
    // Base filtered readings - these are filtered by date range but not processed yet
    private var filteredReadings: [GlucoseReading] {
        guard !appState.glucoseHistory.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Sort the readings by timestamp to ensure proper order
        let sortedReadings = appState.glucoseHistory.sorted(by: { $0.timestamp < $1.timestamp })
        
        // If in day view and a day is selected
        if dateFilter == 0 && selectedDate != nil {
            let startOfSelectedDay = calendar.startOfDay(for: selectedDate!)
            let endOfSelectedDay = calendar.date(byAdding: .day, value: 1, to: startOfSelectedDay)!
            
            return sortedReadings.filter { reading in
                reading.timestamp >= startOfSelectedDay && reading.timestamp < endOfSelectedDay
            }
        }
        
        // For other time ranges
        switch dateFilter {
        case 1: // Last 3 days
            let startDate = calendar.date(byAdding: .day, value: -3, to: now)!
            return sortedReadings.filter { $0.timestamp >= startDate }
        case 2: // Last 7 days
            let startDate = calendar.date(byAdding: .day, value: -7, to: now)!
            return sortedReadings.filter { $0.timestamp >= startDate }
        case 3: // Last 30 days
            let startDate = calendar.date(byAdding: .day, value: -30, to: now)!
            return sortedReadings.filter { $0.timestamp >= startDate }
        case 4: // All data
            return sortedReadings
        default:
            // Default to today
            let startOfToday = calendar.startOfDay(for: now)
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
            
            return sortedReadings.filter { reading in
                reading.timestamp >= startOfToday && reading.timestamp < endOfToday
            }
        }
    }
    
    // Process readings to handle data gaps and ensure continuity across day boundaries
    private var processedReadings: [GlucoseReading] {
        let readings = filteredReadings
        
        // For single day view, no special processing needed
        if dateFilter == 0 {
            return readings
        }
        
        // For multi-day views, ensure proper data handling
        
        // Already sorted in filteredReadings, but we'll ensure it here as well
        let sortedReadings = readings.sorted(by: { $0.timestamp < $1.timestamp })
        
        // If we have fewer than 2 readings, no processing needed
        guard sortedReadings.count >= 2 else { return sortedReadings }
        
        // Create a new array for processed readings
        var processedReadings: [GlucoseReading] = []
        
        // First, identify day boundaries in the data
        let calendar = Calendar.current
        var dayBoundaries: [Date] = []
        
        if let firstReading = sortedReadings.first, let lastReading = sortedReadings.last {
            var currentDate = calendar.startOfDay(for: firstReading.timestamp)
            let endDate = calendar.startOfDay(for: lastReading.timestamp)
            
            // Add all day boundaries (midnight) between first and last reading
            while currentDate <= endDate {
                dayBoundaries.append(currentDate)
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
        }
        
        // Process all readings, adding them to the result array
        for (index, reading) in sortedReadings.enumerated() {
            // Add the current reading
            processedReadings.append(reading)
            
            // If not the last reading, check for large gaps or day boundaries
            if index < sortedReadings.count - 1 {
                let nextReading = sortedReadings[index + 1]
                let timeDifference = nextReading.timestamp.timeIntervalSince(reading.timestamp)
                
                // If gap is greater than 6 hours, it's likely a significant gap in data
                // This prevents straight lines across long periods without data
                if timeDifference > 60 * 60 * 6 {
                    // Create an intentional break in the chart by not connecting these points
                    // This will be handled by the GlucoseChartView
                    continue
                }
                
                // Check if this interval crosses a day boundary
                let readingDay = calendar.startOfDay(for: reading.timestamp)
                let nextReadingDay = calendar.startOfDay(for: nextReading.timestamp)
                
                // If readings span different days, ensure chart handling preserves the connection
                if readingDay != nextReadingDay {
                    // No special action needed here as we've already sorted the readings
                    // The chart will naturally connect these points across day boundaries
                    continue
                }
            }
        }
        
        return processedReadings
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
            
            // Update the selected date immediately without animation
            selectedDate = newDate
            
            // Format for accessibility announcement
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            AccessibilityAnnouncer.shared.announce("Navigated to \(formatter.string(from: newDate))")
        }
    }
    
    // Day navigation controls view
    private var dayNavigationControls: some View {
        HStack(spacing: 16) {
            Button(action: {
                navigateDay(direction: .backward)
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Previous Day")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibility(label: Text("Go to previous day"))
            
            Button(action: {
                showDatePicker = true
            }) {
                HStack {
                    Text(formattedSelectedDate)
                    Image(systemName: "calendar")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibility(label: Text("Open date picker"))
            
            Button(action: {
                navigateDay(direction: .forward)
            }) {
                HStack {
                    Text("Next Day")
                    Image(systemName: "chevron.right")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibility(label: Text("Go to next day"))
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// Add the content transition modifier
extension View {
    func contentWithTransition(
        isTransitioning: Binding<Bool>,
        contentOpacity: Binding<Double>,
        direction: Binding<TransitionDirection>
    ) -> some View {
        // No animations or transitions - just return the content directly
        return self
    }
}

// Create the content transition modifier
struct ContentTransitionModifier: ViewModifier {
    @Binding var isTransitioning: Bool
    @Binding var contentOpacity: Double
    @Binding var direction: TransitionDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        // No animations - just return the content as is
        content
    }
}

// Fix the axis content issues in GlucoseChartView
struct GlucoseChartView: View {
    let readings: [GlucoseReading]
    let selectedDate: Date?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @EnvironmentObject private var appState: AppState
    
    // Target range
    private let targetMin = 70.0
    private let targetMax = 180.0
    
    // Computed property to get insulin shots for the current view period
    private var insulinShots: [InsulinShot] {
        guard !readings.isEmpty else { return [] }
        
        // For a single day view
        if let selectedDate = selectedDate {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return appState.getInsulinShots(fromDate: startOfDay, toDate: endOfDay)
        } 
        // For multiple days view, get the time range from readings
        else if let firstReading = readings.first, let lastReading = readings.last {
            return appState.getInsulinShots(fromDate: firstReading.timestamp, toDate: lastReading.timestamp)
        }
        
        return []
    }
    
    // MARK: - Chart Y-Axis Range
    // Static Y-axis range of 3-27 mmol/L (or equivalent in mg/dL)
    private var chartYDomain: ClosedRange<Double> {
        // Check if current readings are in mmol/L or mg/dL
        let isUsingMmolL = readings.isEmpty ? true : readings.first!.displayUnit == "mmol/L"
        
        if isUsingMmolL {
            // Direct mmol/L values
            return 3.0...27.0
        } else {
            // Convert mmol/L to mg/dL (multiply by 18)
            return 54.0...486.0  // 3 * 18 = 54, 27 * 18 = 486
        }
    }
    
    var body: some View {
        chartContainer
    }
    
    // Break down the chart view into smaller components
    private var chartContainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartContent
                .frame(height: 220)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
        }
        .padding(12)
        .background(chartBackground)
        .overlay(chartBorder)
        .shadow(color: colorScheme == .dark ? 
                Color.black.opacity(0.3) : 
                Color.gray.opacity(0.2), 
               radius: 10, x: 0, y: 5)
    }
    
    private var chartContent: some View {
        Chart {
            // Target range rectangle
            targetRangeRectangle
            
            // Glucose line
            glucoseLine
            
            // Data points
            dataPoints
            
            // Insulin shot indicators
            insulinShotMarkers
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
    }
    
    private var targetRangeRectangle: some ChartContent {
        RectangleMark(
            xStart: .value("Start", readings.first?.timestamp ?? Date()),
            xEnd: .value("End", readings.last?.timestamp ?? Date()),
            yStart: .value("Min", targetMin),
            yEnd: .value("Max", targetMax)
        )
        .foregroundStyle(Color.green.opacity(differentiateWithoutColor ? 0.1 : 0.15))
        .accessibilityHidden(true)
    }
    
    private var glucoseLine: some ChartContent {
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
    }
    
    private var dataPoints: some ChartContent {
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
    
    private var insulinShotMarkers: some ChartContent {
        ForEach(insulinShots) { shot in
            RuleMark(
                x: .value("Insulin Shot", shot.timestamp)
            )
            .foregroundStyle(differentiateWithoutColor ? 
                             Color.purple.opacity(0.8) : 
                             Color.purple.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .accessibilityLabel("Insulin shot at \(timeString(shot.timestamp)), \(shot.dosage != nil ? "\(String(format: "%.1f", shot.dosage!)) units" : "no dosage recorded")")
        }
    }
    
    private var chartBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? 
                  Color(white: 0.12).opacity(0.8) : 
                  Color.white.opacity(0.7))
    }
    
    private var chartBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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

// Update CurrentReadingView to support both current and historical average readings
struct CurrentReadingView: View {
    let reading: GlucoseReading
    let isHistorical: Bool
    let allReadings: [GlucoseReading]
    let selectedDate: Date?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    
    // Computed property to get average reading status
    private var averageStatus: GlucoseRangeStatus {
        guard !allReadings.isEmpty else { return GlucoseRangeStatus.normal }
        
        let average = allReadings.map { $0.displayValue }.reduce(0, +) / Double(allReadings.count)
        return GlucoseRangeStatus.fromValue(average, unit: reading.displayUnit)
    }
    
    // Computed property to check if viewing a historical day (not today)
    private var isViewingPastDate: Bool {
        guard isHistorical, let selectedDate = selectedDate else { return false }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: selectedDate)
        
        return selected < today
    }
    
    var body: some View {
        VStack(spacing: dynamicTypeSize >= .large ? 20 : 16) {
            HStack {
                // Change title based on whether we're showing current or historical data
                Text(isHistorical ? "Average Reading" : "Current Reading")
                    .font(.system(size: dynamicTypeSize >= .large ? 20 : 18, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // For historical view, show date instead of time
                if isHistorical {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .imageScale(.small)
                        Text(formatDate(reading.timestamp))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .imageScale(.small)
                        Text(formatTime(reading.timestamp))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            // MOVED: The historical data indicator is now integrated in the main content
            
            HStack(alignment: .center, spacing: 30) {
                VStack {
                    // For historical view, show average value
                    if isHistorical {
                        Text(calculateAverage())
                            .font(.system(size: dynamicTypeSize >= .large ? 50 : 60, weight: .bold, design: .rounded))
                            .foregroundColor(differentiateWithoutColor ? getHighContrastColor(for: averageStatus) : averageStatus.color)
                            .shadow(color: averageStatus.color.opacity(0.4), radius: 2, x: 0, y: 1)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    } else {
                        Text(String(format: "%.1f", reading.displayValue))
                            .font(.system(size: dynamicTypeSize >= .large ? 50 : 60, weight: .bold, design: .rounded))
                            .foregroundColor(differentiateWithoutColor ? getHighContrastColor(for: reading) : reading.rangeStatus.color)
                            .shadow(color: reading.rangeStatus.color.opacity(0.4), radius: 2, x: 0, y: 1)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    
                    Text(reading.displayUnit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Add the historical data indicator here if viewing a past date
                    if isViewingPastDate {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(differentiateWithoutColor ? AccessibilityUtils.highContrastOrange : .orange)
                                .imageScale(.small)
                                .accessibilityHidden(true)
                            Text("Viewing historical data")
                                .font(.caption.weight(.medium))
                                .foregroundColor(differentiateWithoutColor ? AccessibilityUtils.highContrastOrange : .orange)
                        }
                        .padding(.top, 8) // Add some space above the indicator
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Historical data indicator")
                    }
                }
                
                // Only show trend for current reading, not for historical
                if !isHistorical {
                    VStack(spacing: 10) {
                        Image(systemName: reading.trend.icon)
                            .font(.system(size: dynamicTypeSize >= .large ? 35 : 40))
                            .foregroundColor(differentiateWithoutColor ? getHighContrastColor(for: reading) : reading.rangeStatus.color)
                        
                        Text(reading.trend.description)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // For historical view, show time in range percentage
                    VStack(spacing: 10) {
                        Text(calculateTimeInRange())
                            .font(.system(size: dynamicTypeSize >= .large ? 25 : 30, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        Text("in range")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundColor(.secondary)
                    }
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
                    (isHistorical ? getHighContrastColor(for: averageStatus) : getHighContrastColor(for: reading)).opacity(0.5) : 
                    (isHistorical ? averageStatus.color : reading.rangeStatus.color).opacity(0.3), 
                    lineWidth: differentiateWithoutColor ? 2 : 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isHistorical ? 
                           "Average glucose reading: \(calculateAverage()) \(reading.displayUnit)" : 
                           "Current glucose reading: \(String(format: "%.1f", reading.displayValue)) \(reading.displayUnit), \(reading.trend.description)")
        .accessibilityValue(isHistorical ? 
                           "Time in range: \(calculateTimeInRange())" : 
                           (reading.isInRange ? "In range" : "Out of range"))
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    // Helper function to calculate average
    private func calculateAverage() -> String {
        guard !allReadings.isEmpty else { return "0.0" }
        let values = allReadings.map { $0.displayValue }
        let average = values.reduce(0, +) / Double(values.count)
        return String(format: "%.1f", average)
    }
    
    // Helper function to calculate time in range
    private func calculateTimeInRange() -> String {
        guard !allReadings.isEmpty else { return "0%" }
        let inRange = allReadings.filter { $0.isInRange }.count
        let percentage = Double(inRange) / Double(allReadings.count) * 100
        return String(format: "%.1f%%", percentage)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: dynamicTypeSize >= .large ? 15 : 12) {
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

// Enhance the StatCard design for a more professional look
private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Material.regularMaterial)
            .shadow(color: colorScheme == .dark ? 
                    Color.black.opacity(0.25) : 
                    Color.gray.opacity(0.2), 
                   radius: 8, x: 0, y: 4)
    }
    
    var body: some View {
        VStack(spacing: dynamicTypeSize >= .large ? 12 : 8) {
            // Icon at the top
            Image(systemName: icon)
                .font(.system(size: dynamicTypeSize >= .large ? 24 : 28))
                .foregroundColor(.blue.opacity(0.8))
                .frame(height: dynamicTypeSize >= .large ? 20 : 30)
            
            // Title
            Text(title)
                .font(.system(size: dynamicTypeSize >= .large ? 14 : 16, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Value
            Text(value)
                .font(.system(size: dynamicTypeSize >= .large ? 20 : 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(dynamicTypeSize >= .large ? 10 : 16)
        .frame(maxWidth: .infinity)
        .background(background)
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
                        dragOffset = dragOffset + delta
                    }
                    .onEnded { gesture in
                        let translation = gesture.translation.width
                        let velocity = gesture.predictedEndTranslation.width - translation
                        
                        // Determine swipe direction based on final position and velocity
                        if dragOffset > 75 || (dragOffset > 20 && velocity > 100) {
                            // Swipe right detected - no animation
                            dragOffset = 0
                            previousTranslation = 0
                            onSwipe(.right)
                        } else if dragOffset < -75 || (dragOffset < -20 && velocity < -100) {
                            // Swipe left detected - no animation
                            dragOffset = 0
                            previousTranslation = 0
                            onSwipe(.left)
                        } else {
                            // Reset position if not a valid swipe - no animation
                            dragOffset = 0
                            previousTranslation = 0
                        }
                    }
            )
            .offset(x: dragOffset)
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