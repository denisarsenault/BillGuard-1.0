//
//  User.swift
//  BillGuard
//
//  User model for authentication and preferences
//

import Foundation

// MARK: - User Model (Local Storage)

public struct User: Codable, Identifiable {
    public let id: String
    public var username: String
    public var email: String
    public var firstName: String
    public var lastName: String
    public var createdAt: Date
    public var lastLoginAt: Date?
    
    /// IDs of patients associated with this user
    public var patientIds: [String]
    
    /// User preferences
    public var preferences: UserPreferences
    
    public init(
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
    
    public var displayName: String {
        if !firstName.isEmpty || !lastName.isEmpty {
            return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        }
        return username
    }
}

// MARK: - User Preferences

public struct UserPreferences: Codable {
    public var defaultPatientId: String?
    public var enableNotifications: Bool
    public var enableBiometricAuth: Bool
    public var defaultCurrency: String
    public var dateFormat: String
    public var showPriceEstimates: Bool
    public var autoScanOnLaunch: Bool
    
    /// Future preferences placeholder
    public var customDefaults: [String: String]
    
    public init(
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

public struct RegistrationData {
    public var username: String = ""
    public var email: String = ""
    public var password: String = ""
    public var confirmPassword: String = ""
    public var firstName: String = ""
    public var lastName: String = ""
    
    public var isValid: Bool {
        !username.isEmpty &&
        !email.isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword
    }
    
    public var validationErrors: [String] {
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
