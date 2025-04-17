import SwiftUI

struct ToastView: View {
    let message: String
    let type: ToastType
    let onDismiss: () -> Void
    
    @State private var opacity: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(type.iconColor)
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    opacity = 0
                }
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.secondary)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(14)
        .background(type.backgroundColor)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
        .opacity(opacity)
        .onAppear {
            print("🔔 ToastView: View appeared with message: \"\(message)\"")
            withAnimation(.easeInOut(duration: 0.3)) {
                opacity = 1
            }
            
            // Auto-dismiss after a longer delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                print("🔔 ToastView: Auto-dismissing toast with message: \"\(message)\"")
                withAnimation(.easeInOut(duration: 0.3)) {
                    opacity = 0
                }
                
                // Additional delay to ensure animation completes before dismissal
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}

enum ToastType {
    case success
    case error
    case info
    
    var backgroundColor: Color {
        switch self {
        case .success:
            return Color.green.opacity(0.2)
        case .error:
            return Color.red.opacity(0.2)
        case .info:
            return Color.blue.opacity(0.2)
        }
    }
    
    var iconColor: Color {
        switch self {
        case .success:
            return Color.green
        case .error:
            return Color.red
        case .info:
            return Color.blue
        }
    }
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}

class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: (message: String, type: ToastType)? = nil
    
    func show(_ message: String, type: ToastType = .info) {
        print("🔔 ToastManager: Showing toast with message: \"\(message)\" and type: \(type)")
        // If there's already a toast, replace it
        withAnimation {
            currentToast = (message, type)
        }
    }
    
    func showSuccess(_ message: String) {
        print("🔔 ToastManager: showSuccess called with message: \"\(message)\"")
        show(message, type: .success)
    }
    
    func showError(_ message: String) {
        print("🔔 ToastManager: showError called with message: \"\(message)\"")
        show(message, type: .error)
    }
    
    func showInfo(_ message: String) {
        print("🔔 ToastManager: showInfo called with message: \"\(message)\"")
        
        // Extra debug for "up to date" message
        if message.contains("up to date") {
            print("🔔 ToastManager: IMPORTANT - Showing 'Already up to date' toast")
        }
        
        show(message, type: .info)
    }
    
    func dismiss() {
        print("🔔 ToastManager: Dismissing toast")
        withAnimation {
            currentToast = nil
        }
    }
}

struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let toast = toastManager.currentToast {
                VStack {
                    Spacer()
                    ToastView(
                        message: toast.message, 
                        type: toast.type,
                        onDismiss: {
                            toastManager.dismiss()
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .onAppear {
                        print("🔔 ToastModifier: Displaying toast with message: \"\(toast.message)\"")
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    func toast() -> some View {
        self.modifier(ToastModifier())
    }
} 