//
//  MedicalBillModels.swift
//  BillGuardShare
//
//  Multi-page bill schema from docs/SHARE_EXTENSION_SPEC.md (section 4).
//

import Foundation

public struct MedicalBillPage: Codable, Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var pageNumber: Int
    public var rawText: String
    public var identifiedDiagnosticCodes: [String] // Regex-extracted ICD-10 codes
    public var identifiedProcedureCodes: [String]  // Regex-extracted CPT/HCPCS codes
    public var overlappingCodes: [String]          // Matches occurring within the same page context
}

public struct MedicalBillPayload: Codable, Sendable {
    public var sourceURL: String?
    public var totalPages: Int
    public var pages: [MedicalBillPage]
    public var totalRiskAnomaliesFound: Int
    public var clientScannedAt: Date
}
