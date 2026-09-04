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

    /// All codes in the bundled dataset.
    public static var allCodes: [MedicalCode] { MedicalCode.sampleCodes }

    /// Fuzzy search over code, description, category, and keywords. Ranks exact
    /// code matches and prefix matches ahead of substring matches.
    public static func search(_ query: String, type: MedicalCodeType? = nil, limit: Int = 100) -> [MedicalCode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var pool = MedicalCode.sampleCodes
        if let type { pool = pool.filter { $0.codeType == type } }
        guard !q.isEmpty else { return Array(pool.prefix(limit)) }

        func rank(_ c: MedicalCode) -> Int? {
            let code = c.code.lowercased()
            if code == q { return 0 }
            if code.hasPrefix(q) { return 1 }
            if c.shortDescription.lowercased().hasPrefix(q) { return 2 }
            if code.contains(q) { return 3 }
            if c.shortDescription.lowercased().contains(q) { return 4 }
            if c.category.lowercased().contains(q) { return 5 }
            if c.keywords.contains(where: { $0.lowercased().contains(q) }) { return 6 }
            return nil
        }
        return pool.compactMap { c in rank(c).map { (c, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.code < $1.0.code }
            .prefix(limit)
            .map { $0.0 }
    }
}
