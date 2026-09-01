//
//  User.swift
//  BillGuard
//
//  User model for authentication and preferences
//

import Foundation

// MARK: - User Model (Local Storage)

struct User: Codable, Identifiable {
    let id: String
    var username: String
    var email: String
    var firstName: String
    var lastName: String
    var createdAt: Date
    var lastLoginAt: Date?
    
    /// IDs of patients associated with this user
    var patientIds: [String]
    
    /// User preferences
    var preferences: UserPreferences
    
    init(
        id: String = UUID().uuidString,
        username: String,
        email: String,
        firstName: String = "",
        lastName: String = "",
        patientIds: [String] = [],
        preferences: UserPreferences = UserPreferences()
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.createdAt = Date()
        self.lastLoginAt = nil
        self.patientIds = patientIds
        self.preferences = preferences
    }
    
    var displayName: String {
        if !firstName.isEmpty || !lastName.isEmpty {
            return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        }
        return username
    }
}

// MARK: - User Preferences

struct UserPreferences: Codable {
    var defaultPatientId: String?
    var enableNotifications: Bool
    var enableBiometricAuth: Bool
    var defaultCurrency: String
    var dateFormat: String
    var showPriceEstimates: Bool
    var autoScanOnLaunch: Bool
    
    /// Future preferences placeholder
    var customDefaults: [String: String]
    
    init(
        defaultPatientId: String? = nil,
        enableNotifications: Bool = true,
        enableBiometricAuth: Bool = false,
        defaultCurrency: String = "USD",
        dateFormat: String = "MM/dd/yyyy",
        showPriceEstimates: Bool = true,
        autoScanOnLaunch: Bool = false,
        customDefaults: [String: String] = [:]
    ) {
        self.defaultPatientId = defaultPatientId
        self.enableNotifications = enableNotifications
        self.enableBiometricAuth = enableBiometricAuth
        self.defaultCurrency = defaultCurrency
        self.dateFormat = dateFormat
        self.showPriceEstimates = showPriceEstimates
        self.autoScanOnLaunch = autoScanOnLaunch
        self.customDefaults = customDefaults
    }
}

// MARK: - Registration Data

struct RegistrationData {
    var username: String = ""
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var firstName: String = ""
    var lastName: String = ""
    
    var isValid: Bool {
        !username.isEmpty &&
        !email.isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if username.isEmpty { errors.append("Username is required") }
        if username.count < 3 { errors.append("Username must be at least 3 characters") }
        if email.isEmpty { errors.append("Email is required") }
        if !email.contains("@") { errors.append("Invalid email format") }
        if password.count < 8 { errors.append("Password must be at least 8 characters") }
        if password != confirmPassword { errors.append("Passwords do not match") }
        return errors
    }
}
