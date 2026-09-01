//
//  Provider.swift
//  BillGuard
//
//  Healthcare provider model (clinic, doctor, hospital, pharmacy)
//

import Foundation
import CloudKit
import CoreLocation

// MARK: - Provider Type

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case clinic = "Clinic"
    case doctor = "Doctor"
    case hospital = "Hospital"
    case pharmacy = "Pharmacy"
    case laboratory = "Laboratory"
    case imagingCenter = "Imaging Center"
    case urgentCare = "Urgent Care"
    case emergencyRoom = "Emergency Room"
    case specialist = "Specialist"
    case dentist = "Dentist"
    case optometrist = "Optometrist"
    case therapist = "Therapist"
    case other = "Other"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .clinic: return "cross.case.fill"
        case .doctor: return "stethoscope"
        case .hospital: return "building.2.fill"
        case .pharmacy: return "pills.fill"
        case .laboratory: return "flask.fill"
        case .imagingCenter: return "waveform.path.ecg"
        case .urgentCare: return "bolt.heart.fill"
        case .emergencyRoom: return "cross.circle.fill"
        case .specialist: return "person.badge.plus"
        case .dentist: return "mouth.fill"
        case .optometrist: return "eye.fill"
        case .therapist: return "brain.head.profile"
        case .other: return "building.fill"
        }
    }
}

// MARK: - Provider Specialty

enum ProviderSpecialty: String, Codable, CaseIterable {
    case generalPractice = "General Practice"
    case familyMedicine = "Family Medicine"
    case internalMedicine = "Internal Medicine"
    case pediatrics = "Pediatrics"
    case cardiology = "Cardiology"
    case dermatology = "Dermatology"
    case endocrinology = "Endocrinology"
    case gastroenterology = "Gastroenterology"
    case neurology = "Neurology"
    case obgyn = "OB/GYN"
    case oncology = "Oncology"
    case ophthalmology = "Ophthalmology"
    case orthopedics = "Orthopedics"
    case psychiatry = "Psychiatry"
    case pulmonology = "Pulmonology"
    case radiology = "Radiology"
    case rheumatology = "Rheumatology"
    case surgery = "Surgery"
    case urology = "Urology"
    case pharmacy = "Pharmacy"
    case dental = "Dental"
    case other = "Other"
}

// MARK: - Provider Reminder Settings

struct ProviderReminderSettings: Codable, Hashable {
    var isEnabled: Bool = true
    var geofenceRadius: Double = 100  // meters
    var remindOnArrival: Bool = true
    var remindOnDeparture: Bool = true
    var reminderMessage: String = "Remember to:\n• Take photos of all documents\n• Request itemized bill\n• Get procedure codes (CPT)\n• Ask for diagnosis codes (ICD-10)"
    
    // What to remind about
    var remindToPhotograph: Bool = true
    var remindForProcedureCodes: Bool = true
    var remindForDiagnosisCodes: Bool = true
    var remindForItemizedBill: Bool = true
    var remindForFollowUpDocs: Bool = true
    
    static let `default` = ProviderReminderSettings()
}

// MARK: - Provider Model

