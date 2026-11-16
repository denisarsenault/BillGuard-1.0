//
//  CloudKitManager.swift
//  BillGuardShare
//
//  Saves a committed multi-page scan to the private CloudKit database
//  (spec section 4), using BillGuard's real container.
//

import Foundation
import CloudKit

public actor CloudKitManager {
    public static let shared = CloudKitManager()
    private let container = CKContainer(identifier: "iCloud.com.billguard.BillGuard")
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    public enum SaveError: LocalizedError {
        case noAccount
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .noAccount:
                return "Sign in to iCloud in Settings to save this bill. Your captured pages are kept."
            case .encodingFailed:
                return "The captured pages could not be prepared for saving."
            }
        }
    }

    public func saveMultiPageBill(payload: MedicalBillPayload) async throws {
        guard try await container.accountStatus() == .available else { throw SaveError.noAccount }

        guard let encodedPages = try? JSONEncoder().encode(payload.pages),
              let pagesJSON = String(data: encodedPages, encoding: .utf8)
        else { throw SaveError.encodingFailed }

        let record = CKRecord(recordType: "MedicalBillScan")
        record["sourceURL"] = payload.sourceURL
        record["scannedAt"] = payload.clientScannedAt
        record["status"] = "PendingReview"
        record["anomalyCount"] = payload.totalRiskAnomaliesFound
        record["pageStructureJSON"] = pagesJSON

        _ = try await privateDB.save(record)
    }
}
