//
//  KnownProcedureCodes.swift
//  BillGuardShare
//
//  The CPT and HCPCS codes in BillGuard's bundled code database. Used only as a
//  positive signal: the database is small, so a code missing from it is not
//  evidence that a token isn't a procedure code.
//

import Foundation

enum KnownProcedureCodes {

    /// Codes from the medical_codes.json shipped in the extension bundle.
    static let bundled: Set<String> = load(
        from: Bundle.main.url(forResource: "medical_codes", withExtension: "json"))

    static func load(from url: URL?) -> Set<String> {
        struct Entry: Decodable { let code: String }
        guard let url, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        let shape = "^(?:\(BillCodeAnalyzer.cptPattern)|\(BillCodeAnalyzer.hcpcsPattern))$"
        return Set(entries.map(\.code).filter {
            $0.range(of: shape, options: .regularExpression) != nil
        })
    }
}