struct Provider: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var providerType: ProviderType
    var specialty: ProviderSpecialty?
    
    // Contact Information
    var address: Address?
    var phones: [PhoneNumber]
    var emails: [String]
    var fax: String?
    var website: String?
    
    // Business Information
    var npi: String?  // National Provider Identifier
    var taxId: String?
    var licenseNumber: String?
    
    // Billing Contact
    var billingAddress: Address?
    var billingPhone: String?
    var billingEmail: String?
    var billingFax: String?
    
    // Hours of Operation
    var hoursOfOperation: [DayHours]?
    
    // Location-based Reminder Settings
    var reminderSettings: ProviderReminderSettings
    var isGeofenceActive: Bool
    var lastVisitDate: Date?
    var visitCount: Int
    
    // Notes
    var notes: String?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var recordId: String?
    
    init(
        id: String = UUID().uuidString,
        name: String,
        providerType: ProviderType,
        specialty: ProviderSpecialty? = nil,
        address: Address? = nil,
        phones: [PhoneNumber] = [],
        emails: [String] = [],
        fax: String? = nil,
        website: String? = nil,
        npi: String? = nil,
        taxId: String? = nil,
        licenseNumber: String? = nil,
        billingAddress: Address? = nil,
        billingPhone: String? = nil,
        billingEmail: String? = nil,
        billingFax: String? = nil,
        hoursOfOperation: [DayHours]? = nil,
        reminderSettings: ProviderReminderSettings = .default,
        isGeofenceActive: Bool = true,
        lastVisitDate: Date? = nil,
        visitCount: Int = 0,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.specialty = specialty
        self.address = address
        self.phones = phones
        self.emails = emails
        self.fax = fax
        self.website = website
        self.npi = npi
        self.taxId = taxId
        self.licenseNumber = licenseNumber
        self.billingAddress = billingAddress
        self.billingPhone = billingPhone
        self.billingEmail = billingEmail
        self.billingFax = billingFax
        self.hoursOfOperation = hoursOfOperation
        self.reminderSettings = reminderSettings
        self.isGeofenceActive = isGeofenceActive
        self.lastVisitDate = lastVisitDate
        self.visitCount = visitCount
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Custom Decoding for Legacy Data
    
    enum CodingKeys: String, CodingKey {
        case id, name, providerType, specialty
        case address, phones, emails, fax, website
        case npi, taxId, licenseNumber
        case billingAddress, billingPhone, billingEmail, billingFax
        case hoursOfOperation
        case reminderSettings, isGeofenceActive, lastVisitDate, visitCount
        case notes, createdAt, updatedAt, recordId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        providerType = try container.decode(ProviderType.self, forKey: .providerType)
        
        // Optional fields
        specialty = try container.decodeIfPresent(ProviderSpecialty.self, forKey: .specialty)
        address = try container.decodeIfPresent(Address.self, forKey: .address)
        phones = try container.decodeIfPresent([PhoneNumber].self, forKey: .phones) ?? []
        emails = try container.decodeIfPresent([String].self, forKey: .emails) ?? []
        fax = try container.decodeIfPresent(String.self, forKey: .fax)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        npi = try container.decodeIfPresent(String.self, forKey: .npi)
        taxId = try container.decodeIfPresent(String.self, forKey: .taxId)
        licenseNumber = try container.decodeIfPresent(String.self, forKey: .licenseNumber)
        billingAddress = try container.decodeIfPresent(Address.self, forKey: .billingAddress)
        billingPhone = try container.decodeIfPresent(String.self, forKey: .billingPhone)
        billingEmail = try container.decodeIfPresent(String.self, forKey: .billingEmail)
        billingFax = try container.decodeIfPresent(String.self, forKey: .billingFax)
        hoursOfOperation = try container.decodeIfPresent([DayHours].self, forKey: .hoursOfOperation)
        
        // New fields with defaults for legacy data
        reminderSettings = try container.decodeIfPresent(ProviderReminderSettings.self, forKey: .reminderSettings) ?? .default
        isGeofenceActive = try container.decodeIfPresent(Bool.self, forKey: .isGeofenceActive) ?? true
        lastVisitDate = try container.decodeIfPresent(Date.self, forKey: .lastVisitDate)
        visitCount = try container.decodeIfPresent(Int.self, forKey: .visitCount) ?? 0
        
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        recordId = try container.decodeIfPresent(String.self, forKey: .recordId)
    }
    
    // MARK: - Computed Properties
    
    var primaryPhone: String? {
        phones.first?.number
    }
    
    var primaryEmail: String? {
        emails.first
    }
    
    var displayAddress: String? {
        address?.formatted
    }
    
    var hasLocation: Bool {
        address?.hasCoordinates ?? false
    }
    
    var coordinate: CLLocationCoordinate2D? {
        address?.coordinate
    }
    
    var canSetupGeofence: Bool {
        hasLocation && reminderSettings.isEnabled
    }
    
    // Geofence region identifier
    var geofenceIdentifier: String {
        "provider_\(id)"
    }
}

// MARK: - Phone Number

struct PhoneNumber: Codable, Hashable, Identifiable {
    var id: String
    var label: PhoneLabel
    var number: String
    var isPrimary: Bool
    
    init(id: String = UUID().uuidString, label: PhoneLabel = .main, number: String, isPrimary: Bool = false) {
        self.id = id
        self.label = label
        self.number = number
        self.isPrimary = isPrimary
    }
}

enum PhoneLabel: String, Codable, CaseIterable {
    case main = "Main"
    case mobile = "Mobile"
    case office = "Office"
    case home = "Home"
    case work = "Work"
    case fax = "Fax"
    case billing = "Billing"
    case appointments = "Appointments"
    case emergency = "Emergency"
    case other = "Other"
}

// MARK: - Hours of Operation

