import SwiftUI
import Security
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTab: SettingsTab = .profile
    
    enum SettingsTab {
        case profile
        case monitoring
        case devices
        case data
        case system
        
        var title: String {
            switch self {
            case .profile: return "Profile"
            case .monitoring: return "Monitoring"
            case .devices: return "Devices"
            case .data: return "Data"
            case .system: return "System"
            }
        }
        
        var icon: String {
            switch self {
            case .profile: return "person.fill"
            case .monitoring: return "gauge"
            case .devices: return "display"
            case .data: return "chart.bar.xaxis"
            case .system: return "gearshape"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab navigation
            HStack(spacing: 4) {
                ForEach([SettingsTab.profile, .monitoring, .devices, .data, .system], id: \.self) { tab in
                    SettingsTabItem(
                        title: tab.title,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                ZStack {
                    // Subtle gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            colorScheme == .dark ? Color(#colorLiteral(red: 0.18, green: 0.2, blue: 0.25, alpha: 1)) : Color(#colorLiteral(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)),
                            colorScheme == .dark ? Color(#colorLiteral(red: 0.15, green: 0.17, blue: 0.21, alpha: 1)) : Color(#colorLiteral(red: 0.92, green: 0.94, blue: 0.97, alpha: 1))
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Subtle border at bottom
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.1))
                            .frame(height: 1)
                    }
                }
                .cornerRadius(12)
            )
            
            // Content area
            ZStack {
                switch selectedTab {
                case .profile:
                    ProfileSettingsView()
                        .transition(.opacity)
                case .monitoring:
                    MonitoringSettingsView()
                        .transition(.opacity)
                case .devices:
                    DevicesSettingsView()
                        .transition(.opacity)
                case .data:
                    DataSettingsView()
                        .transition(.opacity)
                case .system:
                    SystemSettingsView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
        .frame(minWidth: 650, minHeight: 500)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}