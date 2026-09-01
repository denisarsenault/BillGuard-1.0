//
//  Claim.swift
//  BillGuard
//
//  Insurance claim model for tracking claim status
//

import Foundation
import CloudKit

// MARK: - Insurance Payment Model

struct InsurancePayment: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var payerName: String             // Insurance company name
    var amount: Double
    var paymentDate: Date
    var checkNumber: String?          // Check # or EFT/transaction ID
    var transactionType: TransactionType
    var eobReference: String?         // EOB document ID
    var notes: String?
    var createdAt: Date = Date()
    
    enum TransactionType: String, Codable, CaseIterable, Hashable {
        case check = "Check"
        case eft = "EFT/Direct Deposit"
        case virtualCard = "Virtual Card"
        case ach = "ACH Transfer"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .check: return "doc.plaintext"
            case .eft: return "arrow.left.arrow.right"
            case .virtualCard: return "creditcard"
            case .ach: return "building.columns"
            case .other: return "dollarsign.circle"
            }
        }
    }
    
    init(
        id: String = UUID().uuidString,
        payerName: String,
        amount: Double,
        paymentDate: Date = Date(),
        checkNumber: String? = nil,
        transactionType: TransactionType = .check,
        eobReference: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.payerName = payerName
        self.amount = amount
        self.paymentDate = paymentDate
        self.checkNumber = checkNumber
        self.transactionType = transactionType
        self.eobReference = eobReference
        self.notes = notes
    }
}

// MARK: - Patient Payment

struct PatientPayment: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var amount: Double
    var paymentDate: Date
    var paymentMethod: PaymentMethodType
    var confirmationNumber: String?
    var paidToProvider: String?       // Provider name payment was sent to
    var notes: String?
    var createdAt: Date = Date()
    
    enum PaymentMethodType: String, Codable, CaseIterable, Hashable {
        case creditCard = "Credit Card"
        case debitCard = "Debit Card"
        case check = "Check"
        case cash = "Cash"
        case bankTransfer = "Bank Transfer"
        case hsaFsa = "HSA/FSA"
        case onlinePortal = "Online Portal"
        case paymentPlan = "Payment Plan"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .creditCard: return "creditcard"
            case .debitCard: return "creditcard.trianglebadge.exclamationmark"
            case .check: return "doc.plaintext"
            case .cash: return "banknote"
            case .bankTransfer: return "building.columns"
            case .hsaFsa: return "cross.case"
            case .onlinePortal: return "globe"
            case .paymentPlan: return "calendar.badge.clock"
            case .other: return "dollarsign.circle"
            }
        }
    }
}

// MARK: - Claim Status

enum ClaimStatus: String, Codable, CaseIterable {
    case notSubmitted = "Not Submitted"
    case submitted = "Submitted"
    case pending = "Pending"
    case inReview = "In Review"
    case approved = "Approved"
    case partiallyApproved = "Partially Approved"
    case denied = "Denied"
    case appealed = "Appealed"
    case paid = "Paid"
    case closed = "Closed"
    
    var color: String {
        switch self {
        case .notSubmitted: return "gray"
        case .submitted, .pending, .inReview: return "blue"
        case .approved, .partiallyApproved: return "green"
        case .denied: return "red"
        case .appealed: return "orange"
        case .paid: return "green"
        case .closed: return "gray"
        }
    }
    
    var icon: String {
        switch self {
        case .notSubmitted: return "doc.badge.plus"
        case .submitted: return "paperplane.fill"
        case .pending: return "clock.fill"
        case .inReview: return "eye.fill"
        case .approved: return "checkmark.circle.fill"
        case .partiallyApproved: return "checkmark.circle.badge.questionmark"
        case .denied: return "xmark.circle.fill"
        case .appealed: return "arrow.uturn.backward.circle.fill"
        case .paid: return "dollarsign.circle.fill"
        case .closed: return "archivebox.fill"
        }
    }
}

// MARK: - Bill Status (Simplified for UI display)

enum BillStatus: String, CaseIterable {
    case resolved = "Resolved"
    case outstanding = "Outstanding"
    case waitingOnProcedureDetail = "Waiting on Procedure Detail"
    
    var icon: String {
        switch self {
        case .resolved: return "checkmark.circle.fill"
        case .outstanding: return "exclamationmark.circle.fill"
        case .waitingOnProcedureDetail: return "doc.badge.clock"
        }
    }
    
    var color: Color {
        switch self {
        case .resolved: return .green
        case .outstanding: return .red
        case .waitingOnProcedureDetail: return .orange
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .waitingOnProcedureDetail: return 0
        case .outstanding: return 1
        case .resolved: return 2
        }
    }
}

import SwiftUI

// MARK: - Claim Model

