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
    /// HCPCS Level II: one letter (the ranges in use) and four digits, e.g. J1885.
    static let hcpcsPattern = #"\b[ABCDEGHJKLMPQRSTUV][0-9]{4}\b"#
    /// Either kind of procedure code (capture group 1), so matches come back in
    /// reading order. A billing modifier may be printed straight after the code
    /// with no space ("93976TC", "J1885JW"); it is matched but not captured, so
    /// the base code is what gets recorded. Only modifiers containing a letter
    /// are accepted glued on: seven digits in a row is an ID, not a code plus a
    /// numeric modifier. A letter-first code followed by XA, XD or XS is an
    /// undotted ICD-10 code with its 7th character ("T8111XA"), not HCPCS.
    private static let procedurePattern =
        #"\b([0-9]{5}|[ABCDEGHJKLMPQRSTUV][0-9]{4}(?!X[ADS]\b))(?:[A-Z]{2}|[A-Z][0-9])?\b"#

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

    // Context used to tell a billed procedure code from any other look-alike token.
    private static let amountPattern = #"\$\s?\d|\b\d{1,3}(?:,\d{3})*\.\d{2}\b"#
    /// A diagnosis label, optionally followed by earlier codes in the same list
    /// ("DX: E1165, "). What follows is a diagnosis, even when an undotted
    /// ICD-10 code happens to be shaped like an HCPCS code.
    private static let diagnosisLabelPattern =
        #"(?i)\b(?:dx|diag\w*|icd(?:-?\s?10)?(?:-cm)?)\b\s*(?:codes?)?\s*[.:#]*\s*(?:[A-Z][0-9][0-9A-Z.]*[,;\s]+)*$"#
    private static let zipPrefixPattern =
        #"\b(?:AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)[.,]?\s+$"#
    private static let identifierLabelPattern =
        #"(?i)\b(?:account|acct|receipt|invoice|statement|claim|mrn|member|policy|group|subscriber|reference|ref|confirmation|check|zip|box|suite|ste|apt|unit|room|rm|bed|lot|ext|npi|tin|id)\b\s*(?:number|num|no|code)?\s*[.:#]*\s*$"#
    private static let codeLabelPattern =
        #"(?i)\b(?:cpt|hcpcs|procedures?|proc|codes?)\b\s*(?:codes?)?\s*[.:#]*\s*$"#

    /// Procedure codes (CPT and HCPCS) in `text`, in order, repeats included.
    /// The patterns find the candidates; a candidate is kept only when it reads
    /// as a billed code: it is a known code, it is labelled as one, or its line
    /// carries a charge. ZIP codes, labelled identifiers (account, receipt,
    /// claim…), diagnoses, pieces of hyphenated IDs and money amounts are
    /// dropped, since those repeat in page headers and would raise false
    /// cross-page conflicts.
    static func procedureCodes(in text: String, knownCodes: Set<String>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: procedurePattern) else { return [] }
        var codes: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let lineHasCharge = line.range(of: amountPattern, options: .regularExpression) != nil
            for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let code = nsLine.substring(with: match.range(at: 1))
                let before = nsLine.substring(to: match.range.location)
                let after = nsLine.substring(from: match.range.location + match.range.length)

                let isPartOfNumberOrID = before.hasSuffix("$") || before.hasSuffix("$ ")
                    || before.hasSuffix("-")
                    || after.range(of: #"^(?:\.\d|-\d{4}\b)"#, options: .regularExpression) != nil
                if isPartOfNumberOrID { continue }
                if before.range(of: zipPrefixPattern, options: .regularExpression) != nil { continue }
                if before.range(of: identifierLabelPattern, options: .regularExpression) != nil { continue }
                if before.range(of: diagnosisLabelPattern, options: .regularExpression) != nil { continue }

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

// MARK: - Bill details for import

/// Used by the apps when a saved scan is turned into a bill. A scan is one
/// block of text per page, not the separate provider / patient / insurance
/// boxes the apps' bill reader works from, so only what is clearly marked on
/// the page is taken and the rest is left for the person to fill in.
extension BillCodeAnalyzer {

    /// Details printed with a label ("Patient: …", "Member ID: …"). Nothing
    /// here is guessed from unlabelled lines.
    struct LabelledFields: Equatable, Sendable {
        var patientName = ""
        var accountNumber = ""
        var dateOfBirth = ""
        var serviceDate: Date?
        var insuranceCarrier = ""
        var memberID = ""
        var groupNumber = ""
        var policyNumber = ""
    }

    private enum Field: CaseIterable {
        case patientName, accountNumber, dateOfBirth, serviceDate
        case insuranceCarrier, memberID, groupNumber, policyNumber

        /// The label, without the "#", "No." or colon that may follow it.
        var label: String {
            switch self {
            case .patientName:      return #"patient(?:\s+name)?"#
            case .accountNumber:    return #"acc(?:oun)?t"#
            case .dateOfBirth:      return #"date\s+of\s+birth|birth\s*date|d\.?o\.?b\.?"#
            case .serviceDate:      return #"dates?\s+of\s+service|service\s+date|d\.?o\.?s\.?"#
            case .insuranceCarrier: return #"(?:primary\s+)?insurance(?:\s+(?:carrier|company|name))?|carrier|pay[eo]r"#
            case .memberID:         return #"(?:member|subscriber)"#
            case .groupNumber:      return #"group"#
            case .policyNumber:     return #"policy"#
            }
        }
    }

    private static let labelSuffix = #"\s*(?:number|num|no\.?|id|#)?\s*[:#]\s*"#
    private static let anyLabelPattern = #"(?i)\b[a-z][a-z .#/]{1,28}:"#
    private static let numericDatePattern = #"\b(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})\b"#
    private static let isoDatePattern = #"\b(\d{4})-(\d{2})-(\d{2})\b"#
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun",
                                     "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let namedDatePattern =
        #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b"#

    static func labelledFields(in text: String) -> LabelledFields {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var fields = LabelledFields()

        for field in Field.allCases {
            guard let regex = try? NSRegularExpression(
                pattern: #"(?i)(?<![a-z])(?:"# + field.label + ")" + labelSuffix) else { continue }
            search: for (index, line) in lines.enumerated() {
                let nsLine = line as NSString
                for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                    var value = nsLine.substring(from: match.range.location + match.range.length)
                    // OCR often puts the value on the line below its label.
                    if value.isEmpty, index + 1 < lines.count,
                       lines[index + 1].range(of: anyLabelPattern, options: .regularExpression) == nil {
                        value = lines[index + 1]
                    }
                    if set(field, from: value, in: &fields) { break search }
                }
            }
        }
        return fields
    }

    /// Stores a value that looks right for `field`; false when it does not.
    private static func set(_ field: Field, from raw: String, in fields: inout LabelledFields) -> Bool {
        // A value ends where the next label on the same line starts, or at a
        // column gap.
        var value = raw
        if let next = value.range(of: anyLabelPattern, options: .regularExpression) {
            value = String(value[..<next.lowerBound])
        }
        if let gap = value.range(of: #"\s{3,}|\t"#, options: .regularExpression) {
            value = String(value[..<gap.lowerBound])
        }
        value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return false }

        switch field {
        case .patientName:
            let words = value.split(separator: " ")
            guard (2...5).contains(words.count), value.count <= 40,
                  value.rangeOfCharacter(from: .decimalDigits) == nil,
                  words.allSatisfy({ $0.first?.isLetter == true }) else { return false }
            fields.patientName = value
        case .accountNumber:
            guard let token = identifier(in: value) else { return false }
            fields.accountNumber = token
        case .memberID:
            guard let token = identifier(in: value) else { return false }
            fields.memberID = token
        case .groupNumber:
            guard let token = identifier(in: value) else { return false }
            fields.groupNumber = token
        case .policyNumber:
            guard let token = identifier(in: value) else { return false }
            fields.policyNumber = token
        case .dateOfBirth:
            guard let found = firstDate(in: value) else { return false }
            fields.dateOfBirth = found.text
        case .serviceDate:
            guard let found = firstDate(in: value) else { return false }
            fields.serviceDate = found.date
        case .insuranceCarrier:
            guard value.count <= 60, value.contains(where: \.isLetter), !value.contains("$"),
                  value.range(of: amountPattern, options: .regularExpression) == nil else { return false }
            fields.insuranceCarrier = value
        }
        return true
    }

    /// The first token that reads as an ID: letters, digits and hyphens, with
    /// at least one digit ("Group: Riverside" is not a group number).
    private static func identifier(in value: String) -> String? {
        guard let range = value.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{2,24}(?![A-Za-z0-9-])"#,
                                      options: .regularExpression) else { return nil }
        let token = String(value[range])
        return token.contains(where: \.isNumber) ? token : nil
    }

    /// The first date in `text` (US month-first, ISO, or "Sep 18, 2026").
    private static func firstDate(in text: String) -> (text: String, date: Date)? {
        func groups(_ pattern: String) -> (whole: String, parts: [String])? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            else { return nil }
            let ns = text as NSString
            return (ns.substring(with: match.range),
                    (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) })
        }
        var whole = ""
        var components = DateComponents()
        if let (matched, parts) = groups(numericDatePattern) {
            whole = matched
            components.month = Int(parts[0])
            components.day = Int(parts[1])
            var year = Int(parts[2]) ?? 0
            if parts[2].count == 2 {
                // Two-digit years: this century unless that would be in the future.
                let thisYear = Calendar.current.component(.year, from: Date())
                year += 2000
                if year > thisYear { year -= 100 }
            }
            components.year = year
        } else if let (matched, parts) = groups(isoDatePattern) {
            whole = matched
            components.year = Int(parts[0])
            components.month = Int(parts[1])
            components.day = Int(parts[2])
        } else if let (matched, parts) = groups(namedDatePattern),
                  let month = monthNames.firstIndex(of: parts[0].lowercased()) {
            whole = matched
            components.month = month + 1
            components.day = Int(parts[1])
            components.year = Int(parts[2])
        } else {
            return nil
        }
        guard let month = components.month, (1...12).contains(month),
              let day = components.day, (1...31).contains(day),
              let year = components.year, (1900...2200).contains(year),
              let date = Calendar.current.date(from: components) else { return nil }
        return (whole, date)
    }

    // The provider's name and address usually head the first page.
    private static let practicePattern =
        #"(?i)\b(?:hospitals?|clinics?|medical\s+(?:cent(?:er|re)|group|assoc\w*|practice|services)|health\s*(?:system|cent(?:er|re)|care|services|partners|network)|physicians?|associates|radiology|laborator(?:y|ies)|pathology|surg(?:ery|ical)|urgent\s+care|pediatrics?|orthopa?edics?|cardiology|dermatology|imaging|family\s+(?:medicine|practice|health)|internal\s+medicine|wellness|dental|m\.?d\.?)(?![a-z])"#
    private static let contactLabelPattern = #"(?i)^(?:phone|tel(?:ephone)?|fax)\b"#

    /// The provider's letterhead: the line near the top of the page that names
    /// a practice, with the address and phone lines under it. Empty when no
    /// such line comes before the first labelled value or charge, so a web
    /// page's menu is not taken for a provider.
    static func letterhead(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        func isContact(_ line: String) -> Bool {
            line.range(of: contactLabelPattern, options: .regularExpression) != nil
        }
        func endsLetterhead(_ line: String) -> Bool {
            if isContact(line) { return false }
            return line.range(of: anyLabelPattern, options: .regularExpression) != nil
                || line.range(of: amountPattern, options: .regularExpression) != nil
                || line.range(of: #"^(?:[0-9]{5}|[A-Z][0-9]{4})(?:[A-Z]{2}|[A-Z][0-9])?\s"#,
                              options: .regularExpression) != nil
        }

        var block: [String] = []
        for line in lines.prefix(12) {
            if endsLetterhead(line) { break }
            if block.isEmpty {
                if line.range(of: practicePattern, options: .regularExpression) != nil { block.append(line) }
            } else if block.count < 5, isContact(line) || line.contains(where: \.isNumber) {
                block.append(line)      // street, city and ZIP, phone
            } else {
                break
            }
        }
        return block.joined(separator: "\n")
    }
}
