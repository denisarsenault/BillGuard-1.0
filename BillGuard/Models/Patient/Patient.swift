//
//  Patient.swift
//  BillGuard
//
//  Comprehensive patient model with demographics, contacts, and relationships
//

import Foundation
import CloudKit

// MARK: - Patient

struct Patient: Identifiable, Codable, Hashable {
    var id: String
    var guardianUserId: String  // The user who manages this patient
    
    // Basic Info
    var firstName: String
    var lastName: String
    var middleName: String?
    var dateOfBirth: Date?
    var gender: Gender?
    var relationship: PatientRelationship
    var socialSecurityLast4: String?
    
    // Contact Information
    var addresses: [PatientAddress]
    var phoneNumbers: [PatientPhone]
    var emailAddresses: [PatientEmail]
    
    // Linked Data IDs
    var insurancePolicyIds: [String]
    var paymentMethodIds: [String]
    var visitIds: [String]
    var documentIds: [String]
    
    // Metadata
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var recordId: String?
    
    init(
        id: String = UUID().uuidString,
        guardianUserId: String = "",
        firstName: String,
        lastName: String,
        middleName: String? = nil,
        dateOfBirth: Date? = nil,
        gender: Gender? = nil,
        relationship: PatientRelationship = .myself,
        socialSecurityLast4: String? = nil,
        addresses: [PatientAddress] = [],
        phoneNumbers: [PatientPhone] = [],
        emailAddresses: [PatientEmail] = [],
        insurancePolicyIds: [String] = [],
        paymentMethodIds: [String] = [],
        visitIds: [String] = [],
        documentIds: [String] = [],
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.guardianUserId = guardianUserId
        self.firstName = firstName
        self.lastName = lastName
        self.middleName = middleName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.relationship = relationship
        self.socialSecurityLast4 = socialSecurityLast4
        self.addresses = addresses
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.insurancePolicyIds = insurancePolicyIds
        self.paymentMethodIds = paymentMethodIds
        self.visitIds = visitIds
        self.documentIds = documentIds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    var fullName: String {
        if let middle = middleName, !middle.isEmpty {
            return "\(firstName) \(middle) \(lastName)"
        }
        return "\(firstName) \(lastName)"
    }
    
    var displayName: String { "\(firstName) \(lastName)" }
    
    var initials: String {
        "\(firstName.prefix(1).uppercased())\(lastName.prefix(1).uppercased())"
    }
    
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }
    
    var primaryAddress: PatientAddress? {
        addresses.first { $0.isPrimary } ?? addresses.first
    }
    
    var primaryPhone: PatientPhone? {
        phoneNumbers.first { $0.isPrimary } ?? phoneNumbers.first
    }
    
    var primaryEmail: PatientEmail? {
        emailAddresses.first { $0.isPrimary } ?? emailAddresses.first
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Patient, rhs: Patient) -> Bool { lhs.id == rhs.id }
}

// MARK: - Patient Address

struct PatientAddress: Identifiable, Codable, Hashable {
    var id: String
    var label: AddressLabel
    var street1: String
    var street2: String?
    var city: String
    var state: String
    var zipCode: String
    var country: String
    var isPrimary: Bool
    
    init(id: String = UUID().uuidString, label: AddressLabel = .home, street1: String = "",
         street2: String? = nil, city: String = "", state: String = "", zipCode: String = "",
         country: String = "USA", isPrimary: Bool = false) {
        self.id = id; self.label = label; self.street1 = street1; self.street2 = street2
        self.city = city; self.state = state; self.zipCode = zipCode
        self.country = country; self.isPrimary = isPrimary
    }
    
    var formatted: String {
        var lines = [street1]
        if let s2 = street2, !s2.isEmpty { lines.append(s2) }
        lines.append("\(city), \(state) \(zipCode)")
        if country != "USA" { lines.append(country) }
        return lines.joined(separator: "\n")
    }
}

enum AddressLabel: String, Codable, CaseIterable {
    case home = "Home", work = "Work", billing = "Billing", mailing = "Mailing", other = "Other"
}

// MARK: - Patient Phone

