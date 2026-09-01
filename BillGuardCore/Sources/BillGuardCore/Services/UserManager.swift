//
//  UserManager.swift
//  BillGuard
//
//  Manages user authentication, registration, and preferences
//  Stores user data in UserDefaults and passwords in Keychain
//

import Foundation
import Security

// MARK: - User Manager

@MainActor
class UserManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let currentUser = "currentUser"
        static let isLoggedIn = "isLoggedIn"
        static let lastUsername = "lastUsername"
        static let patients = "patients"
        static let userDefaults = "userCustomDefaults"
    }
    
    // MARK: - Singleton
    
    static let shared = UserManager()
    
    // MARK: - Initialization
    
    init() {
        // Load auth state without triggering @Published during init
        let isLoggedIn = UserDefaults.standard.bool(forKey: Keys.isLoggedIn)
        if isLoggedIn,
           let username = UserDefaults.standard.string(forKey: Keys.lastUsername),
           let data = UserDefaults.standard.data(forKey: "user_\(username.lowercased())"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            _currentUser = Published(initialValue: user)
            _isAuthenticated = Published(initialValue: true)
        }
    }
    
    // MARK: - Authentication
    
    /// Register a new user
    func register(data: RegistrationData) async -> Result<User, AuthError> {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        // Validate registration data
        guard data.isValid else {
            let errors = data.validationErrors.joined(separator: "\n")
            errorMessage = errors
            return .failure(.validationFailed(errors))
        }
        
        // Check if username already exists
        if userExists(username: data.username) {
            errorMessage = "Username already exists"
            return .failure(.usernameExists)
        }
        
        // Check if email already exists
        if emailExists(email: data.email) {
            errorMessage = "Email already registered"
            return .failure(.emailExists)
        }
        
        // Create new user
        let user = User(
            username: data.username,
            email: data.email,
            firstName: data.firstName,
            lastName: data.lastName
        )
        
        // Save password to Keychain
        let passwordSaved = savePassword(data.password, for: data.username)
        guard passwordSaved else {
            errorMessage = "Failed to save credentials"
            return .failure(.keychainError)
        }
        
        // Save user to UserDefaults
        saveUser(user)
        
        // Set as current user
        currentUser = user
        isAuthenticated = true
        UserDefaults.standard.set(true, forKey: Keys.isLoggedIn)
        UserDefaults.standard.set(data.username, forKey: Keys.lastUsername)
        
        return .success(user)
    }
    
    /// Login with username and password
    func login(username: String, password: String) async -> Result<User, AuthError> {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        // Validate input
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Username and password are required"
            return .failure(.invalidCredentials)
        }
        
        // Get stored password
        guard let storedPassword = getPassword(for: username) else {
            errorMessage = "Invalid username or password"
            return .failure(.invalidCredentials)
        }
        
        // Verify password
        guard storedPassword == password else {
            errorMessage = "Invalid username or password"
            return .failure(.invalidCredentials)
        }
        
        // Load user
        guard let user = loadUser(username: username) else {
            errorMessage = "User account not found"
            return .failure(.userNotFound)
        }
        
        // Update last login
        var updatedUser = user
        updatedUser.lastLoginAt = Date()
        saveUser(updatedUser)
        
        // Set as current user
        currentUser = updatedUser
        isAuthenticated = true
        UserDefaults.standard.set(true, forKey: Keys.isLoggedIn)
        UserDefaults.standard.set(username, forKey: Keys.lastUsername)
        
        return .success(updatedUser)
    }
    
    /// Logout current user
    func logout() {
        currentUser = nil
        isAuthenticated = false
        UserDefaults.standard.set(false, forKey: Keys.isLoggedIn)
    }
    
    /// Check if user is already logged in
    func checkAuthState() {
        let isLoggedIn = UserDefaults.standard.bool(forKey: Keys.isLoggedIn)
        
        if isLoggedIn, let username = UserDefaults.standard.string(forKey: Keys.lastUsername),
           let user = loadUser(username: username) {
            currentUser = user
            isAuthenticated = true
        }
    }
    
    // MARK: - User Management
    
    /// Update current user
    func updateUser(_ user: User) {
        saveUser(user)
        if user.id == currentUser?.id {
            currentUser = user
        }
    }
    
    /// Update user preferences
    func updatePreferences(_ preferences: UserPreferences) {
        guard var user = currentUser else { return }
        user.preferences = preferences
        updateUser(user)
    }
    
    /// Add patient to current user
    func addPatient(id: String) {
        guard var user = currentUser else { return }
        if !user.patientIds.contains(id) {
            user.patientIds.append(id)
            updateUser(user)
        }
    }
    
    /// Remove patient from current user
    func removePatient(id: String) {
        guard var user = currentUser else { return }
        user.patientIds.removeAll { $0 == id }
        updateUser(user)
    }
    
    /// Change password
    func changePassword(currentPassword: String, newPassword: String) -> Result<Void, AuthError> {
        guard let user = currentUser else {
            return .failure(.notAuthenticated)
        }
        
        // Verify current password
        guard let storedPassword = getPassword(for: user.username),
              storedPassword == currentPassword else {
            return .failure(.invalidCredentials)
        }
        
        // Validate new password
        guard newPassword.count >= 8 else {
            return .failure(.validationFailed("Password must be at least 8 characters"))
        }
        
        // Save new password
        guard savePassword(newPassword, for: user.username) else {
            return .failure(.keychainError)
        }
        
        return .success(())
    }
    
    /// Check if a user exists with the given username
    func userExists(username: String) -> Bool {
        let allUsernames = UserDefaults.standard.stringArray(forKey: "allUsernames") ?? []
        return allUsernames.contains(username.lowercased())
    }
    
    /// Reset password for a user (used for forgot password flow)
    func resetPassword(username: String, newPassword: String) -> Result<Void, AuthError> {
        // Validate username exists
        guard userExists(username: username) else {
            return .failure(.userNotFound)
        }
        
        // Validate new password
        guard newPassword.count >= 8 else {
            return .failure(.validationFailed("Password must be at least 8 characters"))
        }
        
        // Delete old password and save new one
        let lowercaseUsername = username.lowercased()
        deletePassword(for: lowercaseUsername)
        
        guard savePassword(newPassword, for: lowercaseUsername) else {
            return .failure(.keychainError)
        }
        
        return .success(())
    }
    
    // MARK: - Private: UserDefaults Operations
    
    private func loadCurrentUser() {
        checkAuthState()
    }
    
    private func emailExists(email: String) -> Bool {
        // In a real app, you'd want to maintain an email index
        // For now, this is a simplified check
        let allUsersKey = "allUsernames"
        guard let usernames = UserDefaults.standard.stringArray(forKey: allUsersKey) else {
            return false
        }
        
        for username in usernames {
            if let user = loadUser(username: username), user.email.lowercased() == email.lowercased() {
                return true
            }
        }
        return false
    }
    
    private func saveUser(_ user: User) {
        let key = "user_\(user.username.lowercased())"
        
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: key)
            
            // Maintain list of all usernames
            var allUsernames = UserDefaults.standard.stringArray(forKey: "allUsernames") ?? []
            if !allUsernames.contains(user.username.lowercased()) {
                allUsernames.append(user.username.lowercased())
                UserDefaults.standard.set(allUsernames, forKey: "allUsernames")
            }
        }
        
        // Also save as current user data
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Keys.currentUser)
        }
    }
    
    private func loadUser(username: String) -> User? {
        let key = "user_\(username.lowercased())"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }
    
    // MARK: - Private: Keychain Operations
    
    private func savePassword(_ password: String, for username: String) -> Bool {
        let passwordData = password.data(using: .utf8)!
        
        // Delete existing password if any
        deletePassword(for: username)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: username.lowercased(),
            kSecAttrService as String: "com.billguard.auth",
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func getPassword(for username: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: username.lowercased(),
            kSecAttrService as String: "com.billguard.auth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    @discardableResult
    private func deletePassword(for username: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: username.lowercased(),
            kSecAttrService as String: "com.billguard.auth"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Custom Defaults Storage
    
    /// Save custom defaults array (for future use)
    func saveCustomDefaults(_ defaults: [String: String]) {
        guard var user = currentUser else { return }
        user.preferences.customDefaults = defaults
        updateUser(user)
    }
    
    /// Get custom defaults
    func getCustomDefaults() -> [String: String] {
        return currentUser?.preferences.customDefaults ?? [:]
    }
}

// MARK: - Auth Error

enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case usernameExists
    case emailExists
    case userNotFound
    case notAuthenticated
    case validationFailed(String)
    case keychainError
    case networkError
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .usernameExists:
            return "Username already exists"
        case .emailExists:
            return "Email is already registered"
        case .userNotFound:
            return "User account not found"
        case .notAuthenticated:
            return "You must be logged in"
        case .validationFailed(let message):
            return message
        case .keychainError:
            return "Failed to save credentials securely"
        case .networkError:
            return "Network error. Please try again."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