struct Claim: Identifiable, Codable, Hashable {
    var id: String
    var patientId: String
    var visitId: String?
    var billId: String?
    var policyId: String     // Insurance policy used
    var providerId: String?  // Healthcare provider
    var providerName: String? // Provider name for display
    
    // Claim Information
    var claimNumber: String?
    var status: ClaimStatus
    var serviceDate: Date
    var submissionDate: Date?
    
    // Financial
    var billedAmount: Double
    var allowedAmount: Double?
    var paidAmount: Double?
    var adjustmentAmount: Double?
    var patientResponsibility: Double?
    var deductibleApplied: Double?
    var coinsuranceAmount: Double?
    var copayAmount: Double?
    
    // Procedure/Diagnosis Codes
    var procedureCodes: [String]?   // CPT codes
    var diagnosisCodes: [String]?   // ICD-10 codes
    var modifiers: [String]?
    
    // EOB (Explanation of Benefits)
    var eobReceived: Bool
    var eobDate: Date?
    var eobDocumentId: String?      // Link to scanned EOB
    
    // Denial/Appeal
    var denialReason: String?
    var denialCode: String?
    var appealDeadline: Date?
    var appealDate: Date?
    var appealNotes: String?
    
    // Remittance
    var checkNumber: String?
    var paymentDate: Date?
    var paymentMethod: String?
    
    // Notes
    var notes: String?
    
    // Line Items (up to 300+ billable codes per bill)
    var lineItems: [BillLineItem]
    
    // Insurance Payments (tracked by check/transaction)
    var insurancePayments: [InsurancePayment]
    
    // Patient Payments (payments made by patient to provider)
    var patientPayments: [PatientPayment]?
    
    // Timeline/History
    var statusHistory: [ClaimStatusEntry]?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var recordId: String?
    
