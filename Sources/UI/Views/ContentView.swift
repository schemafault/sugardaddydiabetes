import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: Int
    @State private var showSidebar: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showSidebar.toggle() }) {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
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
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
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

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                if let reading = appState.currentGlucoseReading {
                    CurrentReadingView(reading: reading)
                }
                
                if !appState.glucoseHistory.isEmpty {
                    EnhancedGlucoseChartView(readings: appState.glucoseHistory)
                        .frame(minHeight: 350)
                        .padding()
                        .background(Material.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1), radius: 5)
                }
                
                StatisticsView(readings: appState.glucoseHistory)
                    .padding(.horizontal)
                
                // Advanced Analytics Cards
                VStack(alignment: .leading, spacing: 16) {
                    Text("Advanced Analytics")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    advancedAnalyticsGrid
                }
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
        .navigationSubtitle(formatDate(Date()))
    }
    
    private var advancedAnalyticsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            analyticCard(
                title: "AGP Analysis",
                description: "Clinical standard glucose profile",
                icon: "chart.xyaxis.line",
                color: .blue,
                destination: 3
            )
            
            analyticCard(
                title: "Calendar View",
                description: "Time in range heatmap",
                icon: "calendar",
                color: .green,
                destination: 4
            )
            
            analyticCard(
                title: "Compare Days",
                description: "Overlay multiple days of data",
                icon: "chart.bar.doc.horizontal",
                color: .purple,
                destination: 5
            )
        }
    }
    
    private func analyticCard(title: String, description: String, icon: String, color: Color, destination: Int) -> some View {
        Button(action: {
            appState.selectedTab = destination
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Last updated: " + formatter.string(from: date)
    }
}

struct CurrentReadingView: View {
    let reading: GlucoseReading
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Reading")
                    .font(.system(size: 18, weight: .medium))
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
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(reading.rangeStatus.color)
                        .contentTransition(.numericText())
                        .shadow(color: reading.rangeStatus.color.opacity(0.4), radius: 2, x: 0, y: 1)
                    
                    Text(reading.displayUnit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 10) {
                    Image(systemName: reading.trend.icon)
                        .font(.system(size: 40))
                        .foregroundColor(reading.rangeStatus.color)
                        .symbolEffect(.pulse, options: .repeating, value: reading.isInRange ? false : true)
                    
                    Text(reading.trend.description)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(Material.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1), radius: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(reading.rangeStatus.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StatisticsView: View {
    let readings: [GlucoseReading]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            StatCard(title: "Average", value: calculateAverage(), icon: "number")
            StatCard(title: "Time in Range", value: calculateTimeInRange(), icon: "timer")
            StatCard(title: "Readings", value: "\(readings.count)", icon: "list.bullet.clipboard")
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

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            HStack {
                Spacer()
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
            }
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Material.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1), radius: 5)
    }
}

#Preview {
    ContentView(selectedTab: .constant(0))
        .environmentObject(AppState())
}