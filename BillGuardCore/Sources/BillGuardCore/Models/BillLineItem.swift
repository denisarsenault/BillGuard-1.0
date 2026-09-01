//
//  BillLineItem.swift
//  BillGuardCore
//
//  A single billed procedure/charge line on a claim. Platform-agnostic model
//  (extracted from the iOS app's BillDetailViews so it can be shared).
//

import Foundation

struct BillLineItem: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var procedureCode: String?
    var procedureDescription: String
    var diagnosisCodes: [String]?
    var modifiers: [String]?
    var serviceDate: Date
    var quantity: Int = 1
    var unitCharge: Double
    var totalCharge: Double
    var allowedAmount: Double?
    var adjustmentAmount: Double?
    var insurancePaid: Double?
    var patientResponsibility: Double?
    var denialCode: String?
    var denialReason: String?
    var notes: String?

    init(
        id: String = UUID().uuidString,
        procedureCode: String? = nil,
        procedureDescription: String,
        diagnosisCodes: [String]? = nil,
        modifiers: [String]? = nil,
        serviceDate: Date = Date(),
        quantity: Int = 1,
        unitCharge: Double,
        totalCharge: Double? = nil,
        allowedAmount: Double? = nil,
        adjustmentAmount: Double? = nil,
        insurancePaid: Double? = nil,
        patientResponsibility: Double? = nil,
        denialCode: String? = nil,
        denialReason: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.procedureCode = procedureCode
        self.procedureDescription = procedureDescription
        self.diagnosisCodes = diagnosisCodes
        self.modifiers = modifiers
        self.serviceDate = serviceDate
        self.quantity = quantity
        self.unitCharge = unitCharge
        self.totalCharge = totalCharge ?? (Double(quantity) * unitCharge)
        self.allowedAmount = allowedAmount
        self.adjustmentAmount = adjustmentAmount
        self.insurancePaid = insurancePaid
        self.patientResponsibility = patientResponsibility
        self.denialCode = denialCode
        self.denialReason = denialReason
        self.notes = notes
    }
}