    init(
        id: String = UUID().uuidString,
        patientId: String,
        visitId: String? = nil,
        billId: String? = nil,
        policyId: String,
        providerId: String? = nil,
        providerName: String? = nil,
        claimNumber: String? = nil,
        status: ClaimStatus = .notSubmitted,
        serviceDate: Date,
        submissionDate: Date? = nil,
        billedAmount: Double,
        allowedAmount: Double? = nil,
        paidAmount: Double? = nil,
        adjustmentAmount: Double? = nil,
        patientResponsibility: Double? = nil,
        deductibleApplied: Double? = nil,
        coinsuranceAmount: Double? = nil,
        copayAmount: Double? = nil,
        procedureCodes: [String]? = nil,
        diagnosisCodes: [String]? = nil,
        modifiers: [String]? = nil,
        eobReceived: Bool = false,
        eobDate: Date? = nil,
        eobDocumentId: String? = nil,
        denialReason: String? = nil,
        denialCode: String? = nil,
        appealDeadline: Date? = nil,
        appealDate: Date? = nil,
        appealNotes: String? = nil,
        checkNumber: String? = nil,
        paymentDate: Date? = nil,
        paymentMethod: String? = nil,
        notes: String? = nil,
        lineItems: [BillLineItem] = [],
        insurancePayments: [InsurancePayment] = [],
        patientPayments: [PatientPayment]? = nil,
        statusHistory: [ClaimStatusEntry]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.visitId = visitId
        self.billId = billId
        self.policyId = policyId
        self.providerId = providerId
        self.providerName = providerName
        self.claimNumber = claimNumber
        self.status = status
        self.serviceDate = serviceDate
        self.submissionDate = submissionDate
        self.billedAmount = billedAmount
        self.allowedAmount = allowedAmount
        self.paidAmount = paidAmount
        self.adjustmentAmount = adjustmentAmount
        self.patientResponsibility = patientResponsibility
        self.deductibleApplied = deductibleApplied
        self.coinsuranceAmount = coinsuranceAmount
        self.copayAmount = copayAmount
        self.procedureCodes = procedureCodes
        self.diagnosisCodes = diagnosisCodes
        self.modifiers = modifiers
        self.eobReceived = eobReceived
        self.eobDate = eobDate
        self.eobDocumentId = eobDocumentId
        self.denialReason = denialReason
        self.denialCode = denialCode
        self.appealDeadline = appealDeadline
        self.appealDate = appealDate
        self.appealNotes = appealNotes
        self.checkNumber = checkNumber
        self.paymentDate = paymentDate
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.lineItems = lineItems
        self.insurancePayments = insurancePayments
        self.patientPayments = patientPayments
        self.statusHistory = statusHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    // --- Line Item Totals ---
    
    /// Sum of all line item charges
    var lineItemsTotalCharged: Double {
        lineItems.reduce(0) { $0 + $1.totalCharge }
    }
    
    /// Sum of all line item allowed amounts
    var lineItemsTotalAllowed: Double {
        lineItems.compactMap(\.allowedAmount).reduce(0, +)
    }
    
    /// Sum of all line item adjustments
    var lineItemsTotalAdjustments: Double {
        lineItems.compactMap(\.adjustmentAmount).reduce(0, +)
    }
    
    /// Sum of all line item insurance paid amounts
    var lineItemsTotalInsurancePaid: Double {
        lineItems.compactMap(\.insurancePaid).reduce(0, +)
    }
    
    /// Sum of all line item patient responsibility
    var lineItemsTotalPatientResponsibility: Double {
        lineItems.compactMap(\.patientResponsibility).reduce(0, +)
    }
    
    // --- Insurance Payment Totals ---
    
    /// Total of all recorded insurance payments (checks/transactions)
    var totalInsurancePayments: Double {
        insurancePayments.reduce(0) { $0 + $1.amount }
    }
    
    /// Number of insurance payment transactions
    var insurancePaymentCount: Int {
        insurancePayments.count
    }
    
    // --- Patient Payment Totals ---
    
    /// Total of all recorded patient payments
    var totalPatientPayments: Double {
        (patientPayments ?? []).reduce(0) { $0 + $1.amount }
    }
    
    /// Number of patient payment transactions
    var patientPaymentCount: Int {
        (patientPayments ?? []).count
    }
    
    /// Running balance: total charges minus insurance payments minus adjustments minus patient payments
    var runningBalance: Double {
        let charges = lineItems.isEmpty ? billedAmount : lineItemsTotalCharged
        let insPaid = insurancePayments.isEmpty ? (paidAmount ?? 0) : totalInsurancePayments
        let adj = lineItems.isEmpty ? (adjustmentAmount ?? 0) : lineItemsTotalAdjustments
        let patPaid = totalPatientPayments
        return max(0, charges - insPaid - adj - patPaid)
    }
    
    var outOfPocket: Double {
        patientResponsibility ?? (billedAmount - (paidAmount ?? 0) - (adjustmentAmount ?? 0))
    }
    
    var isPending: Bool {
        [.submitted, .pending, .inReview].contains(status)
    }
    
    var requiresAction: Bool {
        status == .denied || (status == .appealed && appealDeadline != nil && appealDeadline! < Date().addingTimeInterval(7 * 24 * 60 * 60))
    }
    
    var daysSinceSubmission: Int? {
        guard let submitted = submissionDate else { return nil }
        return Calendar.current.dateComponents([.day], from: submitted, to: Date()).day
    }
    
    /// Simplified bill status for UI display
    var billStatus: BillStatus {
        // Resolved: Paid, Closed, or no balance remaining
        if status == .paid || status == .closed {
            return .resolved
        }
        
        if let responsibility = patientResponsibility, responsibility <= 0 {
            return .resolved
        }
        
        // Waiting on Procedure Detail: No procedure codes
        if procedureCodes == nil || procedureCodes?.isEmpty == true {
            return .waitingOnProcedureDetail
        }
        
        // Outstanding: Has balance and has procedure codes
        return .outstanding
    }
    
    // MARK: - Methods
    
    mutating func updateStatus(to newStatus: ClaimStatus, note: String? = nil) {
        let entry = ClaimStatusEntry(status: newStatus, date: Date(), note: note)
        if statusHistory == nil {
            statusHistory = []
        }
        statusHistory?.append(entry)
        status = newStatus
        updatedAt = Date()
    }
}

// MARK: - Claim Status Entry (for history tracking)

struct ClaimStatusEntry: Codable, Hashable, Identifiable {
    var id: String
    var status: ClaimStatus
    var date: Date
    var note: String?
    
    init(id: String = UUID().uuidString, status: ClaimStatus, date: Date = Date(), note: String? = nil) {
        self.id = id
        self.status = status
        self.date = date
        self.note = note
    }
}

// MARK: - CloudKit Support

extension Claim {
    static let recordType = "Claim"
    
