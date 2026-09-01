//
//  MedicalCodeDatabase.swift
//  BillGuardCore
//
//  Lightweight O(1) lookup over the bundled medical-code dataset, for callers
//  (e.g. the macOS app) that want to match scanned codes without a CloudKitService
//  instance. Backed by the same medical_codes.json shipped with the package.
//

import Foundation

public enum MedicalCodeDatabase {
    private static let index: [String: MedicalCode] = Dictionary(
        MedicalCode.sampleCodes.map { ($0.code.uppercased(), $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Exact code lookup (case-insensitive), e.g. "99213" → MedicalCode.
    public static func lookup(_ code: String) -> MedicalCode? {
        index[code.uppercased()]
    }

    public static var count: Int { index.count }
}
