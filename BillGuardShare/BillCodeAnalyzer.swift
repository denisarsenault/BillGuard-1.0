//
//  BillCodeAnalyzer.swift
//  BillGuardShare
//
//  Code extraction and overlap rules from docs/SHARE_EXTENSION_SPEC.md
//  (section 5). Pure Foundation so it can be exercised outside the extension.
//

import Foundation

enum BillCodeAnalyzer {

    static let icd10Pattern = #"\b[A-Z][0-9][0-9A-Z](?:\.[0-9A-Z]{1,4})?\b"#
    static let cptPattern = #"\b[0-9]{5}\b"#

    /// A code conflict that spans more than one captured page.
    struct Anomaly: Equatable, Sendable, Identifiable {
        enum Kind: Sendable {
            /// The same procedure code is billed on more than one page.
            case duplicateProcedure
            /// The same diagnosis appears on several pages, at least one of
            /// which carries no procedure code to link it to.
            case unlinkedDiagnosis
        }
        let code: String
        let kind: Kind
        let pageNumbers: [Int]
        var id: String { "\(kind)-\(code)" }
    }

    /// Every match of `pattern` in `text`, in order, repeats included.
    static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    // Context used to tell a billed procedure code from any other 5-digit number.
    private static let amountPattern = #"\$\s?\d|\b\d{1,3}(?:,\d{3})*\.\d{2}\b"#
    private static let zipPrefixPattern =
        #"\b(?:AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)[.,]?\s+$"#
    private static let identifierLabelPattern =
        #"(?i)\b(?:account|acct|receipt|invoice|statement|claim|mrn|member|policy|group|subscriber|reference|ref|confirmation|check|zip|box|suite|ste|apt|unit|ext|npi|tin|id)\b\s*(?:number|num|no|code)?\s*[.:#]*\s*$"#
    private static let codeLabelPattern =
        #"(?i)\b(?:cpt|hcpcs|procedures?|proc|codes?)\b\s*(?:codes?)?\s*[.:#]*\s*$"#

    /// Procedure codes in `text`, in order, repeats included. The spec's CPT
    /// pattern finds the candidates; a candidate is kept only when it reads as a
    /// billed code: it is a known code, it is labelled as one, or its line
    /// carries a charge. ZIP codes, labelled identifiers (account, receipt,
    /// claim…), pieces of hyphenated IDs and money amounts are dropped, since
    /// those repeat in page headers and would raise false cross-page conflicts.
    static func procedureCodes(in text: String, knownCodes: Set<String>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: cptPattern) else { return [] }
        var codes: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let lineHasCharge = line.range(of: amountPattern, options: .regularExpression) != nil
            for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let code = nsLine.substring(with: match.range)
                let before = nsLine.substring(to: match.range.location)
                let after = nsLine.substring(from: match.range.location + match.range.length)

                let isPartOfNumberOrID = before.hasSuffix("$") || before.hasSuffix("$ ")
                    || before.hasSuffix("-")
                    || after.range(of: #"^(?:\.\d|-\d{4}\b)"#, options: .regularExpression) != nil
                if isPartOfNumberOrID { continue }
                if before.range(of: zipPrefixPattern, options: .regularExpression) != nil { continue }
                if before.range(of: identifierLabelPattern, options: .regularExpression) != nil { continue }

                let isLabelled = before.range(of: codeLabelPattern, options: .regularExpression) != nil
                if knownCodes.contains(code) || isLabelled || lineHasCharge {
                    codes.append(code)
                }
            }
        }
        return codes
    }

    /// Build a page from OCR text: unique codes in reading order, plus the
    /// procedure codes billed more than once on this same page.
    static func makePage(number: Int, rawText: String,
                         knownCodes: Set<String> = KnownProcedureCodes.bundled) -> MedicalBillPage {
        let diagnostic = matches(of: icd10Pattern, in: rawText)
        let procedure = procedureCodes(in: rawText, knownCodes: knownCodes)
        var counts: [String: Int] = [:]
        for code in procedure { counts[code, default: 0] += 1 }
        return MedicalBillPage(
            pageNumber: number,
            rawText: rawText,
            identifiedDiagnosticCodes: unique(diagnostic),
            identifiedProcedureCodes: unique(procedure),
            overlappingCodes: unique(procedure).filter { (counts[$0] ?? 0) > 1 })
    }

    /// Cross-page rule: flag a procedure code billed on more than one page, and
    /// a diagnosis repeated across pages where one of them has no procedure.
    static func crossPageAnomalies(in pages: [MedicalBillPage]) -> [Anomaly] {
        var anomalies: [Anomaly] = []

        for code in unique(pages.flatMap(\.identifiedProcedureCodes)) {
            let hits = pages.filter { $0.identifiedProcedureCodes.contains(code) }
            if hits.count > 1 {
                anomalies.append(Anomaly(code: code, kind: .duplicateProcedure,
                                         pageNumbers: hits.map(\.pageNumber)))
            }
        }
        for code in unique(pages.flatMap(\.identifiedDiagnosticCodes)) {
            let hits = pages.filter { $0.identifiedDiagnosticCodes.contains(code) }
            if hits.count > 1, hits.contains(where: { $0.identifiedProcedureCodes.isEmpty }) {
                anomalies.append(Anomaly(code: code, kind: .unlinkedDiagnosis,
                                         pageNumbers: hits.map(\.pageNumber)))
            }
        }
        return anomalies
    }

    private static func unique(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }
}