    init?(from record: CKRecord) {
        guard record.recordType == Claim.recordType,
              let patientId = record["patientId"] as? String,
              let policyId = record["policyId"] as? String,
              let statusRaw = record["status"] as? String,
              let status = ClaimStatus(rawValue: statusRaw),
              let serviceDate = record["serviceDate"] as? Date,
              let billedAmount = record["billedAmount"] as? Double else {
            return nil
        }
        
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.patientId = patientId
        self.visitId = record["visitId"] as? String
        self.billId = record["billId"] as? String
        self.policyId = policyId
        self.providerId = record["providerId"] as? String
        self.claimNumber = record["claimNumber"] as? String
        self.status = status
        self.serviceDate = serviceDate
        self.submissionDate = record["submissionDate"] as? Date
        self.billedAmount = billedAmount
        self.allowedAmount = record["allowedAmount"] as? Double
        self.paidAmount = record["paidAmount"] as? Double
        self.adjustmentAmount = record["adjustmentAmount"] as? Double
        self.patientResponsibility = record["patientResponsibility"] as? Double
        self.deductibleApplied = record["deductibleApplied"] as? Double
        self.coinsuranceAmount = record["coinsuranceAmount"] as? Double
        self.copayAmount = record["copayAmount"] as? Double
        
        if let codesData = record["procedureCodes"] as? Data {
            self.procedureCodes = try? JSONDecoder().decode([String].self, from: codesData)
        }
        
        if let diagData = record["diagnosisCodes"] as? Data {
            self.diagnosisCodes = try? JSONDecoder().decode([String].self, from: diagData)
        }
        
        if let modData = record["modifiers"] as? Data {
            self.modifiers = try? JSONDecoder().decode([String].self, from: modData)
        }
        
        self.eobReceived = record["eobReceived"] as? Bool ?? false
        self.eobDate = record["eobDate"] as? Date
        self.eobDocumentId = record["eobDocumentId"] as? String
        self.denialReason = record["denialReason"] as? String
        self.denialCode = record["denialCode"] as? String
        self.appealDeadline = record["appealDeadline"] as? Date
        self.appealDate = record["appealDate"] as? Date
        self.appealNotes = record["appealNotes"] as? String
        self.checkNumber = record["checkNumber"] as? String
        self.paymentDate = record["paymentDate"] as? Date
        self.paymentMethod = record["paymentMethod"] as? String
        self.notes = record["notes"] as? String
        
        if let historyData = record["statusHistory"] as? Data {
            self.statusHistory = try? JSONDecoder().decode([ClaimStatusEntry].self, from: historyData)
        }
        
        if let lineItemsData = record["lineItems"] as? Data {
            self.lineItems = (try? JSONDecoder().decode([BillLineItem].self, from: lineItemsData)) ?? []
        } else {
            self.lineItems = []
        }
        
        if let paymentsData = record["insurancePayments"] as? Data {
            self.insurancePayments = (try? JSONDecoder().decode([InsurancePayment].self, from: paymentsData)) ?? []
        } else {
            self.insurancePayments = []
        }
        
        if let patientPaymentsData = record["patientPayments"] as? Data {
            self.patientPayments = (try? JSONDecoder().decode([PatientPayment].self, from: patientPaymentsData))
        } else {
            self.patientPayments = nil
        }
        
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Claim.recordType)
        
        record["id"] = id
        record["patientId"] = patientId
        record["visitId"] = visitId
        record["billId"] = billId
        record["policyId"] = policyId
        record["providerId"] = providerId
        record["claimNumber"] = claimNumber
        record["status"] = status.rawValue
        record["serviceDate"] = serviceDate
        record["submissionDate"] = submissionDate
        record["billedAmount"] = billedAmount
        record["allowedAmount"] = allowedAmount
        record["paidAmount"] = paidAmount
        record["adjustmentAmount"] = adjustmentAmount
        record["patientResponsibility"] = patientResponsibility
        record["deductibleApplied"] = deductibleApplied
        record["coinsuranceAmount"] = coinsuranceAmount
        record["copayAmount"] = copayAmount
        
        if let codes = procedureCodes, let data = try? JSONEncoder().encode(codes) {
            record["procedureCodes"] = data
        }
        
        if let diag = diagnosisCodes, let data = try? JSONEncoder().encode(diag) {
            record["diagnosisCodes"] = data
        }
        
        if let mods = modifiers, let data = try? JSONEncoder().encode(mods) {
            record["modifiers"] = data
        }
        
        record["eobReceived"] = eobReceived
        record["eobDate"] = eobDate
        record["eobDocumentId"] = eobDocumentId
        record["denialReason"] = denialReason
        record["denialCode"] = denialCode
        record["appealDeadline"] = appealDeadline
        record["appealDate"] = appealDate
        record["appealNotes"] = appealNotes
        record["checkNumber"] = checkNumber
        record["paymentDate"] = paymentDate
        record["paymentMethod"] = paymentMethod
        record["notes"] = notes
        
        if let history = statusHistory, let data = try? JSONEncoder().encode(history) {
            record["statusHistory"] = data
        }
        
        if !lineItems.isEmpty, let data = try? JSONEncoder().encode(lineItems) {
            record["lineItems"] = data
        }
        
        if !insurancePayments.isEmpty, let data = try? JSONEncoder().encode(insurancePayments) {
            record["insurancePayments"] = data
        }
        
        if let pp = patientPayments, !pp.isEmpty, let data = try? JSONEncoder().encode(pp) {
            record["patientPayments"] = data
        }
        
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        
        return record
    }
}
