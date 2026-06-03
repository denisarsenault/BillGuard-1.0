//
//  Visit.swift
//  BillGuard
//
//  Visit model linking patient, provider, and claims
//

import Foundation
import CloudKit

// MARK: - Visit

struct Visit: Identifiable, Codable, Hashable {
    var id: String
    var patientId: String
    var providerId: String
    
    // Visit Details
    var visitDate: Date
    var visitType: VisitType
    var status: VisitStatus
    
    // Reason & Diagnosis
    var reasonForVisit: String?
    var primaryDiagnosis: String?
    var diagnosisCodes: [String]  // ICD-10 codes
    var procedureCodes: [String]  // CPT codes
    
    // Provider Info (denormalized for display)
    var providerName: String?
    var providerType: ProviderType?
    
    // Insurance
    var insurancePolicyId: String?
    var copayAmount: Double?
    var copayPaid: Bool
    
    // Linked Data
    var claimIds: [String]
    var documentIds: [String]  // Scanned invoices, receipts
    
    // Follow-up
    var followUpRequired: Bool
    var followUpDate: Date?
    var followUpNotes: String?
    
    // Notes
    var notes: String?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var recordId: String?
    
    init(
        id: String = UUID().uuidString,
        patientId: String,
        providerId: String,
        visitDate: Date = Date(),
        visitType: VisitType = .officeVisit,
        status: VisitStatus = .scheduled,
        reasonForVisit: String? = nil,
        primaryDiagnosis: String? = nil,
        diagnosisCodes: [String] = [],
        procedureCodes: [String] = [],
        providerName: String? = nil,
        providerType: ProviderType? = nil,
        insurancePolicyId: String? = nil,
        copayAmount: Double? = nil,
        copayPaid: Bool = false,
        claimIds: [String] = [],
        documentIds: [String] = [],
        followUpRequired: Bool = false,
        followUpDate: Date? = nil,
        followUpNotes: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.providerId = providerId
        self.visitDate = visitDate
        self.visitType = visitType
        self.status = status
        self.reasonForVisit = reasonForVisit
        self.primaryDiagnosis = primaryDiagnosis
        self.diagnosisCodes = diagnosisCodes
        self.procedureCodes = procedureCodes
        self.providerName = providerName
        self.providerType = providerType
        self.insurancePolicyId = insurancePolicyId
        self.copayAmount = copayAmount
        self.copayPaid = copayPaid
        self.claimIds = claimIds
        self.documentIds = documentIds
        self.followUpRequired = followUpRequired
        self.followUpDate = followUpDate
        self.followUpNotes = followUpNotes
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: visitDate)
    }
    
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: visitDate)
    }
    
    var isPast: Bool {
        visitDate < Date()
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(visitDate)
    }
    
    var displayTitle: String {
        if let name = providerName {
            return "\(visitType.rawValue) - \(name)"
        }
        return visitType.rawValue
    }
}

// MARK: - Visit Type

enum VisitType: String, Codable, CaseIterable {
    case officeVisit = "Office Visit"
    case telehealth = "Telehealth"
    case urgentCare = "Urgent Care"
    case emergency = "Emergency"
    case hospital = "Hospital"
    case surgery = "Surgery"
    case labWork = "Lab Work"
    case imaging = "Imaging"
    case pharmacy = "Pharmacy"
    case dental = "Dental"
    case vision = "Vision"
    case therapy = "Therapy"
    case preventiveCare = "Preventive Care"
    case followUp = "Follow-up"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .officeVisit: return "stethoscope"
        case .telehealth: return "video.fill"
        case .urgentCare: return "cross.case.fill"
        case .emergency: return "cross.circle.fill"
        case .hospital: return "building.2.fill"
        case .surgery: return "scissors"
        case .labWork: return "testtube.2"
        case .imaging: return "waveform.path.ecg"
        case .pharmacy: return "pills.fill"
        case .dental: return "mouth.fill"
        case .vision: return "eye.fill"
        case .therapy: return "figure.walk"
        case .preventiveCare: return "heart.fill"
        case .followUp: return "arrow.clockwise"
        case .other: return "cross.case.fill"
        }
    }
}

// MARK: - Visit Status

enum VisitStatus: String, Codable, CaseIterable {
    case scheduled = "Scheduled"
    case confirmed = "Confirmed"
    case checkedIn = "Checked In"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case noShow = "No Show"
    case rescheduled = "Rescheduled"
    
    var color: String {
        switch self {
        case .scheduled: return "blue"
        case .confirmed: return "green"
        case .checkedIn: return "purple"
        case .inProgress: return "orange"
        case .completed: return "gray"
        case .cancelled: return "red"
        case .noShow: return "red"
        case .rescheduled: return "yellow"
        }
    }
    
    var icon: String {
        switch self {
        case .scheduled: return "calendar"
        case .confirmed: return "checkmark.circle"
        case .checkedIn: return "person.badge.clock"
        case .inProgress: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .noShow: return "person.slash"
        case .rescheduled: return "arrow.clockwise"
        }
    }
}

// MARK: - CloudKit Extension

extension Visit {
    static let recordType = "Visit"
    
    init?(from record: CKRecord) {
        guard record.recordType == Visit.recordType else { return nil }
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.patientId = record["patientId"] as? String ?? ""
        self.providerId = record["providerId"] as? String ?? ""
        self.visitDate = record["visitDate"] as? Date ?? Date()
        self.visitType = (record["visitType"] as? String).flatMap { VisitType(rawValue: $0) } ?? .officeVisit
        self.status = (record["status"] as? String).flatMap { VisitStatus(rawValue: $0) } ?? .scheduled
        self.reasonForVisit = record["reasonForVisit"] as? String
        self.primaryDiagnosis = record["primaryDiagnosis"] as? String
        self.diagnosisCodes = record["diagnosisCodes"] as? [String] ?? []
        self.procedureCodes = record["procedureCodes"] as? [String] ?? []
        self.providerName = record["providerName"] as? String
        self.providerType = (record["providerType"] as? String).flatMap { ProviderType(rawValue: $0) }
        self.insurancePolicyId = record["insurancePolicyId"] as? String
        self.copayAmount = record["copayAmount"] as? Double
        self.copayPaid = record["copayPaid"] as? Bool ?? false
        self.claimIds = record["claimIds"] as? [String] ?? []
        self.documentIds = record["documentIds"] as? [String] ?? []
        self.followUpRequired = record["followUpRequired"] as? Bool ?? false
        self.followUpDate = record["followUpDate"] as? Date
        self.followUpNotes = record["followUpNotes"] as? String
        self.notes = record["notes"] as? String
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Visit.recordType)
        record["id"] = id; record["patientId"] = patientId; record["providerId"] = providerId
        record["visitDate"] = visitDate; record["visitType"] = visitType.rawValue
        record["status"] = status.rawValue; record["reasonForVisit"] = reasonForVisit
        record["primaryDiagnosis"] = primaryDiagnosis; record["diagnosisCodes"] = diagnosisCodes
        record["procedureCodes"] = procedureCodes; record["providerName"] = providerName
        record["providerType"] = providerType?.rawValue; record["insurancePolicyId"] = insurancePolicyId
        record["copayAmount"] = copayAmount; record["copayPaid"] = copayPaid
        record["claimIds"] = claimIds; record["documentIds"] = documentIds
        record["followUpRequired"] = followUpRequired; record["followUpDate"] = followUpDate
        record["followUpNotes"] = followUpNotes; record["notes"] = notes
        record["createdAt"] = createdAt; record["updatedAt"] = Date()
        return record
    }
}

