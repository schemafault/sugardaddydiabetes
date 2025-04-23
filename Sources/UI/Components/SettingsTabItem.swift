import SwiftUI

struct SettingsTabItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? 
                          Color.accentColor.opacity(0.15) : 
                          Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle()) // Make entire area clickable
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    HStack {
        SettingsTabItem(title: "Profile", icon: "person.fill", isSelected: true, action: {})
        SettingsTabItem(title: "Monitoring", icon: "gauge", isSelected: false, action: {})
        SettingsTabItem(title: "Data", icon: "chart.bar", isSelected: false, action: {})
    }
    .padding()
}