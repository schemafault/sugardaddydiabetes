import Foundation
import Security

/// A secure manager for handling passwords using the macOS Keychain
class SecurePasswordManager {
    static let shared = SecurePasswordManager()
    
    private let service = "com.macsugardaddydiabetes"
    private let account = "libreview"
    
    private init() {
        // Migrate any existing password from UserDefaults to Keychain
        if let legacyPassword = UserDefaults.standard.string(forKey: "password") {
            savePassword(legacyPassword)
            // Remove from UserDefaults for security
            UserDefaults.standard.removeObject(forKey: "password")
        }
    }
    
    /// Save password to keychain
    func savePassword(_ password: String) {
        // Delete any existing password first
        deletePassword()
        
        guard !password.isEmpty else { return }
        
        let passwordData = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Error saving password to keychain: \(status)")
        }
    }
    
    /// Get password from keychain
    func getPassword() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let passwordData = result as? Data {
            return String(data: passwordData, encoding: .utf8) ?? ""
        } else {
            // Check if we have a legacy password in UserDefaults
            if let legacyPassword = UserDefaults.standard.string(forKey: "password") {
                // Migrate the password to keychain
                savePassword(legacyPassword)
                // Remove from UserDefaults
                UserDefaults.standard.removeObject(forKey: "password")
                return legacyPassword
            }
            return ""
        }
    }
    
    /// Delete password from keychain
    func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Error deleting password from keychain: \(status)")
        }
    }
}