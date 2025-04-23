import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 36, height: 36)
                    )
                
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 4)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsSection(title: "Account", icon: "person.fill") {
        Text("Content goes here")
            .padding()
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}