//
//  BillTemplates.swift
//  BillGuardCore
//
//  Provider bill template types used by the shared BillParser. Extracted from the
//  iOS app's BillScannerView so both platforms share one definition.
//

import Foundation

enum BillFormat: String, Codable, CaseIterable {
    case standard              = "Standard"
    case accountStatement      = "Account Statement"
    case explanationOfBenefits = "Explanation of Benefits"
    case custom                = "Custom"

    var icon: String {
        switch self {
        case .standard:              return "doc.text"
        case .accountStatement:      return "tablecells"
        case .explanationOfBenefits: return "doc.badge.ellipsis"
        case .custom:                return "wrench.and.screwdriver"
        }
    }
}

struct ProcedureColumnLayout: Codable, Equatable {
    var chargesColumnKeywords:    [String] = ["charges", "debits", "billed", "amount"]
    var insurancePendingKeywords: [String] = ["insurance pending", "ins pending", "pending"]
    var paymentsColumnKeywords:   [String] = ["payments", "credits", "paid", "payment"]
    var patientAmountKeywords:    [String] = ["patient amount", "patient", "you owe", "balance"]
    var visitTotalLabels:         [String] = ["visit total", "---- visit total", "subtotal"]
    var voucherLabels:            [String] = ["voucher:", "voucher #", "claim #", "visit #"]
    var accountingRowKeywords:    [String] = [
        "payment", "adjustment", "transfer", "credit card", "self pay",
        "mastercard", "visa", "check", "write off", "write-off",
        "courtesy", "refund", "collection", "contractual"
    ]
    var useColumnPositionForCharge: Bool = false
    var chargesColumnPosition:  Int = 45
    var paymentsColumnPosition: Int = 60
    var patientAmountPosition:  Int = 75
}

struct ScanBoxRect: Codable, Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
    init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 0.25) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

struct ProviderBillTemplate: Codable, Identifiable, Equatable {
    var id:            UUID   = UUID()
    var displayName:   String
    var matchKeywords: [String]
    var billFormat:    BillFormat = .standard
    var procedureColumnLayout: ProcedureColumnLayout?
    var providerBoxPosition:   ScanBoxRect? = nil
    var patientBoxPosition:    ScanBoxRect? = nil
    var insuranceBoxPosition:  ScanBoxRect? = nil
    var procedureBoxPosition:  ScanBoxRect? = nil
    var dateCreated: Date   = Date()
    var lastUsed:    Date   = Date()
    var scanCount:   Int    = 0
    var notes:       String = ""
    static func == (lhs: ProviderBillTemplate, rhs: ProviderBillTemplate) -> Bool { lhs.id == rhs.id }
}