struct PatientPhone: Identifiable, Codable, Hashable {
    var id: String
    var label: PhoneLabel
    var number: String
    var isPrimary: Bool
    
    init(id: String = UUID().uuidString, label: PhoneLabel = .mobile, number: String = "", isPrimary: Bool = false) {
        self.id = id; self.label = label; self.number = number; self.isPrimary = isPrimary
    }
    
    var formatted: String {
        let digits = number.filter { $0.isNumber }
        guard digits.count == 10 else { return number }
        return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
    }
}

// MARK: - Patient Email

struct PatientEmail: Identifiable, Codable, Hashable {
    var id: String
    var label: EmailLabel
    var address: String
    var isPrimary: Bool
    
    init(id: String = UUID().uuidString, label: EmailLabel = .personal, address: String = "", isPrimary: Bool = false) {
        self.id = id; self.label = label; self.address = address; self.isPrimary = isPrimary
    }
}

enum EmailLabel: String, Codable, CaseIterable {
    case personal = "Personal", work = "Work", other = "Other"
}

// MARK: - Enums

enum Gender: String, Codable, CaseIterable {
    case male = "Male", female = "Female", other = "Other", preferNotToSay = "Prefer not to say"
}

enum PatientRelationship: String, Codable, CaseIterable {
    case myself = "Myself", spouse = "Spouse", child = "Child", parent = "Parent"
    case sibling = "Sibling", grandparent = "Grandparent", grandchild = "Grandchild", other = "Other"
}

// MARK: - CloudKit

extension Patient {
    static let recordType = "Patient"
    
    init?(from record: CKRecord) {
        guard record.recordType == Patient.recordType else { return nil }
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.guardianUserId = record["guardianUserId"] as? String ?? ""
        self.firstName = record["firstName"] as? String ?? ""
        self.lastName = record["lastName"] as? String ?? ""
        self.middleName = record["middleName"] as? String
        self.dateOfBirth = record["dateOfBirth"] as? Date
        self.gender = (record["gender"] as? String).flatMap { Gender(rawValue: $0) }
        self.relationship = (record["relationship"] as? String).flatMap { PatientRelationship(rawValue: $0) } ?? .other
        self.socialSecurityLast4 = record["socialSecurityLast4"] as? String
        self.addresses = (record["addressesJSON"] as? Data).flatMap { try? JSONDecoder().decode([PatientAddress].self, from: $0) } ?? []
        self.phoneNumbers = (record["phoneNumbersJSON"] as? Data).flatMap { try? JSONDecoder().decode([PatientPhone].self, from: $0) } ?? []
        self.emailAddresses = (record["emailAddressesJSON"] as? Data).flatMap { try? JSONDecoder().decode([PatientEmail].self, from: $0) } ?? []
        self.insurancePolicyIds = record["insurancePolicyIds"] as? [String] ?? []
        self.paymentMethodIds = record["paymentMethodIds"] as? [String] ?? []
        self.visitIds = record["visitIds"] as? [String] ?? []
        self.documentIds = record["documentIds"] as? [String] ?? []
        self.notes = record["notes"] as? String
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Patient.recordType)
        record["id"] = id; record["guardianUserId"] = guardianUserId
        record["firstName"] = firstName; record["lastName"] = lastName
        record["middleName"] = middleName; record["dateOfBirth"] = dateOfBirth
        record["gender"] = gender?.rawValue; record["relationship"] = relationship.rawValue
        record["socialSecurityLast4"] = socialSecurityLast4
        record["addressesJSON"] = try? JSONEncoder().encode(addresses)
        record["phoneNumbersJSON"] = try? JSONEncoder().encode(phoneNumbers)
        record["emailAddressesJSON"] = try? JSONEncoder().encode(emailAddresses)
        record["insurancePolicyIds"] = insurancePolicyIds
        record["paymentMethodIds"] = paymentMethodIds
        record["visitIds"] = visitIds; record["documentIds"] = documentIds
        record["notes"] = notes; record["createdAt"] = createdAt; record["updatedAt"] = Date()
        return record
    }
}