struct DayHours: Codable, Hashable, Identifiable {
    var id: String
    var day: DayOfWeek
    var isOpen: Bool
    var openTime: Date?
    var closeTime: Date?
    
    init(id: String = UUID().uuidString, day: DayOfWeek, isOpen: Bool = true, openTime: Date? = nil, closeTime: Date? = nil) {
        self.id = id
        self.day = day
        self.isOpen = isOpen
        self.openTime = openTime
        self.closeTime = closeTime
    }
    
    var displayHours: String {
        guard isOpen, let open = openTime, let close = closeTime else {
            return "Closed"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: open)) - \(formatter.string(from: close))"
    }
}

enum DayOfWeek: String, Codable, CaseIterable {
    case sunday = "Sunday"
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    
    var shortName: String {
        String(rawValue.prefix(3))
    }
}

// MARK: - CloudKit Support

extension Provider {
    static let recordType = "Provider"
    
    init?(from record: CKRecord) {
        guard record.recordType == Provider.recordType,
              let name = record["name"] as? String,
              let typeRaw = record["providerType"] as? String,
              let providerType = ProviderType(rawValue: typeRaw) else {
            return nil
        }
        
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.name = name
        self.providerType = providerType
        
        if let specialtyRaw = record["specialty"] as? String {
            self.specialty = ProviderSpecialty(rawValue: specialtyRaw)
        }
        
        if let addressData = record["address"] as? Data {
            self.address = try? JSONDecoder().decode(Address.self, from: addressData)
        }
        
        if let phonesData = record["phones"] as? Data {
            self.phones = (try? JSONDecoder().decode([PhoneNumber].self, from: phonesData)) ?? []
        } else {
            self.phones = []
        }
        
        if let emailsData = record["emails"] as? Data {
            self.emails = (try? JSONDecoder().decode([String].self, from: emailsData)) ?? []
        } else {
            self.emails = []
        }
        
        self.fax = record["fax"] as? String
        self.website = record["website"] as? String
        self.npi = record["npi"] as? String
        self.taxId = record["taxId"] as? String
        self.licenseNumber = record["licenseNumber"] as? String
        
        if let billingAddressData = record["billingAddress"] as? Data {
            self.billingAddress = try? JSONDecoder().decode(Address.self, from: billingAddressData)
        }
        
        self.billingPhone = record["billingPhone"] as? String
        self.billingEmail = record["billingEmail"] as? String
        self.billingFax = record["billingFax"] as? String
        
        if let hoursData = record["hoursOfOperation"] as? Data {
            self.hoursOfOperation = try? JSONDecoder().decode([DayHours].self, from: hoursData)
        }
        
        // Reminder settings
        if let reminderData = record["reminderSettings"] as? Data {
            self.reminderSettings = (try? JSONDecoder().decode(ProviderReminderSettings.self, from: reminderData)) ?? .default
        } else {
            self.reminderSettings = .default
        }
        
        self.isGeofenceActive = record["isGeofenceActive"] as? Bool ?? true
        self.lastVisitDate = record["lastVisitDate"] as? Date
        self.visitCount = record["visitCount"] as? Int ?? 0
        
        self.notes = record["notes"] as? String
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Provider.recordType)
        
        record["id"] = id
        record["name"] = name
        record["providerType"] = providerType.rawValue
        record["specialty"] = specialty?.rawValue
        
        if let address = address, let data = try? JSONEncoder().encode(address) {
            record["address"] = data
        }
        
        if let data = try? JSONEncoder().encode(phones) {
            record["phones"] = data
        }
        
        if let data = try? JSONEncoder().encode(emails) {
            record["emails"] = data
        }
        
        record["fax"] = fax
        record["website"] = website
        record["npi"] = npi
        record["taxId"] = taxId
        record["licenseNumber"] = licenseNumber
        
        if let billingAddress = billingAddress, let data = try? JSONEncoder().encode(billingAddress) {
            record["billingAddress"] = data
        }
        
        record["billingPhone"] = billingPhone
        record["billingEmail"] = billingEmail
        record["billingFax"] = billingFax
        
        if let hours = hoursOfOperation, let data = try? JSONEncoder().encode(hours) {
            record["hoursOfOperation"] = data
        }
        
        // Reminder settings
        if let data = try? JSONEncoder().encode(reminderSettings) {
            record["reminderSettings"] = data
        }
        
        record["isGeofenceActive"] = isGeofenceActive
        record["lastVisitDate"] = lastVisitDate
        record["visitCount"] = visitCount
        
        record["notes"] = notes
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        
        return record
    }
}
